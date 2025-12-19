import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Pages are laid out in "page units": a new page is [pageWidth] units wide
/// (extending a side makes it wider/taller). Stroke points are stored in these
/// units so annotations stay aligned when the on-screen size changes
/// (rotation, split view) and when exporting to PDF.
const double pageWidth = 1000;

/// Height / width of a blank page (A4 portrait).
const double a4Aspect = 297 / 210;

enum StrokeTool { pen, highlighter }

class Stroke {
  Stroke({
    required this.tool,
    required this.color,
    required this.width,
    List<Offset>? points,
  }) : points = points ?? [];
}
