import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ipad_notes/document_store.dart';
import 'package:ipad_notes/library_screen.dart';
import 'package:ipad_notes/models.dart';
import 'package:ipad_notes/notebook_screen.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePaths extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _FakePaths(this.dir);
  final String dir;

  @override
  Future<String?> getApplicationDocumentsPath() async => dir;

  @override
  Future<String?> getTemporaryPath() async => dir;
}

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('library_test');
    PathProviderPlatform.instance = _FakePaths(tmp.path);
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() => tmp.delete(recursive: true));

  test(
    'old single notebook becomes a note and keeps its slide cursor',
    () async {
      final old = Directory('${tmp.path}/notebook/images')
        ..createSync(recursive: true);
      File('${old.parent.path}/document.json').writeAsStringSync(
        jsonEncode({
          'title': 'Lecture',
          'lastSlideId': 7,
          'pages': [
            {'id': 'a', 'width': 1000, 'height': 1414, 'strokes': []},
          ],
        }),
      );

      final library = await NoteLibrary.open();
      expect(library.lastSlideId, 7);
      expect(Directory('${tmp.path}/notebook').existsSync(), isFalse);
      final notes = await library.list();
      expect(notes.single.title, 'Lecture');
      expect(notes.single.pageCount, 1);
      expect(library.lastOpenedId, notes.single.id);
    },
  );

  test('create, rename, duplicate, delete', () async {
    final library = await NoteLibrary.open();
    final id = await library.create('First');
    await library.rename(id, 'Renamed');
    final copy = await library.duplicate(id, 'Renamed copy');

    var titles = (await library.list()).map((n) => n.title).toSet();
    expect(titles, {'Renamed', 'Renamed copy'});

    await library.delete(id);
    final notes = await library.list();
    expect(notes.single.id, copy);
  });

  test('thumbnail renders the first page with ink', () async {
    final library = await NoteLibrary.open();
    final id = await library.create('Ink');
    final store = library.storeFor(id);
    final doc = await store.load();
    doc.appendPage(
      NotePage(id: 'p', aspect: 1)..addStroke(
        Stroke(
          tool: StrokeTool.pen,
          color: 0xFF000000,
          width: 20,
          points: [const Offset(100, 100), const Offset(900, 900)],
        ),
      ),
    );
    final saver = AutoSaver(store, doc);
    await saver.flush(thumbnail: true);
    saver.dispose();

    final note = (await library.list()).single;
    expect(note.pageCount, 1);
    expect(note.thumbnail, isNotNull);
    // PNG signature.
    expect(note.thumbnail!.sublist(1, 4), utf8.encode('PNG'));
  });
}
