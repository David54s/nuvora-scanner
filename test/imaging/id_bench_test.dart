import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvora_scanner/core/imaging/id_composer.dart';
import 'package:nuvora_scanner/core/imaging/id_layout.dart';
import 'package:nuvora_scanner/core/imaging/page_filter.dart';
import 'package:nuvora_scanner/core/imaging/quad.dart';
import 'package:opencv_dart/opencv.dart' as cv;
import 'package:path/path.dart' as p;

/// Banco visual de la hoja de identificación con las fotos reales (fuera de
/// git: tienen datos personales). Usa dos fotos como "frente" y "reverso" y
/// guarda varias composiciones en `build/id_bench/` para revisarlas a ojo.
const _dir = 'test/fixtures/real';
const _outDir = 'build/id_bench';

void main() {
  final gtFile = File(p.join(_dir, 'ground_truth.json'));
  final skip = gtFile.existsSync() ? false : 'Sin fotos reales en $_dir';

  test('composiciones con fotos reales', skip: skip, () {
    final gt = (jsonDecode(gtFile.readAsStringSync()) as Map<String, dynamic>)..remove('_comment');
    Directory(_outDir).createSync(recursive: true);
    final sides = <IdSideImage>[];
    for (final MapEntry(key: name, value: corners) in gt.entries.take(2)) {
      final img = cv.imread(p.join(_dir, name));
      final c = [
        for (final c in (corners as List).cast<List>()) Pt((c[0] as num) / img.cols, (c[1] as num) / img.rows),
      ];
      // Las hojas están en vertical: se giran para que la "tarjeta" quede horizontal.
      sides.add((image: img, quad: Quad(c[0], c[1], c[2], c[3]), rotation: 90));
    }
    const base = IdLayout(template: IdTemplate.ine);
    final variants = {
      'apilados_arriba_original': base,
      'apilados_arriba_mejorado': base.copyWith(filter: PageFilter.enhanced),
      'lado_a_lado_150': base.copyWith(arrangement: IdArrangement.sideBySide, scale: IdScale.xlarge),
      'centro_maximo_intercambiado': base.copyWith(anchor: IdAnchor.center, scale: IdScale.fit, swapped: true),
    };
    for (final MapEntry(key: name, value: layout) in variants.entries) {
      final sheet = composeIdSheet(sides, layout);
      cv.imwrite(p.join(_outDir, '$name.jpg'), sheet);
      sheet.dispose();
    }
    for (final s in sides) {
      s.image.dispose();
    }
  });
}
