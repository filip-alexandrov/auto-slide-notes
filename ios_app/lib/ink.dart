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

/// How strongly Pencil input is smoothed; selectable in the toolbar.
enum Smoothing {
  off('Off', 1.0, 1.0, 0),
  low('Low', 0.5, 0.9, 0),
  medium('Medium', 0.35, 0.8, 0),
  high('High', 0.25, 0.65, 1),
  max('Max', 0.15, 0.5, 2);

  const Smoothing(
    this.label,
    this.slowAlpha,
    this.fastAlpha,
    this.finishPasses,
  );

  final String label;

  /// Share of each new sample that is kept, for slow and fast pen movement
  /// (1 = raw input, lower = smoother but the ink trails the tip more).
  final double slowAlpha;
  final double fastAlpha;

  /// Extra smoothing passes applied once the Pencil is lifted.
  final int finishPasses;
}
