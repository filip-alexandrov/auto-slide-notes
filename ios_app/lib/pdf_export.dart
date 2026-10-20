import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'document_store.dart';
import 'ink.dart';
import 'models.dart';
import 'page_canvas.dart' show highlighterOpacity;

/// Width of every exported PDF page in points (A4 width).
const double _pdfPageWidth = 595.28;

/// Renders the notebook to a PDF: slide images as-is, ink as vector paths.
Future<File> exportPdf(NoteDocument doc, DocumentStore store) async {
  final pdf = pw.Document(title: doc.title, creator: 'AutoSlide Notes');

  for (final page in doc.pages) {
    final height = _pdfPageWidth * page.aspect;
    final pageUnits = page.width;
    final pdfScale = _pdfPageWidth / pageUnits;
    final imageRect = page.imageRect;
    pw.MemoryImage? image;
    if (page.imageFile != null) {
      final file = store.imageFile(page.imageFile!);
      if (await file.exists()) image = pw.MemoryImage(await file.readAsBytes());
    }
    // Snapshot strokes so later edits don't affect the export.
    final strokes = List<Stroke>.of(page.strokes);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(_pdfPageWidth, height),
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Stack(
          fit: pw.StackFit.expand,
          children: [
            if (image != null && imageRect != null)
              pw.Positioned(
                left: imageRect.left * pdfScale,
                top: imageRect.top * pdfScale,
                child: pw.SizedBox(
                  width: imageRect.width * pdfScale,
                  height: imageRect.height * pdfScale,
                  child: pw.Image(image, fit: pw.BoxFit.fill),
                ),
              ),
            pw.CustomPaint(
              size: PdfPoint(_pdfPageWidth, height),
              painter: (canvas, size) =>
                  _paintStrokes(canvas, size, strokes, pageUnits),
            ),
          ],
        ),
      ),
    );
  }

  final dir = await getTemporaryDirectory();
  final stamp = DateTime.now().toIso8601String().replaceAll(
    RegExp(r'[:.]'),
    '-',
  );
  final file = File('${dir.path}/Notes_$stamp.pdf');
  await file.writeAsBytes(await pdf.save(), flush: true);
  return file;
}

void _paintStrokes(
  PdfGraphics canvas,
  PdfPoint size,
  List<Stroke> strokes,
  double width,
) {
  final scale = size.x / width;
  // PDF origin is bottom-left; page coordinates are top-left.
  double x(double v) => v * scale;
  double y(double v) => size.y - v * scale;

  final ordered = [
    ...strokes.where((s) => s.tool == StrokeTool.highlighter),
    ...strokes.where((s) => s.tool == StrokeTool.pen),
  ];

  for (final s in ordered) {
    if (s.points.isEmpty) continue;
    canvas.saveContext();
    final color = PdfColor.fromInt(s.color);
    if (s.tool == StrokeTool.highlighter) {
      canvas.setGraphicState(PdfGraphicState(opacity: highlighterOpacity));
    }
    if (s.points.length == 1) {
      final p = s.points.first;
      final r = s.width * scale / 2;
      canvas
        ..setFillColor(color)
        ..drawEllipse(x(p.dx), y(p.dy), r, r)
        ..fillPath();
    } else {
      canvas
        ..setStrokeColor(color)
        ..setLineWidth(s.width * scale)
        ..setLineCap(PdfLineCap.round)
        ..setLineJoin(PdfLineJoin.round);
      traceSmooth(
        s.points,
        moveTo: (p) => canvas.moveTo(x(p.dx), y(p.dy)),
        cubicTo: (c1, c2, p) => canvas.curveTo(
          x(c1.dx),
          y(c1.dy),
          x(c2.dx),
          y(c2.dy),
          x(p.dx),
          y(p.dy),
        ),
      );
      canvas.strokePath();
    }
    canvas.restoreContext();
  }
}
