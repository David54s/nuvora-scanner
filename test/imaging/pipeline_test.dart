import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:nuvora_scanner/core/imaging/edge_detector.dart';
import 'package:nuvora_scanner/core/imaging/filters.dart';
import 'package:nuvora_scanner/core/imaging/image_pipeline.dart';
import 'package:nuvora_scanner/core/imaging/live_edge_worker.dart';
import 'package:nuvora_scanner/core/imaging/page_filter.dart';
import 'package:nuvora_scanner/core/imaging/paper_size.dart';
import 'package:nuvora_scanner/core/imaging/perspective.dart';
import 'package:nuvora_scanner/core/imaging/quad.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opencv_dart/opencv.dart' as cv;

/// Foto sintética: fondo oscuro con algo de textura y una hoja blanca con
/// "renglones" de texto en las esquinas [corners] (en píxeles).
cv.Mat syntheticPhoto(List<(int, int)> corners, {int w = 1200, int h = 900, int background = 60}) {
  final img = cv.Mat.fromScalar(h, w, cv.MatType.CV_8UC3, cv.Scalar.all(background.toDouble()));
  final rnd = math.Random(42);
  for (var i = 0; i < 40; i++) {
    cv.line(
      img,
      cv.Point(rnd.nextInt(w), rnd.nextInt(h)),
      cv.Point(rnd.nextInt(w), rnd.nextInt(h)),
      cv.Scalar.all((background - 20 + rnd.nextInt(40)).toDouble()),
      thickness: 2,
    );
  }
  final poly = cv.VecVecPoint.fromList([
    [for (final (x, y) in corners) cv.Point(x, y)],
  ]);
  cv.fillPoly(img, poly, cv.Scalar(235, 240, 240));
  poly.dispose();
  // Renglones de "texto" dentro de la hoja (interpolando entre los lados).
  final (x0, y0) = corners[0];
  final (x1, y1) = corners[1];
  final (x3, y3) = corners[3];
  for (var r = 1; r < 12; r++) {
    final t = r / 13;
    final ax = x0 + (x3 - x0) * t, ay = y0 + (y3 - y0) * t;
    cv.line(
      img,
      cv.Point((ax + (x1 - x0) * 0.1).round(), (ay + (y1 - y0) * 0.1).round()),
      cv.Point((ax + (x1 - x0) * 0.85).round(), (ay + (y1 - y0) * 0.85).round()),
      cv.Scalar.all(30),
      thickness: 3,
    );
  }
  return img;
}

void expectCornersClose(Quad q, List<(int, int)> expected, int w, int h, {double tol = 0.02}) {
  for (var i = 0; i < 4; i++) {
    final (ex, ey) = expected[i];
    final p = q.points[i];
    expect((p.x - ex / w).abs(), lessThan(tol), reason: 'esquina $i x: $p vs $expected');
    expect((p.y - ey / h).abs(), lessThan(tol), reason: 'esquina $i y: $p vs $expected');
  }
}

