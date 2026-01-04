import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:ipad_notes/ink.dart';
import 'package:ipad_notes/models.dart';

void main() {
  NotePage slidePage() => NotePage(
    id: 'p',
    aspect: 0.5,
    imageFile: 'a.png',
    strokes: [
      Stroke(
        tool: StrokeTool.pen,
        color: 0xFF000000,
        width: 3,
        points: [const Offset(10, 20)],
      ),
    ],
  );

  test('extending left/top shifts image and ink, right/bottom does not', () {
    final page = slidePage();
    page.extend(PageSide.left, 100);
    page.extend(PageSide.top, 50);
    page.extend(PageSide.right, 100);
    page.extend(PageSide.bottom, 50);

    expect(page.width, 1200);
    expect(page.height, 600);
    expect(page.imageRect, const Rect.fromLTWH(100, 50, 1000, 500));
    expect(page.strokes.single.points.single, const Offset(110, 70));
  });

  test('negative extend undoes it', () {
    final page = slidePage();
    page.extend(PageSide.left, 100);
    page.extend(PageSide.left, -100);
    expect(page.width, 1000);
    expect(page.imageRect, const Rect.fromLTWH(0, 0, 1000, 500));
    expect(page.strokes.single.points.single, const Offset(10, 20));
  });
}
