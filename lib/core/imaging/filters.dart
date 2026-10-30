import 'dart:math' as math;

import 'package:opencv_dart/opencv.dart' as cv;

import 'page_filter.dart';

/// Aplica [filter] a una página BGR ya recortada. Devuelve un Mat nuevo
/// (BGR o de un canal); no modifica [src].
cv.Mat applyFilter(cv.Mat src, PageFilter filter) {
  return switch (filter) {
    PageFilter.original => src.clone(),
    PageFilter.grayscale => _gray(src),
    PageFilter.bw => _blackAndWhite(src),
    PageFilter.enhanced => _enhance(src),
  };
}

cv.Mat _gray(cv.Mat src) => src.channels == 1 ? src.clone() : cv.cvtColor(src, cv.COLOR_BGR2GRAY);

const _bwThreshold = 128.0;

/// Tinta negra sobre blanco puro: la misma limpieza que "Mejorado" (quitar
/// sombra + niveles) y luego un corte a mitad de rango. Con el fondo ya
/// parejo y el texto ya oscuro, un umbral fijo conserva los trazos finos que
/// un umbral adaptativo rompe.
cv.Mat _blackAndWhite(cv.Mat src) {
  final gray = _gray(src);
  final flat = _removeShadows(gray);
  final lut = _levelsLut(flat);
  final leveled = cv.LUT(flat, lut);
  try {
    final (_, bw) = cv.threshold(leveled, _bwThreshold, 255, cv.THRESH_BINARY);
    return bw;
  } finally {
    gray.dispose();
    flat.dispose();
    lut.dispose();
    leveled.dispose();
  }
}

/// Parámetros de "Mejorado", calibrados con fotos reales de documentos para
/// que se parezcan a un escaneo: fondo blanco puro y texto negro nítido.
///
/// Todo lo que tras quitar la sombra queda por encima de este nivel se vuelve
/// blanco (papel, sombras residuales, textura).
const _enhanceWhitePoint = 230.0;

/// Curva de los medios tonos: > 1 oscurece el trazo sin tocar el blanco.
const _enhanceGamma = 1.45;

/// Percentil de luminancia que se lleva a negro.
const _enhanceBlackPercentile = 0.01;
const _enhanceSaturation = 1.35;
const _enhanceSharpenAmount = 0.4;

/// Mejora tipo escaneo:
/// 1. quita sombras dividiendo cada canal entre su fondo estimado,
/// 2. aplica niveles (punto blanco, punto negro y gamma) para dejar el papel
///    blanco y el texto negro,
/// 3. realza un poco el color (firmas, sellos) y
/// 4. enfoca levemente.
cv.Mat _enhance(cv.Mat src) {
  final flat = _removeShadows(src);
  cv.Mat? leveled, lut;
  try {
    lut = _levelsLut(flat);
    leveled = cv.LUT(flat, lut);
    if (leveled.channels == 3) {
      final saturated = _boostSaturation(leveled, _enhanceSaturation);
      leveled.dispose();
      leveled = saturated;
    }
    final blurred = cv.gaussianBlur(leveled, (0, 0), 1.0);
    try {
      return cv.addWeighted(leveled, 1 + _enhanceSharpenAmount, blurred, -_enhanceSharpenAmount, 0);
    } finally {
      blurred.dispose();
    }
  } finally {
    flat.dispose();
    lut?.dispose();
    leveled?.dispose();
  }
}

/// Estima el fondo de cada canal (cierre + mediana grande), divide el canal
/// entre su fondo y estira el contraste.
cv.Mat _removeShadows(cv.Mat src) {
  final planes = cv.split(src);
  final out = <cv.Mat>[];
  try {
    for (final plane in planes) {
      final bg = _background(plane);
      final divided = cv.divide(plane, bg, scale: 255);
      final normalized = cv.normalize(divided, cv.Mat.empty(), alpha: 0, beta: 255, normType: cv.NORM_MINMAX);
      bg.dispose();
      divided.dispose();
      out.add(normalized);
    }
    if (out.length == 1) return out.removeLast();
    final vec = cv.VecMat.fromList(out);
    try {
      return cv.merge(vec);
    } finally {
      vec.dispose();
    }
  } finally {
    for (final m in out) {
      m.dispose();
    }
    planes.dispose();
  }
}

/// Tabla de 256 valores: niveles con punto negro (percentil de la luminancia
/// de [img]), punto blanco fijo y gamma.
cv.Mat _levelsLut(cv.Mat img) {
  final gray = img.channels == 1 ? img.clone() : cv.cvtColor(img, cv.COLOR_BGR2GRAY);
  final hist = List<int>.filled(256, 0);
  for (final v in (gray.isContinuous ? gray : gray.clone()).data) {
    hist[v]++;
  }
  final target = gray.rows * gray.cols * _enhanceBlackPercentile;
  gray.dispose();
  var black = 0, acc = 0;
  while (black < 255 && acc + hist[black] < target) {
    acc += hist[black++];
  }
  // Si casi no hay tinta, el percentil cae en el papel: se acota.
  final b = math.min(black.toDouble(), 120.0);
  final range = _enhanceWhitePoint - b;
  return cv.Mat.fromList(1, 256, cv.MatType.CV_8UC1, [
    for (var v = 0; v < 256; v++)
      v <= b
          ? 0
          : v >= _enhanceWhitePoint
          ? 255
          : (255 * math.pow((v - b) / range, _enhanceGamma)).round(),
  ]);
}

cv.Mat _boostSaturation(cv.Mat bgr, double factor) {
  final hsv = cv.cvtColor(bgr, cv.COLOR_BGR2HSV);
  final planes = cv.split(hsv);
  final boosted = planes[1].convertTo(cv.MatType.CV_8UC1, alpha: factor);
  final vec = cv.VecMat.fromList([planes[0], boosted, planes[2]]);
  final merged = cv.merge(vec);
  try {
    return cv.cvtColor(merged, cv.COLOR_HSV2BGR);
  } finally {
    hsv.dispose();
    planes.dispose();
    boosted.dispose();
    vec.dispose();
    merged.dispose();
  }
}

/// Fondo de un canal, calculado a media escala por velocidad.
cv.Mat _background(cv.Mat plane) {
  final half = cv.resize(plane, (
    math.max(1, plane.cols ~/ 2),
    math.max(1, plane.rows ~/ 2),
  ), interpolation: cv.INTER_AREA);
  final kernel = cv.getStructuringElement(cv.MORPH_RECT, (7, 7));
  final dilated = cv.dilate(half, kernel, borderType: cv.BORDER_REPLICATE);
  final blurred = cv.medianBlur(dilated, 21);
  try {
    return cv.resize(blurred, (plane.cols, plane.rows), interpolation: cv.INTER_LINEAR);
  } finally {
    half.dispose();
    kernel.dispose();
    dilated.dispose();
    blurred.dispose();
  }
}