void main() {
  group('Quad', () {
    test('ordena esquinas desordenadas como TL, TR, BR, BL', () {
      const tl = Pt(0.1, 0.1), tr = Pt(0.9, 0.15), br = Pt(0.85, 0.9), bl = Pt(0.15, 0.95);
      final q = Quad.fromUnordered([br, tl, bl, tr]);
      expect(q, const Quad(tl, tr, br, bl));
    });

    test('ordena un quad girado 45°', () {
      const top = Pt(0.5, 0.05), right = Pt(0.95, 0.5), bottom = Pt(0.5, 0.95), left = Pt(0.05, 0.5);
      final q = Quad.fromUnordered([bottom, right, top, left]);
      expect(q.points.toSet(), {top, right, bottom, left});
      expect(q.isConvex, isTrue);
    });

    test('JSON de ida y vuelta', () {
      const q = Quad(Pt(0.1, 0.2), Pt(0.8, 0.1), Pt(0.9, 0.9), Pt(0.05, 0.85));
      expect(Quad.fromJson(q.toJson()), q);
    });

    test('detecta quads cóncavos', () {
      expect(Quad.full.isConvex, isTrue);
      final concave = Quad.full.copyWithPoint(0, const Pt(0.8, 0.8));
      expect(concave.isConvex, isFalse);
    });
  });

  group('detectQuad', () {
    test('encuentra una hoja en perspectiva', () {
      const corners = [(250, 120), (950, 160), (1010, 800), (180, 760)];
      final img = syntheticPhoto(corners);
      addTearDown(img.dispose);
      final det = detectQuad(img);
      expect(det.found, isTrue);
      expectCornersClose(det.quad, corners, img.cols, img.rows);
    });

    test('hoja blanca sobre fondo claro', () {
      const corners = [(250, 120), (950, 160), (1010, 800), (180, 760)];
      final img = syntheticPhoto(corners, background: 175);
      addTearDown(img.dispose);
      final det = detectQuad(img);
      expect(det.found, isTrue);
      expectCornersClose(det.quad, corners, img.cols, img.rows, tol: 0.03);
    });

    test('hoja que se sale del cuadro por los lados', () {
      // Los lados izquierdo y derecho quedan fuera: las esquinas van sobre el borde.
      final img = syntheticPhoto([(-60, 150), (1260, 130), (1260, 800), (-60, 820)]);
      addTearDown(img.dispose);
      final det = detectQuad(img);
      expect(det.found, isTrue);
      expectCornersClose(det.quad, [(0, 149), (1199, 131), (1199, 801), (0, 819)], img.cols, img.rows, tol: 0.03);
    });

    test('esquina tapada por un dedo', () {
      const corners = [(250, 120), (950, 160), (1010, 800), (180, 760)];
      final img = syntheticPhoto(corners);
      addTearDown(img.dispose);
      cv.circle(img, cv.Point(1010, 800), 70, cv.Scalar(90, 120, 170), thickness: -1);
      final det = detectQuad(img);
      expect(det.found, isTrue);
      expectCornersClose(det.quad, corners, img.cols, img.rows, tol: 0.03);
    });

    test('sin documento devuelve la imagen completa con confianza 0', () {
      final img = cv.Mat.fromScalar(600, 800, cv.MatType.CV_8UC3, cv.Scalar.all(90));
      addTearDown(img.dispose);
      final det = detectQuad(img);
      expect(det.confidence, 0);
      expect(det.quad, Quad.full);
    });
  });

  group('warpQuad', () {
    test('respeta la proporción de la hoja', () {
      const corners = [(100, 100), (900, 100), (900, 500), (100, 500)];
      final img = syntheticPhoto(corners);
      addTearDown(img.dispose);
      final q = Quad.fromUnordered([for (final (x, y) in corners) Pt(x / img.cols, y / img.rows)]);
      final out = warpQuad(img, q);
      addTearDown(out.dispose);
      expect(out.cols / out.rows, closeTo(2.0, 0.04));
    });

    test('limita el lado largo', () {
      final img = cv.Mat.zeros(400, 800, cv.MatType.CV_8UC3);
      addTearDown(img.dispose);
      final out = warpQuad(img, Quad.full, maxSide: 200);
      addTearDown(out.dispose);
      expect(math.max(out.cols, out.rows), 200);
    });
  });

  group('applyFilter', () {
    late cv.Mat page;
    setUp(() {
      // Hoja con sombra en degradado y texto oscuro.
      page = cv.Mat.zeros(400, 300, cv.MatType.CV_8UC3);
      for (var x = 0; x < 300; x++) {
        final v = 240 - (x * 0.4).round();
        cv.line(page, cv.Point(x, 0), cv.Point(x, 399), cv.Scalar.all(v.toDouble()));
      }
      for (var y = 40; y < 380; y += 30) {
        cv.line(page, cv.Point(20, y), cv.Point(280, y), cv.Scalar.all(20), thickness: 2);
      }
    });
    tearDown(() => page.dispose());

    test('B/N solo contiene 0 y 255', () {
      final bw = applyFilter(page, PageFilter.bw);
      addTearDown(bw.dispose);
      expect(bw.channels, 1);
      expect(bw.data.toSet().difference({0, 255}), isEmpty);
    });

    test('grises tiene un canal', () {
      final g = applyFilter(page, PageFilter.grayscale);
      addTearDown(g.dispose);
      expect(g.channels, 1);
      expect((g.cols, g.rows), (300, 400));
    });

    test('mejorado deja el papel blanco puro y los renglones oscuros', () {
      final enh = applyFilter(page, PageFilter.enhanced);
      addTearDown(enh.dispose);
      final gray = cv.cvtColor(enh, cv.COLOR_BGR2GRAY);
      addTearDown(gray.dispose);
      // Franja sin texto (filas 0..30), a pesar de la sombra en degradado.
      var white = 0;
      for (var y = 0; y < 30; y++) {
        for (var x = 0; x < 300; x++) {
          if (gray.at<int>(y, x) >= 245) white++;
        }
      }
      expect(white / (30 * 300), greaterThan(0.95));
      // Renglón en y = 40, lejos de los bordes.
      var sum = 0;
      for (var x = 40; x < 260; x++) {
        sum += gray.at<int>(40, x);
      }
      expect(sum / 220, lessThanOrEqualTo(80));
    });

    test('mejorado reduce la sombra del fondo', () {
      final enh = applyFilter(page, PageFilter.enhanced);
      addTearDown(enh.dispose);
      expect(enh.channels, 3);
      // Franja de fondo sin texto (filas 0..30) en ambas imágenes.
      final roi = cv.Rect(0, 0, 300, 30);
      final before = page.region(roi);
      final after = enh.region(roi);
      final (_, sdBefore) = cv.meanStdDev(before);
      final (_, sdAfter) = cv.meanStdDev(after);
      expect(sdAfter.val1, lessThan(sdBefore.val1 / 2));
    });
  });

  group('pipeline de archivos', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('pipeline_test'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('ingest → detect → render produce página y miniatura', () {
      const corners = [(250, 120), (950, 160), (1010, 800), (180, 760)];
      final img = syntheticPhoto(corners);
      final src = '${tmp.path}/src.png';
      cv.imwrite(src, img);
      img.dispose();

      final orig = '${tmp.path}/original.jpg';
      final size = ingestSync(src, orig);
      expect(size, (width: 1200, height: 900));

      final det = detectSync(orig);
      expect(det.found, isTrue);

      final out = renderSync(
        RenderRequest(
          originalPath: orig,
          quad: det.quad,
          filter: PageFilter.enhanced,
          rotation: 90,
          processedPath: '${tmp.path}/processed.jpg',
          thumbPath: '${tmp.path}/thumb.jpg',
        ),
      );
      // La hoja es más ancha que alta; rotada 90° queda vertical.
      expect(out.height, greaterThan(out.width));
      final thumb = cv.imread('${tmp.path}/thumb.jpg');
      addTearDown(thumb.dispose);
      expect(math.max(thumb.cols, thumb.rows), thumbnailSide);
    });

    test('preview devuelve un JPEG del recorte, reducido', () async {
      final img = cv.Mat.fromScalar(1600, 1200, cv.MatType.CV_8UC3, cv.Scalar.all(200));
      final src = '${tmp.path}/big.jpg';
      cv.imwrite(src, img);
      img.dispose();
      final bytes = previewSync(
        src,
        const Quad(Pt(0.1, 0.1), Pt(0.9, 0.1), Pt(0.9, 0.9), Pt(0.1, 0.9)),
        PageFilter.grayscale,
        90,
        (width: 1200, height: 1600),
        400,
      );
      expect(bytes.take(2), [0xFF, 0xD8]);
      final decoded = cv.imdecode(bytes, cv.IMREAD_COLOR);
      addTearDown(decoded.dispose);
      // Rotada 90°: más ancha que alta; lado largo limitado a 400.
      expect(decoded.cols, 400);
      expect(decoded.rows, closeTo(300, 2));
    });

    test('render ajusta la página a carta', () {
      // Hoja con proporción distorsionada por la foto (700 × 640 medidos).
      const corners = [(250, 120), (950, 160), (1010, 800), (180, 760)];
      final img = syntheticPhoto(corners);
      final src = '${tmp.path}/src.jpg';
      cv.imwrite(src, img);
      img.dispose();
      final q = Quad.fromUnordered([for (final (x, y) in corners) Pt(x / 1200, y / 900)]);
      final out = renderSync(
        RenderRequest(
          originalPath: src,
          quad: q,
          filter: PageFilter.original,
          rotation: 0,
          paper: PaperSize.letter,
          processedPath: '${tmp.path}/p.jpg',
          thumbPath: '${tmp.path}/t.jpg',
        ),
      );
      final ratio = math.max(out.width, out.height) / math.min(out.width, out.height);
      expect(ratio, closeTo(PaperSize.letter.ratio!, 0.005));
      expect(paperForImage(out.width, out.height), PaperSize.letter);
    });

    test('ruta inexistente lanza ImageReadException', () {
      expect(() => detectSync('${tmp.path}/nope.jpg'), throwsA(isA<ImageReadException>()));
    });
  });

  group('contorno en vivo', () {
    test('GrayFrame quita el relleno de fila y reduce', () {
      // 8×4 con stride 10: cada fila vale su número.
      final y = Uint8List(10 * 4);
      for (var r = 0; r < 4; r++) {
        y.fillRange(r * 10, r * 10 + 8, r);
      }
      final f = GrayFrame.fromYPlane(y, 8, 4, 10, targetSide: 4);
      expect((f.width, f.height), (4, 2));
      expect(f.bytes, [0, 0, 0, 0, 2, 2, 2, 2]);
    });

    test('LiveEdgeWorker detecta la hoja en un isolate', () async {
      const corners = [(250, 120), (950, 160), (1010, 800), (180, 760)];
      final img = syntheticPhoto(corners);
      final gray = cv.cvtColor(img, cv.COLOR_BGR2GRAY);
      img.dispose();
      final frame = GrayFrame.fromYPlane(Uint8List.fromList(gray.data), gray.cols, gray.rows, gray.cols);
      gray.dispose();

      final worker = await LiveEdgeWorker.spawn();
      addTearDown(worker.dispose);
      final det = await worker.detect(frame);
      expect(det, isNotNull);
      expectCornersClose(det!.quad, corners, 1200, 900, tol: 0.03);
      // Un segundo cuadro reutiliza el mismo isolate.
      expect(await worker.detect(frame), isNotNull);
    });
  });
}
