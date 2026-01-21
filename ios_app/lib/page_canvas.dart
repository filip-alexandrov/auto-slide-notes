import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'ink.dart';
import 'models.dart';

enum DrawTool { pen, highlighter, eraser }

const double highlighterOpacity = 0.35;

class ToolSettings {
  const ToolSettings({
    this.tool = DrawTool.pen,
    this.penColor = 0xFF1A1A1A,
    this.highlighterColor = 0xFFFFD600,
    this.penWidth = 3,
    this.highlighterWidth = 18,
    this.fingerDraws = false,
    this.smoothing = Smoothing.medium,
  });

  final DrawTool tool;

  /// Pen and highlighter keep their own color and width, so switching tools
  /// doesn't lose either choice.
  final int penColor;
  final int highlighterColor;

  /// Widths in units of a [pageWidth]-wide page; scaled up on pages that
  /// were extended so ink looks the same size on screen.
  final double penWidth;
  final double highlighterWidth;

  bool get isHighlighter => tool == DrawTool.highlighter;
  int get color => isHighlighter ? highlighterColor : penColor;
  double get strokeWidth => isHighlighter ? highlighterWidth : penWidth;

  /// Eraser reach around the Pencil tip, in page units (a stroke is hit
  /// when it passes within this distance plus half its own width).
  double get eraserRadius => 4;

  bool canDraw(PointerDeviceKind kind) =>
      kind == PointerDeviceKind.stylus ||
      kind == PointerDeviceKind.invertedStylus ||
      (fingerDraws && kind == PointerDeviceKind.touch) ||
      kind == PointerDeviceKind.mouse; // Simulator / Mac debugging.

  ToolSettings copyWith({
    DrawTool? tool,
    int? penColor,
    int? highlighterColor,
    double? penWidth,
    double? highlighterWidth,
    bool? fingerDraws,
    Smoothing? smoothing,
  }) => ToolSettings(
    tool: tool ?? this.tool,
    penColor: penColor ?? this.penColor,
    highlighterColor: highlighterColor ?? this.highlighterColor,
    penWidth: penWidth ?? this.penWidth,
    highlighterWidth: highlighterWidth ?? this.highlighterWidth,
    fingerDraws: fingerDraws ?? this.fingerDraws,
    smoothing: smoothing ?? this.smoothing,
  );
}

/// Renders one page (background image + ink) and turns stylus input into
/// strokes. Fingers are left to the enclosing scroll view.
class PageCanvas extends StatefulWidget {
  const PageCanvas({
    super.key,
    required this.page,
    required this.imageFile,
    required this.settings,
    required this.onStrokeAdded,
    required this.onStrokesErased,
  });

  final NotePage page;
  final File? imageFile;
  final ToolSettings settings;
  final void Function(NotePage page, Stroke stroke) onStrokeAdded;
  final void Function(NotePage page, List<Stroke> strokes) onStrokesErased;

  @override
  State<PageCanvas> createState() => _PageCanvasState();
}

class _PageCanvasState extends State<PageCanvas> {
  final _active = _ActiveStroke();
  int? _pointer;
  PointerDeviceKind? _pointerKind;
  bool _erasing = false;
  final List<Stroke> _erased = [];
  double _scale = 1;

  @override
  void dispose() {
    _active.dispose();
    super.dispose();
  }

  Offset _toPage(Offset local) => local / _scale;

  static int _bucket(double px) => ((px / 512).ceil() * 512).clamp(512, 8192);

  /// How much larger this page is than a fresh one (1 unless extended).
  double get _unitScale => widget.page.width / pageWidth;

  void _onDown(PointerDownEvent e) {
    // A second finger while drawing with a finger means a pinch, not ink.
    if (_pointer != null &&
        _pointerKind == PointerDeviceKind.touch &&
        e.kind == PointerDeviceKind.touch) {
      _finish(commit: false);
      return;
    }
    if (_pointer != null || !widget.settings.canDraw(e.kind)) return;
    _pointer = e.pointer;
    _pointerKind = e.kind;
    final p = _toPage(e.localPosition);
    // The back end of the Apple Pencil (where supported) always erases.
    _erasing =
        widget.settings.tool == DrawTool.eraser ||
        e.kind == PointerDeviceKind.invertedStylus;
    if (_erasing) {
      _eraseAt(p);
    } else {
      final s = widget.settings;
      _active.start(
        Stroke(
          tool: s.tool == DrawTool.highlighter
              ? StrokeTool.highlighter
              : StrokeTool.pen,
          color: s.color,
          width: s.strokeWidth * _unitScale,
          points: [p],
        ),
        s.smoothing,
      );
    }
  }

  void _onMove(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    final p = _toPage(e.localPosition);
    if (_erasing) {
      _eraseAt(p);
    } else {
      _active.add(p);
    }
  }

  void _onUp(PointerUpEvent e) {
    if (e.pointer != _pointer) return;
    // End exactly where the pen lifted, not at the lagging smoothed point.
    if (!_erasing) _active.end(_toPage(e.localPosition));
    _finish(commit: true);
  }

  void _onCancel(PointerCancelEvent e) {
    if (e.pointer != _pointer) return;
    _finish(commit: false);
  }

  void _finish({required bool commit}) {
    _pointer = null;
    if (_erasing) {
      if (_erased.isNotEmpty) {
        widget.onStrokesErased(widget.page, List.of(_erased));
        _erased.clear();
      }
      _erasing = false;
      return;
    }
    final stroke = _active.take();
    if (commit && stroke != null) {
      widget.page.addStroke(stroke);
      widget.onStrokeAdded(widget.page, stroke);
    }
  }
}

class _StrokesPainter extends CustomPainter {
  _StrokesPainter(this.page, this.scale) : super(repaint: page);

  final NotePage page;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(scale);
    // Highlighter first so pen ink stays crisp on top of it.
    for (final s in page.strokes) {
      if (s.tool == StrokeTool.highlighter) paintStroke(canvas, s);
    }
    for (final s in page.strokes) {
      if (s.tool == StrokeTool.pen) paintStroke(canvas, s);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StrokesPainter old) =>
      old.page != page || old.scale != scale;
}

void paintStroke(Canvas canvas, Stroke s) {
  final color = Color(s.color);
  final paint = Paint()
    ..color = s.tool == StrokeTool.highlighter
        ? color.withValues(alpha: highlighterOpacity)
        : color
    ..strokeWidth = s.width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke
    ..isAntiAlias = true;

  final pts = s.points;
  if (pts.isEmpty) return;
  if (pts.length == 1) {
    canvas.drawCircle(
      pts.first,
      s.width / 2,
      paint..style = PaintingStyle.fill,
    );
    return;
  }
  final path = Path();
  traceSmooth(
    pts,
    moveTo: (p) => path.moveTo(p.dx, p.dy),
    cubicTo: (c1, c2, p) =>
        path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p.dx, p.dy),
  );
  canvas.drawPath(path, paint);
}
