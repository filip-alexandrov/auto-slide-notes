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
}
