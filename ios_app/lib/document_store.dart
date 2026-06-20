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

const _lastSlideIdKey = 'lastSlideId';
const _lastOpenedKey = 'lastOpenedNote';

/// What the library shows for a note without opening it.
class NoteSummary {
  NoteSummary({
    required this.id,
    required this.title,
    required this.created,
    required this.modified,
    required this.pageCount,
    this.thumbnail,
  });

  final String id;
  final String title;
  final DateTime created;
  final DateTime modified;
  final int pageCount;

  /// PNG of the first slide (or page), null for empty notes.
  final Uint8List? thumbnail;
}

/// All notes, stored locally as `Documents/notes/<id>/` folders, each with
/// `document.json`, `meta.json`, `thumbnail.png` and an `images/` directory.
///
/// Also keeps the server slide cursor: it is global (not per note) so that
/// a slide is imported exactly once, into whichever note is open.
class NoteLibrary {
  NoteLibrary._(this.root, this._prefs);

  final Directory root;
  final SharedPreferences _prefs;

  static Future<NoteLibrary> open() async {
    final prefs = await SharedPreferences.getInstance();
    final docs = await getApplicationDocumentsDirectory();
    final lib = NoteLibrary._(Directory('${docs.path}/notes'), prefs);
    await lib._migrateSingleNotebook(Directory('${docs.path}/notebook'));
    await lib.root.create(recursive: true);
    return lib;
  }

  /// Highest server slide id already imported into any note.
  int get lastSlideId => _prefs.getInt(_lastSlideIdKey) ?? 0;
  set lastSlideId(int id) => _prefs.setInt(_lastSlideIdKey, id);

  /// The note that was open last, reopened on launch.
  String? get lastOpenedId {
    final id = _prefs.getString(_lastOpenedKey);
    return id != null && _dir(id).existsSync() ? id : null;
  }

  set lastOpenedId(String? id) => id == null
      ? _prefs.remove(_lastOpenedKey)
      : _prefs.setString(_lastOpenedKey, id);

  Directory _dir(String id) => Directory('${root.path}/$id');

  DocumentStore storeFor(String id) => DocumentStore._(_dir(id));

  /// Earlier versions kept a single notebook in `Documents/notebook`;
  /// it becomes the first note of the library.
  Future<void> _migrateSingleNotebook(Directory old) async {
    final oldDoc = File('${old.path}/document.json');
    if (await root.exists() || !await oldDoc.exists()) return;
    try {
      final json = jsonDecode(await oldDoc.readAsString());
      final cursor = (json as Map<String, dynamic>)['lastSlideId'] as int?;
      if (cursor != null && !_prefs.containsKey(_lastSlideIdKey)) {
        lastSlideId = cursor;
      }
    } catch (_) {
      // Unreadable: DocumentStore.load sets it aside as before.
    }
    await root.create(recursive: true);
    final id = newId();
    await old.rename(_dir(id).path);
    lastOpenedId = id;
  }

  Future<List<NoteSummary>> list() async {
    final notes = <NoteSummary>[];
    if (!await root.exists()) return notes;
    await for (final entity in root.list()) {
      if (entity is! Directory) continue;
      final summary = await DocumentStore._(entity).summary();
      if (summary != null) notes.add(summary);
    }
    return notes;
  }

  Future<String> create(String title) async {
    final id = newId();
    final store = storeFor(id);
    await store.imagesDir.create(recursive: true);
    await store.save(NoteDocument(title: title));
    return id;
  }

  Future<void> rename(String id, String title) async {
    final store = storeFor(id);
    final doc = await store.load();
    doc.title = title;
    await store.save(doc, touch: false);
  }

  Future<String> duplicate(String id, String title) async {
    final copy = newId();
    await _copyDir(_dir(id), _dir(copy));
    final store = storeFor(copy);
    final doc = await store.load();
    doc
      ..title = title
      ..created = DateTime.now();
    await store.save(doc);
    return copy;
  }

  Future<void> delete(String id) async {
    if (_prefs.getString(_lastOpenedKey) == id) lastOpenedId = null;
    final dir = _dir(id);
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  static Future<void> _copyDir(Directory from, Directory to) async {
    await to.create(recursive: true);
    await for (final e in from.list()) {
      final name = _basename(e);
      if (e is Directory) {
        await _copyDir(e, Directory('${to.path}/$name'));
      } else if (e is File) {
        await e.copy('${to.path}/$name');
      }
    }
  }

  static int _counter = 0;
  static String newId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${_counter++}';
}

String _basename(FileSystemEntity e) =>
    e.uri.pathSegments.lastWhere((s) => s.isNotEmpty);

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
