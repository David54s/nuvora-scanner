import 'package:flutter_test/flutter_test.dart';
import 'package:nuvora_scanner/core/imaging/id_composer.dart';
import 'package:nuvora_scanner/core/imaging/id_layout.dart';
import 'package:nuvora_scanner/core/imaging/paper_size.dart';
import 'package:nuvora_scanner/core/imaging/quad.dart';
import 'package:opencv_dart/opencv.dart' as cv;

/// Foto 1200×900 con una "tarjeta" de un color en perspectiva.
(cv.Mat, Quad) cardPhoto(cv.Scalar color, List<(int, int)> corners) {
  const w = 1200, h = 900;
  final img = cv.Mat.fromScalar(h, w, cv.MatType.CV_8UC3, cv.Scalar.all(70));
  final poly = cv.VecVecPoint.fromList([
    [for (final (x, y) in corners) cv.Point(x, y)],
  ]);
  cv.fillPoly(img, poly, color);
  poly.dispose();
  final q = Quad(
    Pt(corners[0].$1 / w, corners[0].$2 / h),
    Pt(corners[1].$1 / w, corners[1].$2 / h),
    Pt(corners[2].$1 / w, corners[2].$2 / h),
    Pt(corners[3].$1 / w, corners[3].$2 / h),
  );
  return (img, q);
}

void main() {
  final blue = cv.Scalar(200, 40, 20);
  final red = cv.Scalar(30, 30, 210);

  int px(double mm) => (mm * idSheetDpi / 25.4).round();

  void expectColor(cv.Mat m, int row, int col, cv.Scalar c, {String? reason}) {
    final v = m.at<cv.Vec3b>(row, col);
    expect((v.val1 - c.val1).abs(), lessThan(12), reason: reason);
    expect((v.val2 - c.val2).abs(), lessThan(12), reason: reason);
    expect((v.val3 - c.val3).abs(), lessThan(12), reason: reason);
  }

  test('compone frente y reverso a tamaño real sobre Carta a 300 dpi', () {
    final (front, fq) = cardPhoto(blue, [(300, 220), (930, 260), (900, 640), (270, 600)]);
    final (back, bq) = cardPhoto(red, [(250, 250), (950, 230), (960, 690), (240, 700)]);
    const layout = IdLayout(template: IdTemplate.ine);
    final sheet = composeIdSheet([(image: front, quad: fq, rotation: 0), (image: back, quad: bq, rotation: 0)], layout);
    addTearDown(() {
      front.dispose();
      back.dispose();
      sheet.dispose();
    });

    expect((sheet.cols, sheet.rows), (2550, 3300));
    final r = layout.placeCards(2);
    for (final (i, color) in [blue, red].indexed) {
      final x = px(r[i].x), y = px(r[i].y), w = px(r[i].w), h = px(r[i].h);
      expectColor(sheet, y + h ~/ 2, x + w ~/ 2, color, reason: 'centro del lado $i');
      // Cerca de las esquinas sigue siendo tarjeta (sin fondo de la foto).
      expectColor(sheet, y + 8, x + 8, color, reason: 'esquina del lado $i');
      expectColor(sheet, y + h - 9, x + w - 9, color, reason: 'esquina opuesta del lado $i');
      // Justo fuera, papel blanco.
      expectColor(sheet, y + h ~/ 2, x - 6, cv.Scalar.all(255), reason: 'izquierda del lado $i');
    }
    expectColor(sheet, 3200, 1275, cv.Scalar.all(255), reason: 'parte de abajo en blanco');
    expectColor(sheet, 20, 20, cv.Scalar.all(255), reason: 'margen superior');
  });

  test('un lado fotografiado en vertical y girado 90° queda horizontal y sin deformar', () {
    // Tarjeta en vertical en la foto: proporción 54:85.6.
    final (side, q) = cardPhoto(blue, [(500, 150), (770, 150), (770, 578), (500, 578)]);
    final layout = const IdLayout(template: IdTemplate.card).copyWith(paper: PaperSize.a4);
    final sheet = composeIdSheet([(image: side, quad: q, rotation: 90)], layout);
    addTearDown(() {
      side.dispose();
      sheet.dispose();
    });
    expect((sheet.cols, sheet.rows), (px(210), px(297)));
    final r = layout.placeCards(1).single;
    expect(r.w > r.h, isTrue);
    expectColor(sheet, px(r.y) + 8, px(r.x) + 8, blue);
    expectColor(sheet, px(r.y + r.h) - 9, px(r.x + r.w) - 9, blue);
  });
}
