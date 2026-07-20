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
}
