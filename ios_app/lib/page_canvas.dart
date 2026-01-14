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
