import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'page_canvas.dart' show paintStroke;

/// Persists one note as `document.json` plus slide images in its folder.
class DocumentStore {
  DocumentStore._(this.root);

  final Directory root;

  String get id => _basename(root);
  Directory get imagesDir => Directory('${root.path}/images');
  File get _docFile => File('${root.path}/document.json');
  File get _metaFile => File('${root.path}/meta.json');
  File get _thumbFile => File('${root.path}/thumbnail.png');

  File imageFile(String name) => File('${imagesDir.path}/$name');

  Future<NoteDocument> load() async {
    await imagesDir.create(recursive: true);
    if (await _docFile.exists()) {
      try {
        final json = jsonDecode(await _docFile.readAsString());
        final doc = NoteDocument.fromJson(json as Map<String, dynamic>);
        await _collectStrayImages(doc);
        return doc;
      } catch (_) {
        // Keep the unreadable file around for manual recovery.
        await _docFile.rename('${_docFile.path}.corrupt');
      }
    }
    return NoteDocument(title: 'Notes');
  }

  /// Writes the document and its library metadata. [touch] updates the
  /// modification date (not wanted for a plain rename).
  Future<void> save(NoteDocument doc, {bool touch = true}) async {
    final previous = touch ? null : (await summary())?.modified;
    await _writeAtomic(_docFile, jsonEncode(doc.toJson()));
    await _writeAtomic(
      _metaFile,
      jsonEncode({
        'title': doc.title,
        'created': doc.created.toIso8601String(),
        'modified': (previous ?? DateTime.now()).toIso8601String(),
        'pageCount': doc.pages.length,
      }),
    );
  }

  static int _tmpCounter = 0;

  static Future<void> _writeAtomic(File file, String contents) async {
    // A unique temp name per write: two saves of the same note must never
    // share (and rename away) each other's temp file.
    final tmp = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}_${_tmpCounter++}.tmp',
    );
    await tmp.writeAsString(contents, flush: true);
    await tmp.rename(file.path);
  }
}

/// Coalesces rapid document changes into a single write.
class AutoSaver {
  AutoSaver(this.store, this.doc) {
    doc.addListener(_schedule);
  }

  final DocumentStore store;
  final NoteDocument doc;
  Timer? _timer;

  /// Saves run strictly one after another on this chain. It never holds an
  /// error, so one failed save can't block the ones after it.
  Future<void> _chain = Future.value();

  void _schedule() {
    _thumbStale = true;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 800), flush);
  }

  /// Saves the current state; with [thumbnail] also refreshes the library
  /// preview (done when leaving the note rather than on every autosave).
  /// Overlapping calls are queued, never run in parallel.
  Future<void> flush({bool thumbnail = false}) {
    _timer?.cancel();
    _timer = null;
    return _chain = _chain.then((_) => _save(thumbnail));
  }

  Future<void> _save(bool thumbnail) async {
    try {
      await store.save(doc);
    } catch (e) {
      // Keep the change pending and try again shortly.
      debugPrint('Autosave failed, retrying: $e');
      _timer?.cancel();
      _timer = Timer(const Duration(seconds: 2), flush);
      return;
    }
    if (thumbnail && _thumbStale) {
      _thumbStale = false;
      try {
        await store.saveThumbnail(doc);
      } catch (_) {
        _thumbStale = true; // A missing preview must not block saving.
      }
    }
  }

  void dispose() {
    doc.removeListener(_schedule);
    _timer?.cancel();
  }
}
