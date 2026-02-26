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
