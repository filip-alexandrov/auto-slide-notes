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

  test('round-trips through JSON and reads old aspect-only pages', () {
    final page = slidePage()..extend(PageSide.top, 50);
    final back = NotePage.fromJson(page.toJson());
    expect(back.height, 550);
    expect(back.imageRect, const Rect.fromLTWH(0, 50, 1000, 500));

    final old = NotePage.fromJson({
      'id': 'o',
      'aspect': 0.5,
      'imageFile': 'x.png',
      'strokes': [],
    });
    expect(old.width, 1000);
    expect(old.height, 500);
    expect(old.imageRect, const Rect.fromLTWH(0, 0, 1000, 500));
  });

  test('only white space can be removed', () {
    final page = slidePage();
    expect(page.removableOn(PageSide.left), 0);
    page.extend(PageSide.left, 100);
    expect(page.removableOn(PageSide.left), 100);
    expect(page.removableOn(PageSide.right), 0);

    final blank = NotePage(id: 'b', aspect: 1);
    expect(blank.removableOn(PageSide.bottom), 1000 - NotePage.minSize);
  });

  test('finishing smoothing keeps endpoints and flattens zig-zags', () {
    final zigzag = [
      for (var i = 0; i < 9; i++) Offset(i * 10.0, i.isEven ? 0 : 6),
    ];
    final smooth = relax(zigzag, 2);
    expect(smooth.first, zigzag.first);
    expect(smooth.last, zigzag.last);
    double swing(List<Offset> p) => p
        .skip(1)
        .take(p.length - 2)
        .map((o) => (o.dy - 3).abs())
        .reduce((a, b) => a > b ? a : b);
    expect(swing(smooth), lessThan(swing(zigzag) / 2));
  });

  test('stabilizer lags more at higher smoothing', () {
    Offset step(Smoothing level) {
      final st = InkStabilizer()..reset(Offset.zero, level);
      return st.add(const Offset(4, 0))!;
    }

    expect(step(Smoothing.off).dx, 4);
    expect(step(Smoothing.max).dx, lessThan(step(Smoothing.medium).dx));
  });
}
