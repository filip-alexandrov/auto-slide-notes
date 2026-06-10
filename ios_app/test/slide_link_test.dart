import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ipad_notes/document_store.dart';
import 'package:ipad_notes/models.dart';
import 'package:ipad_notes/slide_link.dart';
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

/// A 4×2 px PNG, as the Mac would send it.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAQAAAACCAIAAADwyuo0AAAAEElEQVR4nGP4z8AARwzIHABvqgf5gNwAKAAAAABJRU5ErkJggg==',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  final native = <String>[];

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('link_test');
    PathProviderPlatform.instance = _FakePaths(tmp.path);
    SharedPreferences.setMockInitialValues({});
    native.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('ipad_notes/link'), (
          call,
        ) async {
          native.add(call.method);
          return null;
        });
  });

  tearDown(() => tmp.delete(recursive: true));

  Future<void> fromNative(String method, Object args) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'ipad_notes/link',
          const StandardMethodCodec().encodeMethodCall(
            MethodCall(method, args),
          ),
          (_) {},
        );
  }

  testWidgets('slides pushed by the Mac become pages in order', (tester) async {
    await tester.runAsync(() async {
      final library = await NoteLibrary.open();
      final id = await library.create('Lecture');
      final store = library.storeFor(id);
      final doc = await store.load();
      final added = <NotePage>[];
      final link = SlideLink(store: store, doc: doc, onSlideAdded: added.add);

      await link.start();
      expect(native, ['start']);
      expect(link.state, LinkState.searching);

      await fromNative('status', {'state': 'connected', 'peer': 'Studio Mac'});
      expect(link.state, LinkState.connected);
      expect(link.peer, 'Studio Mac');

      await fromNative('slide', {'seq': 41, 'bytes': _png});
      await fromNative('slide', {'seq': 42, 'bytes': _png});
      // Imports are chained; wait for both to land.
      for (var i = 0; i < 50 && added.length < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      expect(added.map((p) => p.slideId), [41, 42]);
      expect(doc.pages.last.slideId, 42);
      expect(added.first.aspect, closeTo(0.5, 1e-9));
      expect(store.imageFile(added.first.imageFile!).existsSync(), isTrue);

      await link.stop();
      expect(native.last, 'stop');
      expect(link.state, LinkState.off);
      link.dispose();
    });
  });
}
