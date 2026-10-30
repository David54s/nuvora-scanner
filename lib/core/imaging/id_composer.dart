import 'dart:math' as math;

import 'package:opencv_dart/opencv.dart' as cv;

import 'filters.dart';
import 'id_layout.dart';
import 'perspective.dart';
import 'quad.dart';

/// Resolución de la hoja guardada (Carta = 2550 × 3300 px).
const idSheetDpi = 300.0;

/// Un lado ya leído en memoria. Quien llama es dueño de [image].
typedef IdSideImage = ({cv.Mat image, Quad quad, int rotation});

/// Compone la hoja de una identificación: papel blanco de [IdLayout.paper] a
/// [dpi] con cada lado recortado a su tamaño real (según la escala elegida),
/// derecho y filtrado, en la posición que da [IdLayout.placeCards].
/// Devuelve un Mat BGR nuevo.
cv.Mat composeIdSheet(List<IdSideImage> sides, IdLayout layout, {double dpi = idSheetDpi}) {
  int px(double mm) => (mm * dpi / 25.4).round();
  final sheet = cv.Mat.fromScalar(
    px(layout.paperHeightMm),
    px(layout.paperWidthMm),
    cv.MatType.CV_8UC3,
    cv.Scalar(255, 255, 255),
  );
  try {
    final rects = layout.placeCards(sides.length);
    for (final (i, side) in sides.indexed) {
      final r = rects[i];
      final x = px(r.x), y = px(r.y);
      final w = math.max(1, math.min(px(r.w), sheet.cols - x));
      final h = math.max(1, math.min(px(r.h), sheet.rows - y));
      final card = _cardImage(side, layout, w, h);
      final roi = sheet.region(cv.Rect(x, y, w, h));
      try {
        card.copyTo(roi);
      } finally {
        roi.dispose();
        card.dispose();
      }
    }
    return sheet;
  } catch (_) {
    sheet.dispose();
    rethrow;
  }
}

/// El lado recortado con la proporción de la plantilla, girado, llevado a
/// [w]×[h] y filtrado (BGR). El filtro va después de escalar para que el
/// resultado no dependa de la resolución de la foto.
cv.Mat _cardImage(IdSideImage s, IdLayout layout, int w, int h) {
  // Si el lado se giró 90°, en la foto la tarjeta está en vertical.
  final turned = s.rotation % 180 != 0;
  final aspect = turned ? 1 / layout.template.aspect : layout.template.aspect;
  cv.Mat? warped, upright, sized, filtered;
  try {
    warped = warpQuad(s.image, s.quad, aspect: aspect, maxSide: math.max(w, h));
    upright = rotateQuarterTurns(warped, s.rotation);
    final shrinking = upright.cols >= w;
    sized = cv.resize(upright, (w, h), interpolation: shrinking ? cv.INTER_AREA : cv.INTER_CUBIC);
    filtered = applyFilter(sized, layout.filter);
    if (filtered.channels == 1) return cv.cvtColor(filtered, cv.COLOR_GRAY2BGR);
    final out = filtered;
    filtered = null;
    return out;
  } finally {
    warped?.dispose();
    upright?.dispose();
    sized?.dispose();
    filtered?.dispose();
  }
}
