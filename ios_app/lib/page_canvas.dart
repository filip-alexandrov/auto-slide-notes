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
}
