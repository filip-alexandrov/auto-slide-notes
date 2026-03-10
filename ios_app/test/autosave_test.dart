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
}
