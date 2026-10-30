import 'package:flutter_test/flutter_test.dart';
import 'package:nuvora_scanner/core/imaging/id_layout.dart';
import 'package:nuvora_scanner/core/imaging/page_filter.dart';
import 'package:nuvora_scanner/core/imaging/paper_size.dart';
import 'package:nuvora_scanner/core/imaging/quad.dart';

void main() {
  const ine = IdLayout(template: IdTemplate.ine);

  test('por defecto: apilados arriba, tamaño real y centrados a lo ancho en Carta', () {
    final r = ine.placeCards(2);
    expect(r, hasLength(2));
    expect(r[0].w, closeTo(85.6, 1e-9));
    expect(r[0].h, closeTo(54, 1e-9));
    expect(r[0].x, closeTo((215.9 - 85.6) / 2, 1e-9));
    expect(r[0].y, idTopMm);
    expect(r[1].x, r[0].x);
    expect(r[1].y, closeTo(idTopMm + 54 + idGapMm, 1e-9));
  });

  test('al centro, el bloque queda centrado en la hoja', () {
    final r = ine.copyWith(anchor: IdAnchor.center).placeCards(2);
    final blockH = 2 * 54 + idGapMm;
    expect(r[0].y, closeTo((279.4 - blockH) / 2, 1e-9));
    expect(r[1].y + r[1].h, closeTo((279.4 + blockH) / 2, 1e-9));
  });

  test('lado a lado comparte la fila', () {
    final r = ine.copyWith(arrangement: IdArrangement.sideBySide).placeCards(2);
    expect(r[0].y, r[1].y);
    expect(r[1].x, closeTo(r[0].x + r[0].w + idGapMm, 1e-9));
    // Centrado: mismo margen a ambos lados.
    expect(r[0].x, closeTo(215.9 - (r[1].x + r[1].w), 1e-9));
  });

  test('si la escala no cabe se reduce hasta caber', () {
    final r = ine.copyWith(arrangement: IdArrangement.sideBySide, scale: IdScale.xlarge).placeCards(2);
    expect(r[0].w, lessThan(85.6 * 1.5));
    expect(r[0].x, closeTo(idMarginMm, 1e-9));
    expect(r[1].x + r[1].w, closeTo(215.9 - idMarginMm, 1e-9));
    // Conserva la proporción de la tarjeta.
    expect(r[0].w / r[0].h, closeTo(IdTemplate.ine.aspect, 1e-9));
  });

  test('Máximo crece hasta tocar el margen que limite', () {
    // Apilados en Carta limita el alto.
    final stacked = ine.copyWith(scale: IdScale.fit).placeCards(2);
    expect(stacked[1].y + stacked[1].h, closeTo(279.4 - idMarginMm, 1e-9));
    expect(stacked[0].w, lessThanOrEqualTo(215.9 - 2 * idMarginMm));
    // Un solo lado limita el ancho.
    final single = ine.copyWith(scale: IdScale.fit).placeCards(1);
    expect(single[0].w, closeTo(215.9 - 2 * idMarginMm, 1e-9));
  });

  test('150 % apilados sí cabe en Carta', () {
    final r = ine.copyWith(scale: IdScale.xlarge).placeCards(2);
    expect(r[0].w, closeTo(85.6 * 1.5, 1e-9));
  });

  test('intercambiar pone el segundo lado arriba', () {
    final normal = ine.placeCards(2);
    final swapped = ine.copyWith(swapped: true).placeCards(2);
    expect(swapped[0], normal[1]);
    expect(swapped[1], normal[0]);
  });

  test('pasaporte: un lado de 125 × 88 mm', () {
    const passport = IdLayout(template: IdTemplate.passport);
    expect(IdTemplate.passport.sides, hasLength(1));
    final r = passport.placeCards(1);
    expect(r.single.w, closeTo(125, 1e-9));
    expect(r.single.h, closeTo(88, 1e-9));
  });

  test('la composición sobrevive a JSON', () {
    final c = IdComposition(
      layout: ine.copyWith(
        arrangement: IdArrangement.sideBySide,
        anchor: IdAnchor.center,
        scale: IdScale.large,
        paper: PaperSize.oficio,
        swapped: true,
        filter: PageFilter.enhanced,
      ),
      sides: const [
        IdSide(
          originalPath: 'pages/u/side0_r0.jpg',
          quad: Quad(Pt(0.1, 0.2), Pt(0.9, 0.2), Pt(0.9, 0.7), Pt(0.1, 0.7)),
        ),
        IdSide(originalPath: 'pages/u/side1_r0.jpg', quad: Quad.full, rotation: 90),
      ],
    );
    final back = IdComposition.fromJson(c.toJson());
    expect(back.layout.toJson(), c.layout.toJson());
    expect(back.sides.map((s) => s.toJson()).toList(), c.sides.map((s) => s.toJson()).toList());
    expect(back.sides[1].rotation, 90);
    expect(back.sides[0].quad, c.sides[0].quad);
  });
}
