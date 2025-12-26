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

  final StrokeTool tool;
  final int color;
  final double width;
  final List<Offset> points;

  Rect get bounds {
    if (points.isEmpty) return Rect.zero;
    var minX = points.first.dx, maxX = minX;
    var minY = points.first.dy, maxY = minY;
    for (final p in points) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY).inflate(width / 2);
  }

  Map<String, dynamic> toJson() => {
    'tool': tool.name,
    'color': color,
    'width': width,
    // Flattened [x0, y0, x1, y1, ...] rounded to 0.1 units to keep files small.
    'points': [
      for (final p in points) ...[
        (p.dx * 10).round() / 10,
        (p.dy * 10).round() / 10,
      ],
    ],
  };

  factory Stroke.fromJson(Map<String, dynamic> json) {
    final flat = (json['points'] as List).cast<num>();
    return Stroke(
      tool: StrokeTool.values.byName(json['tool'] as String),
      color: json['color'] as int,
      width: (json['width'] as num).toDouble(),
      points: [
        for (var i = 0; i + 1 < flat.length; i += 2)
          Offset(flat[i].toDouble(), flat[i + 1].toDouble()),
      ],
    );
  }
}

enum PageSide { left, top, right, bottom }

/// A single page of the notebook: either blank or backed by a slide image.
///
/// A page starts [pageWidth] units wide with the slide image filling it.
/// [extend] adds white space on one side; strokes and the image keep their
/// position relative to each other.
class NotePage extends ChangeNotifier {
  NotePage({
    required this.id,
    required double aspect,
    this.imageFile,
    this.slideId,
    List<Stroke>? strokes,
  }) : width = pageWidth,
       height = pageWidth * aspect,
       imageRect = imageFile == null
           ? null
           : Rect.fromLTWH(0, 0, pageWidth, pageWidth * aspect),
       strokes = strokes ?? [];

  NotePage._({
    required this.id,
    required this.width,
    required this.height,
    required this.imageRect,
    required this.imageFile,
    required this.slideId,
    required this.strokes,
  });

  final String id;

  /// Page size in page units.
  double width;
  double height;

  /// Where the slide image sits on the page, in page units.
  Rect? imageRect;

  /// File name (relative to the notebook's image directory) of the slide image.
  final String? imageFile;

  /// Server-side slide id, if this page came from the Mac.
  final int? slideId;

  final List<Stroke> strokes;

  /// height / width
  double get aspect => height / width;

  void addStroke(Stroke s) {
    strokes.add(s);
    notifyListeners();
  }

  void removeStrokes(Iterable<Stroke> toRemove) {
    final set = toRemove.toSet();
    strokes.removeWhere(set.contains);
    notifyListeners();
  }

  void insertStrokes(Iterable<Stroke> toAdd) {
    strokes.addAll(toAdd);
    notifyListeners();
  }
}
