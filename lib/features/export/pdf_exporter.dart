import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/imaging/paper_size.dart';

enum PdfPageSize {
  /// Si la imagen tiene proporción de Carta, Oficio o A4, ese papel a página
  /// completa; si no, A4 con la imagen centrada. Vertical u horizontal según
  /// la imagen.
  a4,

  /// Cada página mide lo mismo que su imagen.
  fitImage,
}

class PdfPageInput {
  const PdfPageInput(this.imagePath, this.width, this.height);
  final String imagePath;
  final int width;
  final int height;
}

/// Une las páginas procesadas en un PDF dentro de un isolate. Los JPEG se
/// incrustan tal cual, sin recomprimir.
class PdfExporter {
  const PdfExporter();

  Future<String> export({
    required String title,
    required List<PdfPageInput> pages,
    required Directory outDir,
    PdfPageSize pageSize = PdfPageSize.a4,
  }) async {
    await outDir.create(recursive: true);
    final outPath = p.join(outDir.path, '${safeFileName(title)}.pdf');
    await Isolate.run(() => buildPdf(title: title, pages: pages, outPath: outPath, pageSize: pageSize));
    return outPath;
  }
}

Future<void> buildPdf({
  required String title,
  required List<PdfPageInput> pages,
  required String outPath,
  required PdfPageSize pageSize,
}) async {
  final doc = pw.Document(title: title, creator: 'Nuvora');
  for (final page in pages) {
    final image = pw.MemoryImage(File(page.imagePath).readAsBytesSync());
    final landscape = page.width > page.height;
    final paper = paperForImage(page.width, page.height);
    final base = paper == null
        ? PdfPageFormat.a4
        : PdfPageFormat(paper.shortMm! * PdfPageFormat.mm, paper.longMm! * PdfPageFormat.mm);
    final format = switch (pageSize) {
      PdfPageSize.a4 => landscape ? base.landscape : base,
      // 72 puntos por pulgada; se asume 200 dpi para que el tamaño físico sea razonable.
      PdfPageSize.fitImage => PdfPageFormat(page.width * 72 / 200, page.height * 72 / 200),
    };
    doc.addPage(
      pw.Page(
        pageFormat: format,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
      ),
    );
  }
  await File(outPath).writeAsBytes(await doc.save());
}

/// Nombre de archivo seguro a partir del título del documento.
String safeFileName(String title) {
  final cleaned = title.trim().replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_');
  return cleaned.isEmpty ? 'documento' : cleaned;
}
