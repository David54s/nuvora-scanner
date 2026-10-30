import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvora_scanner/core/imaging/filters.dart';
import 'package:nuvora_scanner/core/imaging/page_filter.dart';
import 'package:nuvora_scanner/core/imaging/paper_size.dart';
import 'package:nuvora_scanner/core/imaging/perspective.dart';
import 'package:nuvora_scanner/core/imaging/quad.dart';
import 'package:opencv_dart/opencv.dart' as cv;
import 'package:path/path.dart' as p;

/// Banco de calibración de filtros con las fotos reales (fuera de git: tienen
/// datos personales). Recorta cada foto con su quad de `ground_truth.json`,
/// aplica los filtros y guarda el resultado en `build/filter_bench/` para
/// compararlo a ojo. Mide en "Mejorado" cuánto fondo queda blanco y qué tan
/// oscuro queda el texto.
const _dir = 'test/fixtures/real';
const _outDir = 'build/filter_bench';

void main() {
  final gtFile = File(p.join(_dir, 'ground_truth.json'));
  final skip = gtFile.existsSync() ? false : 'Sin fotos reales en $_dir';

  test('filtros con fotos reales', skip: skip, () {
    final gt = (jsonDecode(gtFile.readAsStringSync()) as Map<String, dynamic>)..remove('_comment');
    Directory(_outDir).createSync(recursive: true);
    final rows = <String>[];
    for (final MapEntry(key: name, value: corners) in gt.entries) {
      final img = cv.imread(p.join(_dir, name));
      final c = [
        for (final c in (corners as List).cast<List>()) Pt((c[0] as num) / img.cols, (c[1] as num) / img.rows),
      ];
      final quad = Quad(c[0], c[1], c[2], c[3]);
      final page = warpQuad(img, quad, aspect: pageLayout(PaperSize.auto, quad, img.cols, img.rows).warpAspect);
      final base = name.replaceAll(' ', '_').replaceAll('.jpeg', '');
      for (final f in [PageFilter.enhanced, PageFilter.bw]) {
        final out = applyFilter(page, f);
        cv.imwrite(p.join(_outDir, '${base}_${f.name}.jpg'), out);
        if (f == PageFilter.enhanced) {
          final (white, dark) = toneStats(out);
          rows.add(
            'blanco ${(white * 100).toStringAsFixed(1).padLeft(5)}%  '
            'texto ${dark.toStringAsFixed(0).padLeft(3)}  $name',
          );
        }
        out.dispose();
      }
      // La misma hoja forzada a Oficio: debe verse sin deformar, con blanco abajo.
      final oficio = pageLayout(PaperSize.oficio, quad, img.cols, img.rows);
      final warped = warpQuad(img, quad, aspect: oficio.warpAspect);
      final enhanced = applyFilter(warped, PageFilter.enhanced);
      final sheet = oficio.paperAspect == null ? enhanced.clone() : placeOnPaper(enhanced, oficio.paperAspect!);
      cv.imwrite(p.join(_outDir, '${base}_oficio.jpg'), sheet);
      for (final m in [warped, enhanced, sheet]) {
        m.dispose();
      }
      page.dispose();
      img.dispose();
    }
    // ignore: avoid_print
    print('Mejorado: % de píxeles con luminancia ≥ 245 y media del 3 % más oscuro\n${rows.join('\n')}');
  });
}

/// (fracción de píxeles con luminancia ≥ 245, media del 3 % más oscuro).
(double, double) toneStats(cv.Mat img) {
  final gray = img.channels == 1 ? img.clone() : cv.cvtColor(img, cv.COLOR_BGR2GRAY);
  final hist = List<int>.filled(256, 0);
  for (final v in gray.data) {
    hist[v]++;
  }
  final total = gray.rows * gray.cols;
  gray.dispose();
  final white = hist.sublist(245).fold(0, (a, b) => a + b) / total;
  final target = (total * 0.03).round();
  var count = 0, sum = 0;
  for (var v = 0; v < 256 && count < target; v++) {
    final take = (target - count).clamp(0, hist[v]);
    count += take;
    sum += take * v;
  }
  return (white, count == 0 ? 0 : sum / count);
}
