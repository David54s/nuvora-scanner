import 'dart:io';

import 'package:nuvora_scanner/features/export/pdf_exporter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opencv_dart/opencv.dart' as cv;

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('pdf_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  String jpeg(String name, int w, int h) {
    final path = '${tmp.path}/$name.jpg';
    final m = cv.Mat.fromScalar(h, w, cv.MatType.CV_8UC3, cv.Scalar.all(200));
    cv.imwrite(path, m);
    m.dispose();
    return path;
  }

  test('genera un PDF con una página por imagen', () async {
    final pages = [
      PdfPageInput(jpeg('a', 300, 400), 300, 400),
      PdfPageInput(jpeg('b', 400, 300), 400, 300),
      PdfPageInput(jpeg('c', 300, 400), 300, 400),
    ];
    final path = await const PdfExporter().export(
      title: 'Factura: marzo/2026',
      pages: pages,
      outDir: Directory('${tmp.path}/out'),
    );
    expect(path, endsWith('Factura_ marzo_2026.pdf'));
    final bytes = File(path).readAsBytesSync();
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    final text = String.fromCharCodes(bytes);
    expect(RegExp(r'/Type\s*/Page[^s]').allMatches(text).length, 3);
  });

  test('una página con proporción carta sale en papel carta', () async {
    final path = await const PdfExporter().export(
      title: 'carta',
      pages: [PdfPageInput(jpeg('carta', 255, 330), 255, 330)],
      outDir: Directory('${tmp.path}/out'),
    );
    final text = String.fromCharCodes(File(path).readAsBytesSync());
    // Carta = 612 × 792 puntos.
    expect(RegExp(r'/MediaBox\s*\[\s*0\s+0\s+612(\.0+)?\s+792').hasMatch(text), isTrue);
  });

  test('safeFileName', () {
    expect(safeFileName('  '), 'documento');
    expect(safeFileName('a/b\\c?'), 'a_b_c_');
  });
}
