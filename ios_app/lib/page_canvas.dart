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
}
