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

  test('preview shows only the first slide, at its own shape', () async {
    final library = await NoteLibrary.open();
    final id = await library.create('Slides');
    final store = library.storeFor(id);
    final doc = await store.load();

    // A 16:9 slide image.
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 160, 90),
      Paint()..color = const Color(0xFF1E5EFF),
    );
    final img = await recorder.endRecording().toImage(160, 90);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    await store.imageFile('s.png').writeAsBytes(png!.buffer.asUint8List());

    // White space added below the slide must not show up in the preview.
    final page = NotePage(id: 'p', aspect: 90 / 160, imageFile: 's.png')
      ..extend(PageSide.bottom, 800);
    doc.appendPage(page);
    await store.saveThumbnail(doc);
    var note = (await library.list()).single;
    expect(note.thumbnailAspect, closeTo(16 / 9, 0.02));

    // A blank page is shown whole.
    doc.pages
      ..clear()
      ..add(NotePage(id: 'b', aspect: 1));
    await store.saveThumbnail(doc);
    note = (await library.list()).single;
    expect(note.thumbnailAspect, closeTo(1, 0.01));
  });

  testWidgets('library lists notes, opens one and returns', (tester) async {
    tester.view.physicalSize = const Size(2048, 1536);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      final library = await NoteLibrary.open();
      await library.create('Biology');
      await library.create('History');
      await tester.pumpWidget(const MaterialApp(home: LibraryScreen()));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();

    expect(find.text('All Notes'), findsOneWidget);
    expect(find.text('Biology'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'bio');
    await tester.pump();
    expect(find.text('History'), findsNothing);

    await tester.runAsync(() async {
      await tester.tap(find.text('Biology'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    expect(find.byType(NotebookScreen), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.text('Notes'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    expect(find.byType(NotebookScreen), findsNothing);
    expect(find.text('Biology'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
