import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ipad_notes/document_store.dart';
import 'package:ipad_notes/notebook_screen.dart';
import 'package:ipad_notes/page_canvas.dart';
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
    tmp = await Directory.systemTemp.createTemp('notes_test');
    PathProviderPlatform.instance = _FakePaths(tmp.path);
    SharedPreferences.setMockInitialValues({});
    final nb = Directory('${tmp.path}/notes/n1/images')
      ..createSync(recursive: true);
    File('${nb.parent.path}/document.json').writeAsStringSync(
      jsonEncode({
        'title': 'Notes',
        'pages': [
          for (final id in ['a', 'b', 'c'])
            {'id': id, 'width': 1000, 'height': 1414, 'strokes': []},
        ],
      }),
    );
  });

  tearDown(() => tmp.delete(recursive: true));

  testWidgets('pinching zooms pages and reset restores them', (tester) async {
    tester.view.physicalSize = const Size(1668, 2420);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      final library = await NoteLibrary.open();
      await tester.pumpWidget(
        MaterialApp(
          home: NotebookScreen(library: library, noteId: 'n1'),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();

    final canvas = find.byType(PageCanvas).first;
    final before = tester.getSize(canvas).width;

    final center = tester.getCenter(find.byType(ListView));
    final a = await tester.createGesture(kind: PointerDeviceKind.touch);
    final b = await tester.createGesture(kind: PointerDeviceKind.touch);
    await a.down(center - const Offset(0, 50));
    await b.down(center + const Offset(0, 50));
    await tester.pump();
    for (var i = 1; i <= 10; i++) {
      await a.moveTo(center - Offset(0, 50.0 + 5 * i));
      await b.moveTo(center + Offset(0, 50.0 + 5 * i));
      await tester.pump();
    }
    await a.up();
    await b.up();
    await tester.pumpAndSettle();

    // Finger span went from 100 to 200 -> 200 %.
    expect(find.text('200%'), findsOneWidget);
    expect(
      tester.getSize(find.byType(PageCanvas).first).width,
      closeTo(before * 2, 1),
    );

    // The point between the fingers stays under them: the middle of the
    // screen still shows a page, not empty space.
    expect(
      find.byWidgetPredicate((w) => w is PageCanvas).hitTestable(),
      findsWidgets,
    );

    await tester.tap(find.text('200%'));
    await tester.pumpAndSettle();
    expect(find.text('200%'), findsNothing);
    expect(
      tester.getSize(find.byType(PageCanvas).first).width,
      closeTo(before, 1),
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('delete page is undoable, new pages are square', (tester) async {
    tester.view.physicalSize = const Size(1668, 2420);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      final library = await NoteLibrary.open();
      await tester.pumpWidget(
        MaterialApp(
          home: NotebookScreen(library: library, noteId: 'n1'),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();

    expect(find.text('1 / 3'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Delete page').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete page').first);
    await tester.pumpAndSettle();
    expect(find.textContaining(' / 2'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.textContaining(' / 3'), findsOneWidget);

    // Deleted pages go to the recycle bin and come back from there.
    await tester.ensureVisible(find.byTooltip('Delete page').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete page').first);
    await tester.pumpAndSettle();
    expect(find.textContaining(' / 2'), findsOneWidget);
    await tester.tap(find.byType(PopupMenuButton<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recycle bin (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    expect(find.textContaining(' / 3'), findsOneWidget);

    // On narrower screens the toolbar scrolls; bring the button into view.
    await tester.ensureVisible(find.byTooltip('Add blank page'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add blank page'));
    await tester.pumpAndSettle();
    expect(find.text('1 / 4'), findsNothing); // jumped to the new page
    final last = tester.getSize(find.byType(PageCanvas).last);
    expect(last.width, closeTo(last.height, 1));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('+ buttons stay in place when pressed', (tester) async {
    tester.view.physicalSize = const Size(1668, 2420);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      final library = await NoteLibrary.open();
      await tester.pumpWidget(
        MaterialApp(
          home: NotebookScreen(library: library, noteId: 'n1'),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();

    for (final side in ['top', 'left', 'right', 'bottom']) {
      final button = find.byTooltip('Add space ($side)').first;
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      final before = tester.getCenter(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(
        tester.getCenter(button).dy,
        closeTo(before.dy, 0.5),
        reason: '$side + moved vertically',
      );
      expect(
        tester.getCenter(button).dx,
        closeTo(before.dx, 0.5),
        reason: '$side + moved horizontally',
      );
    }

    await tester.pumpWidget(const SizedBox());
  });
}
