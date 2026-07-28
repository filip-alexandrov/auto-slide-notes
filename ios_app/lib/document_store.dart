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

/// Width of the stored preview image in pixels.
const double _thumbWidth = 360;

/// Previews are cropped below this height / width so very tall pages
/// don't turn into thin strips in the library.
const double _thumbMaxAspect = 1.5;

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

  /// Width / height of [thumbnail], read from the PNG header.
  double? get thumbnailAspect {
    final t = thumbnail;
    if (t == null || t.length < 24) return null;
    final header = ByteData.sublistView(t);
    final w = header.getUint32(16), h = header.getUint32(20);
    return w > 0 && h > 0 ? w / h : null;
  }
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

  /// Reads the metadata the library needs; null if this isn't a note.
  Future<NoteSummary?> summary() async {
    Map<String, dynamic>? meta;
    try {
      if (await _metaFile.exists()) {
        meta =
            jsonDecode(await _metaFile.readAsString()) as Map<String, dynamic>;
      }
    } catch (_) {}
    if (meta == null) {
      // Notes written before meta.json existed.
      if (!await _docFile.exists()) return null;
      final doc = await load();
      final stat = await _docFile.stat();
      meta = {
        'title': doc.title,
        'created': doc.created.toIso8601String(),
        'modified': stat.modified.toIso8601String(),
        'pageCount': doc.pages.length,
      };
    }
    final thumb = await _thumbFile.exists()
        ? await _thumbFile.readAsBytes()
        : null;
    final modified =
        DateTime.tryParse(meta['modified'] as String? ?? '') ?? DateTime.now();
    return NoteSummary(
      id: id,
      title: meta['title'] as String? ?? 'Notes',
      created: DateTime.tryParse(meta['created'] as String? ?? '') ?? modified,
      modified: modified,
      pageCount: meta['pageCount'] as int? ?? 0,
      thumbnail: thumb,
    );
  }

  /// Renders the first page into `thumbnail.png`: just the slide (with the
  /// ink on it) when the page has one, otherwise the whole blank page.
  Future<void> saveThumbnail(NoteDocument doc) async {
    if (doc.pages.isEmpty) {
      if (await _thumbFile.exists()) await _thumbFile.delete();
      return;
    }
    final page = doc.pages.first;
    final rect = page.imageRect;
    final area = page.imageFile != null && rect != null
        ? rect
        : Offset.zero & Size(page.width, page.height);
    final scale = _thumbWidth / area.width;
    final height = (_thumbWidth * area.height / area.width).clamp(
      1.0,
      _thumbWidth * _thumbMaxAspect,
    );

    ui.Image? slide;
    if (page.imageFile != null && rect != null) {
      final file = imageFile(page.imageFile!);
      if (await file.exists()) {
        final codec = await ui.instantiateImageCodec(
          await file.readAsBytes(),
          targetWidth: (rect.width * scale).round().clamp(1, 2048),
        );
        slide = (await codec.getNextFrame()).image;
        codec.dispose();
      }
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final bounds = Rect.fromLTWH(0, 0, _thumbWidth, height);
    canvas
      ..clipRect(bounds)
      ..drawRect(bounds, Paint()..color = const Color(0xFFFFFFFF))
      ..translate(-area.left * scale, -area.top * scale);
    if (slide != null) {
      canvas.drawImageRect(
        slide,
        Offset.zero & Size(slide.width.toDouble(), slide.height.toDouble()),
        Rect.fromLTWH(
          rect!.left * scale,
          rect.top * scale,
          rect.width * scale,
          rect.height * scale,
        ),
        Paint()..filterQuality = FilterQuality.medium,
      );
      slide.dispose();
    }
    canvas.scale(scale);
    // Same order as on screen: highlighter under pen.
    for (final tool in [StrokeTool.highlighter, StrokeTool.pen]) {
      for (final s in page.strokes) {
        if (s.tool == tool) paintStroke(canvas, s);
      }
    }

    final image = await recorder.endRecording().toImage(
      _thumbWidth.round(),
      height.round(),
    );
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (png == null) return;
    final tmp = File('${_thumbFile.path}.tmp');
    await tmp.writeAsBytes(png.buffer.asUint8List(), flush: true);
    await tmp.rename(_thumbFile.path);
  }

  static int _counter = 0;
  static String newPageId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${_counter++}';
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

  /// Whether the library preview may be out of date.
  bool _thumbStale = true;

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
