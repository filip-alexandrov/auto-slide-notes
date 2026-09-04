import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ipad_notes/document_store.dart';
import 'package:ipad_notes/models.dart';
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
    tmp = await Directory.systemTemp.createTemp('autosave_test');
    PathProviderPlatform.instance = _FakePaths(tmp.path);
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() => tmp.delete(recursive: true));

  NotePage page() => NotePage(id: DocumentStore.newPageId(), aspect: 1);

  // Going to the background fires "inactive" and "paused" right after each
  // other, and each flushes. Those saves must not collide, and one failed
  // save must not stop all later ones.
  test('overlapping flushes keep saving every later change', () async {
    final library = await NoteLibrary.open();
    final store = library.storeFor(await library.create('Lecture'));
    final doc = await store.load();
    final saver = AutoSaver(store, doc);

    for (var round = 0; round < 20; round++) {
      doc.appendPage(page());
      await Future.wait([saver.flush(), saver.flush(thumbnail: true)]);
    }
    doc.appendPage(page());
    await saver.flush();

    expect((await store.load()).pages.length, 21);
    saver.dispose();
  });

  test(
    'deleted pages survive in the recycle bin and can be restored',
    () async {
      final library = await NoteLibrary.open();
      final store = library.storeFor(await library.create('Lecture'));
      final doc = await store.load();
      final a = page(), b = page(), c = page();
      doc
        ..appendPage(a)
        ..appendPage(b)
        ..appendPage(c);
      doc.trashPage(b);
      await store.save(doc);

      // The bin is part of the saved note.
      final reloaded = await store.load();
      expect(reloaded.pages.map((p) => p.id), [a.id, c.id]);
      expect(reloaded.trash.single.page.id, b.id);
      expect(reloaded.trash.single.index, 1);

      reloaded.restorePage(reloaded.trash.single);
      expect(reloaded.pages.map((p) => p.id), [a.id, b.id, c.id]);
      expect(reloaded.trash, isEmpty);
    },
  );

  test('slide images without a page show up in the bin', () async {
    final library = await NoteLibrary.open();
    final store = library.storeFor(await library.create('Lecture'));
    final doc = await store.load();
    // A 4x2 PNG header is all the bin needs to size the page.
    final png = [
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, //
      0x49, 0x48, 0x44, 0x52, 0, 0, 0, 4, 0, 0, 0, 2, 8, 2, 0, 0, 0,
    ];
    await store.imageFile('kept.png').writeAsBytes(png);
    await store.imageFile('lost.png').writeAsBytes(png);
    doc.appendPage(NotePage(id: 'p', aspect: 0.5, imageFile: 'kept.png'));
    await store.save(doc);

    final reloaded = await store.load();
    expect(reloaded.pages.single.imageFile, 'kept.png');
    expect(reloaded.trash.single.page.imageFile, 'lost.png');
    expect(reloaded.trash.single.page.aspect, closeTo(0.5, 1e-9));
  });
}
