import 'dart:math' as math;

import 'package:nuvora_scanner/core/imaging/paper_size.dart';
import 'package:nuvora_scanner/core/imaging/quad.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fotografía sintética de una hoja de [wMm]×[hMm] inclinada [tiltX]/[tiltY]
/// grados, a [distMm] de una cámara con focal [f] px y sensor [imgW]×[imgH].
Quad photographRect(
  double wMm,
  double hMm, {
  double tiltX = 25,
  double tiltY = 15,
  double distMm = 450,
  double f = 3200,
  int imgW = 3000,
  int imgH = 4000,
  double offsetX = 0,
}) {
  final ax = tiltX * math.pi / 180, ay = tiltY * math.pi / 180;
  Pt project(double x, double y) {
    // Centrada en el origen, rotada en X y luego en Y, alejada en Z.
    var px = x - wMm / 2, py = y - hMm / 2, pz = 0.0;
    final y1 = py * math.cos(ax) - pz * math.sin(ax);
    final z1 = py * math.sin(ax) + pz * math.cos(ax);
    py = y1;
    pz = z1;
    final x2 = px * math.cos(ay) + pz * math.sin(ay);
    final z2 = -px * math.sin(ay) + pz * math.cos(ay);
    px = x2 + offsetX;
    pz = z2 + distMm;
    return Pt((f * px / pz + imgW / 2) / imgW, (f * py / pz + imgH / 2) / imgH);
  }

  return Quad(project(0, 0), project(wMm, 0), project(wMm, hMm), project(0, hMm));
}

void main() {
  group('estimateAspect', () {
    test('recupera la proporción de una hoja carta en perspectiva', () {
      final q = photographRect(215.9, 279.4);
      expect(estimateAspect(q, 3000, 4000), closeTo(215.9 / 279.4, 0.01));
    });

    test('recupera la proporción de una hoja oficio, más inclinada y descentrada', () {
      final q = photographRect(216, 340, tiltX: 35, tiltY: -20, offsetX: 40);
      expect(estimateAspect(q, 3000, 4000), closeTo(216 / 340, 0.012));
    });

    test('sin perspectiva usa los lados medidos', () {
      final q = photographRect(215.9, 279.4, tiltX: 0, tiltY: 0);
      expect(estimateAspect(q, 3000, 4000), closeTo(215.9 / 279.4, 0.005));
    });

    test('hoja apaisada da proporción > 1', () {
      final q = photographRect(279.4, 215.9, tiltX: 20, tiltY: 10);
      expect(estimateAspect(q, 3000, 4000), closeTo(279.4 / 215.9, 0.015));
    });
  });

  group('resolvePaper', () {
    test('auto elige carta u oficio según la hoja', () {
      expect(resolvePaper(PaperSize.auto, photographRect(215.9, 279.4), 3000, 4000), PaperSize.letter);
      expect(resolvePaper(PaperSize.auto, photographRect(216, 340, tiltX: 30), 3000, 4000), PaperSize.oficio);
    });

    test('auto deja como está lo que no parece carta ni oficio', () {
      // Un recibo angosto (8 × 25 cm).
      expect(resolvePaper(PaperSize.auto, photographRect(80, 250), 3000, 4000), PaperSize.original);
    });

    test('hoja cortada por el borde: solo se ajusta si ya casi es carta u oficio', () {
      // Visible 3000 × 3200: muy lejos de carta, se deja como está.
      const wide = Quad(Pt(0, 0.1), Pt(1, 0.1), Pt(1, 0.9), Pt(0, 0.9));
      expect(touchesFrame(wide), isTrue);
      expect(resolvePaper(PaperSize.auto, wide, 3000, 4000), PaperSize.original);
      expect(pageLayout(PaperSize.auto, wide, 3000, 4000), (warpAspect: null, paperAspect: null));
      // Visible 3000 × 3960 (1.32, a 2 % de carta): se ajusta a carta.
      const nearLetter = Quad(Pt(0, 0.005), Pt(1, 0.005), Pt(1, 0.995), Pt(0, 0.995));
      expect(resolvePaper(PaperSize.auto, nearLetter, 3000, 4000), PaperSize.letter);
    });
  });

  group('pageLayout', () {
    final letterPhoto = photographRect(215.9, 279.4);

    test('una carta con papel carta se ajusta exacto, sin márgenes', () {
      final l = pageLayout(PaperSize.letter, letterPhoto, 3000, 4000);
      expect(l.warpAspect, closeTo(215.9 / 279.4, 1e-9));
      expect(l.paperAspect, isNull);
    });

    test('una carta con papel oficio conserva su proporción y va sobre la hoja', () {
      final l = pageLayout(PaperSize.oficio, letterPhoto, 3000, 4000);
      expect(l.warpAspect, closeTo(215.9 / 279.4, 0.01), reason: 'no se deforma');
      expect(l.paperAspect, closeTo(216 / 340, 1e-9));
    });

    test('un recibo con papel carta lleva margen', () {
      final l = pageLayout(PaperSize.letter, photographRect(80, 250), 3000, 4000);
      expect(l.warpAspect, closeTo(80 / 250, 0.01));
      expect(l.paperAspect, closeTo(215.9 / 279.4, 1e-9));
    });

    test('la hoja apaisada usa el papel apaisado', () {
      final landscape = photographRect(279.4, 215.9, tiltX: 10, tiltY: 5);
      final l = pageLayout(PaperSize.letter, landscape, 3000, 4000);
      expect(l.warpAspect, closeTo(279.4 / 215.9, 1e-9));
      expect(l.paperAspect, isNull);
    });

    test('original conserva los lados medidos', () {
      expect(pageLayout(PaperSize.original, letterPhoto, 3000, 4000), (warpAspect: null, paperAspect: null));
    });
  });

  test('paperForImage reconoce el tamaño por la proporción', () {
    expect(paperForImage(2550, 3300), PaperSize.letter);
    expect(paperForImage(3300, 2550), PaperSize.letter);
    expect(paperForImage(2160, 3400), PaperSize.oficio);
    expect(paperForImage(2480, 3508), PaperSize.a4);
    expect(paperForImage(1000, 1000), isNull);
  });
}
