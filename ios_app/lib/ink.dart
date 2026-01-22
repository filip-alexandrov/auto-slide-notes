import 'dart:ui';

/// Emits a smooth curve through [pts] as cubic Bézier segments
/// (uniform Catmull-Rom spline). Used for both screen and PDF rendering so
/// exported ink looks the same as on screen.
void traceSmooth(
  List<Offset> pts, {
  required void Function(Offset p) moveTo,
  required void Function(Offset c1, Offset c2, Offset p) cubicTo,
}) {
  if (pts.isEmpty) return;
  moveTo(pts.first);
  if (pts.length == 1) return;
  for (var i = 0; i < pts.length - 1; i++) {
    final p0 = pts[i == 0 ? 0 : i - 1];
    final p1 = pts[i];
    final p2 = pts[i + 1];
    final p3 = pts[i + 2 < pts.length ? i + 2 : pts.length - 1];
    cubicTo(p1 + (p2 - p0) / 6, p2 - (p3 - p1) / 6, p2);
  }
}
