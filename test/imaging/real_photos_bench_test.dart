import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:nuvora_scanner/core/imaging/edge_detector.dart';
import 'package:nuvora_scanner/core/imaging/quad.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opencv_dart/opencv.dart' as cv;
import 'package:path/path.dart' as p;

/// Banco de calibración del detector con fotos reales.
///
/// Las fotos viven en `test/fixtures/real/` (fuera de git: tienen datos
/// personales) junto con `ground_truth.json`. Si no existen, se salta.
/// Dibuja la verdad (verde) y la detección (rojo) en `build/detector_bench/`.
const _dir = 'test/fixtures/real';
const _outDir = 'build/detector_bench';
const _minIou = 0.9;

void main() {
  final gtFile = File(p.join(_dir, 'ground_truth.json'));
  final skip = gtFile.existsSync() ? false : 'Sin fotos reales en $_dir';

  test('detector con fotos reales', skip: skip, () {
    final gt = (jsonDecode(gtFile.readAsStringSync()) as Map<String, dynamic>)..remove('_comment');
    Directory(_outDir).createSync(recursive: true);
    final rows = <String>[];
    var passed = 0;

    for (final MapEntry(key: name, value: corners) in gt.entries) {
      final img = cv.imread(p.join(_dir, name));
      expect(img.isEmpty, isFalse, reason: name);
      final w = img.cols, h = img.rows;
      final c = [for (final c in (corners as List).cast<List>()) Pt((c[0] as num) / w, (c[1] as num) / h)];
      final truth = Quad(c[0], c[1], c[2], c[3]);
      final sw = Stopwatch()..start();
      final det = detectQuad(img);
      sw.stop();

      final iou = quadIou(truth, det.quad);
      final err = meanCornerError(truth, det.quad, w, h);
      if (iou >= _minIou) passed++;
      rows.add(
        '${iou.toStringAsFixed(3)}  err ${(err * 100).toStringAsFixed(1).padLeft(5)}%  '
        'conf ${det.confidence.toStringAsFixed(2)}  ${det.source.padRight(8)} '
        '${sw.elapsedMilliseconds.toString().padLeft(4)} ms  $name',
      );

      _draw(img, truth, cv.Scalar(0, 200, 0));
      _draw(img, det.quad, cv.Scalar(0, 0, 255));
      cv.imwrite(p.join(_outDir, name.replaceAll(' ', '_')), img);
      img.dispose();
    }

    // ignore: avoid_print
    print('IoU    error         conf  fuente      tiempo\n${rows.join('\n')}\n$passed/${gt.length} con IoU ≥ $_minIou');
  });
}

void _draw(cv.Mat img, Quad q, cv.Scalar color) {
  final pts = cv.VecVecPoint.fromList([
    [for (final pt in q.toPixels(img.cols, img.rows)) cv.Point(pt.x.round(), pt.y.round())],
  ]);
  cv.polylines(img, pts, true, color, thickness: 4);
  pts.dispose();
}

/// IoU de dos cuadriláteros convexos, rasterizando en una grilla de 200×200.
double quadIou(Quad a, Quad b, {int grid = 200}) {
  var inter = 0, union = 0;
  for (var j = 0; j < grid; j++) {
    for (var i = 0; i < grid; i++) {
      final pt = Pt((i + 0.5) / grid, (j + 0.5) / grid);
      final ia = _inside(a, pt), ib = _inside(b, pt);
      if (ia && ib) inter++;
      if (ia || ib) union++;
    }
  }
  return union == 0 ? 0 : inter / union;
}

bool _inside(Quad q, Pt p) {
  final pts = q.points;
  double? sign;
  for (var i = 0; i < 4; i++) {
    final a = pts[i], b = pts[(i + 1) % 4];
    final cross = (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x);
    if (cross == 0) continue;
    sign ??= cross.sign;
    if (cross.sign != sign) return false;
  }
  return true;
}

/// Error medio por esquina como fracción de la diagonal de la imagen.
double meanCornerError(Quad a, Quad b, int w, int h) {
  final diag = math.sqrt(w * w + h * h);
  final pa = a.toPixels(w, h), pb = b.toPixels(w, h);
  var sum = 0.0;
  for (var i = 0; i < 4; i++) {
    sum += pa[i].distanceTo(pb[i]);
  }
  return sum / 4 / diag;
}
