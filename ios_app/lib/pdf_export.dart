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
  final pdf = pw.Document(title: doc.title, creator: 'Slide Notes');

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
