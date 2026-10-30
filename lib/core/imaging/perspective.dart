import 'dart:math' as math;

import 'package:opencv_dart/opencv.dart' as cv;

import 'quad.dart';

/// Lado máximo de la página resultante (A4 a 300 dpi), para acotar memoria.
const maxPageSide = 3508;

/// Corrige la perspectiva: lleva el [quad] (normalizado respecto a [src]) a un
/// rectángulo plano. Devuelve un Mat nuevo; no modifica [src].
///
/// Sin [aspect] el tamaño sale de los lados medidos en la foto. Con [aspect]
/// (ancho/alto, p. ej. de una hoja carta) se conserva el lado largo medido y
/// el otro se ajusta a esa proporción.
cv.Mat warpQuad(cv.Mat src, Quad quad, {int maxSide = maxPageSide, double? aspect}) {
  final p = quad.toPixels(src.cols, src.rows);
  final tl = p[0], tr = p[1], br = p[2], bl = p[3];
  var w = math.max(tl.distanceTo(tr), bl.distanceTo(br));
  var h = math.max(tl.distanceTo(bl), tr.distanceTo(br));
  if (aspect != null) {
    final measuredLong = math.max(w, h);
    if (aspect >= 1) {
      w = measuredLong;
      h = measuredLong / aspect;
    } else {
      h = measuredLong;
      w = measuredLong * aspect;
    }
  }
  final longSide = math.max(w, h);
  if (longSide > maxSide) {
    final s = maxSide / longSide;
    w *= s;
    h *= s;
  }
  final outW = math.max(1, w.round());
  final outH = math.max(1, h.round());

  final srcPts = cv.VecPoint2f.fromList([for (final q in p) cv.Point2f(q.x, q.y)]);
  final dstPts = cv.VecPoint2f.fromList([
    cv.Point2f(0, 0),
    cv.Point2f(outW - 1.0, 0),
    cv.Point2f(outW - 1.0, outH - 1.0),
    cv.Point2f(0, outH - 1.0),
  ]);
  final m = cv.getPerspectiveTransform2f(srcPts, dstPts);
  try {
    return cv.warpPerspective(src, m, (outW, outH), flags: cv.INTER_LINEAR, borderMode: cv.BORDER_REPLICATE);
  } finally {
    m.dispose();
    srcPts.dispose();
    dstPts.dispose();
  }
}

/// Rota en múltiplos de 90° (sentido horario). Devuelve un Mat nuevo.
cv.Mat rotateQuarterTurns(cv.Mat src, int degrees) {
  return switch (degrees % 360) {
    90 => cv.rotate(src, cv.ROTATE_90_CLOCKWISE),
    180 => cv.rotate(src, cv.ROTATE_180),
    270 => cv.rotate(src, cv.ROTATE_90_COUNTERCLOCKWISE),
    _ => src.clone(),
  };
}
