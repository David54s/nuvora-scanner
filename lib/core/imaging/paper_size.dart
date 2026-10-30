import 'dart:math' as math;

import 'quad.dart';

/// Tamaño de papel al que se ajusta una página recortada.
enum PaperSize {
  /// Carta u Oficio, según la proporción real estimada de la hoja.
  auto('Auto'),
  letter('Carta', 215.9, 279.4),

  /// Oficio mexicano (21.6 × 34 cm).
  oficio('Oficio', 216, 340),
  a4('A4', 210, 297),

  /// Las proporciones medidas en la foto, sin ajustar.
  original('Original');

  const PaperSize(this.label, [this.shortMm, this.longMm]);

  final String label;
  final double? shortMm;
  final double? longMm;

  /// Lado largo / lado corto, o null para [auto] y [original].
  double? get ratio => longMm == null ? null : longMm! / shortMm!;

  /// Tamaños reales de papel (sin [auto] ni [original]).
  static const physical = [letter, oficio, a4];
}

/// Límites de [PaperSize.auto]: más chato que Carta o más alargado que Oficio
/// se deja como está (recibos, credenciales).
const _autoMinRatio = 1.15;
const _letterOficioBoundary = 1.43;
const _autoMaxRatio = 1.75;

/// Si la hoja está cortada por el borde de la foto, lo visible no es la hoja
/// entera: solo se ajusta si ya se parece mucho a Carta u Oficio, para que la
/// deformación quede acotada a este margen.
const _cutTolerance = 0.05;

/// Proporción ancho/alto que debe tener la página, o null si se conservan
/// las proporciones medidas en la foto.
double? targetAspect(PaperSize choice, Quad quad, int imageWidth, int imageHeight) {
  final ratio = resolvePaper(choice, quad, imageWidth, imageHeight).ratio;
  if (ratio == null) return null;
  final landscape = estimateAspect(quad, imageWidth, imageHeight) > 1;
  return landscape ? ratio : 1 / ratio;
}

/// El tamaño concreto que corresponde a [choice] (resuelve [PaperSize.auto]).
PaperSize resolvePaper(PaperSize choice, Quad quad, int imageWidth, int imageHeight) {
  if (choice != PaperSize.auto) return choice;
  final a = estimateAspect(quad, imageWidth, imageHeight);
  final r = a >= 1 ? a : 1 / a;
  if (touchesFrame(quad)) {
    for (final p in const [PaperSize.letter, PaperSize.oficio]) {
      if ((r - p.ratio!).abs() / p.ratio! <= _cutTolerance) return p;
    }
    return PaperSize.original;
  }
  if (r < _autoMinRatio || r > _autoMaxRatio) return PaperSize.original;
  return r < _letterOficioBoundary ? PaperSize.letter : PaperSize.oficio;
}

/// Algún lado del quad coincide con el borde de la imagen.
bool touchesFrame(Quad q) {
  const t = 0.005;
  final p = q.points;
  for (var i = 0; i < 4; i++) {
    final a = p[i], b = p[(i + 1) % 4];
    if ((a.x <= t && b.x <= t) ||
        (a.y <= t && b.y <= t) ||
        (a.x >= 1 - t && b.x >= 1 - t) ||
        (a.y >= 1 - t && b.y >= 1 - t)) {
      return true;
    }
  }
  return false;
}

/// Estima la proporción ancho/alto *real* del rectángulo fotografiado en
/// perspectiva (Zhang y He, "Whiteboard scanning and image enhancement",
/// 2007). Supone píxeles cuadrados y el punto principal en el centro de la
/// imagen; estima la distancia focal a partir del propio cuadrilátero y, si
/// no se puede (lados casi paralelos), usa una focal típica de teléfono.
double estimateAspect(Quad q, int imageWidth, int imageHeight) {
  final cx = imageWidth / 2, cy = imageHeight / 2;
  // Coordenadas homogéneas centradas. Orden del método: m1 = TL, m2 = TR,
  // m3 = BL, m4 = BR.
  List<double> h(Pt p) => [p.x * imageWidth - cx, p.y * imageHeight - cy, 1];
  final m1 = h(q.tl), m2 = h(q.tr), m3 = h(q.bl), m4 = h(q.br);

  final k2 = _dot(_cross(m1, m4), m3) / _dot(_cross(m2, m4), m3);
  final k3 = _dot(_cross(m1, m4), m2) / _dot(_cross(m3, m4), m2);
  final n2 = [for (var i = 0; i < 3; i++) k2 * m2[i] - m1[i]];
  final n3 = [for (var i = 0; i < 3; i++) k3 * m3[i] - m1[i]];

  final longSide = math.max(imageWidth, imageHeight).toDouble();
  final fallbackF = 0.8 * longSide;
  var f = fallbackF;
  final denom = n2[2] * n3[2];
  if (denom.abs() > 1e-12) {
    final f2 = -(n2[0] * n3[0] + n2[1] * n3[1]) / denom;
    // Fuera de un rango razonable la estimación es ruido (casi sin perspectiva).
    if (f2 > 0 && math.sqrt(f2) > 0.3 * longSide && math.sqrt(f2) < 3 * longSide) f = math.sqrt(f2);
  }
  final f2 = f * f;
  final num = (n2[0] * n2[0] + n2[1] * n2[1]) / f2 + n2[2] * n2[2];
  final den = (n3[0] * n3[0] + n3[1] * n3[1]) / f2 + n3[2] * n3[2];
  if (!num.isFinite || !den.isFinite || den <= 0 || num <= 0) return _measuredAspect(q, imageWidth, imageHeight);
  return math.sqrt(num / den);
}

/// Proporción medida directamente en la foto (promedio de lados opuestos).
double _measuredAspect(Quad q, int w, int h) {
  final p = q.toPixels(w, h);
  final width = (p[0].distanceTo(p[1]) + p[3].distanceTo(p[2])) / 2;
  final height = (p[0].distanceTo(p[3]) + p[1].distanceTo(p[2])) / 2;
  return height == 0 ? 1 : width / height;
}

/// Tamaño de papel cuya proporción coincide con una imagen de [width]×[height]
/// (para elegir la página del PDF), o null si no coincide con ninguno.
PaperSize? paperForImage(int width, int height) {
  final r = math.max(width, height) / math.min(width, height);
  for (final p in PaperSize.physical) {
    if ((r - p.ratio!).abs() / p.ratio! < 0.01) return p;
  }
  return null;
}

List<double> _cross(List<double> a, List<double> b) => [
  a[1] * b[2] - a[2] * b[1],
  a[2] * b[0] - a[0] * b[2],
  a[0] * b[1] - a[1] * b[0],
];

double _dot(List<double> a, List<double> b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
