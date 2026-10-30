import 'dart:math' as math;
import 'dart:typed_data';

import 'package:opencv_dart/opencv.dart' as cv;

import 'quad.dart';

/// Resultado de buscar el documento en una imagen.
class QuadDetection {
  const QuadDetection(this.quad, this.confidence, [this.source = 'none']);

  /// Esquinas normalizadas (0..1) respecto a la imagen recibida.
  final Quad quad;

  /// 0 = no se encontró nada (quad de imagen completa); 1 = detección limpia.
  final double confidence;

  /// Estrategia que produjo el quad (para depurar y para el banco de pruebas).
  final String source;

  bool get found => confidence > 0;
}

/// Lado largo al que se reduce la imagen antes de detectar.
const detectionSide = 512;

/// Puntuación mínima para dar por encontrado el documento.
const _minScore = 0.45;

/// Puntuación fija de un lado que coincide con el borde de la foto: la hoja
/// se sale del cuadro por ahí, así que no hay borde que comprobar.
const _frameSideScore = 0.35;

/// Busca el cuadrilátero del documento en una imagen BGR o de grises.
/// No modifica [image].
///
/// Genera candidatos con varias estrategias (contornos de bordes, regiones
/// claras, líneas rectas con los bordes de la foto como lados posibles), los
/// filtra por geometría y elige el de mejor puntuación según el soporte de
/// borde y el contraste a lo largo de cada lado. Con [fast] usa menos
/// variantes (para la vista previa en vivo).
QuadDetection detectQuad(cv.Mat image, {bool fast = false}) {
  final ctx = _Context.build(image, fast: fast);
  try {
    if (ctx.flat) return const QuadDetection(Quad.full, 0);
    _Candidate? best;
    for (final c in [...ctx.contourCandidates(), ...ctx.lineCandidates()]) {
      c.score = ctx.score(c.pts);
      if (best == null || c.score > best.score) best = c;
    }
    if (best == null || best.score < _minScore) return const QuadDetection(Quad.full, 0);
    final n = [for (final p in best.pts) Pt((p.x / (ctx.w - 1)).clamp(0.0, 1.0), (p.y / (ctx.h - 1)).clamp(0.0, 1.0))];
    return QuadDetection(Quad(n[0], n[1], n[2], n[3]), best.score.clamp(0.0, 1.0), best.source);
  } finally {
    ctx.dispose();
  }
}

class _Candidate {
  _Candidate(this.pts, this.source);

  /// Esquinas en píxeles de la imagen reducida, en orden TL, TR, BR, BL.
  final List<Pt> pts;
  final String source;
  double score = 0;
}

/// Imágenes intermedias compartidas por todas las estrategias.
class _Context {
  _Context._(this.w, this.h, this.fast);

  final int w;
  final int h;
  final bool fast;
  final _mats = <cv.Mat>[];

  /// Gris con el texto borrado (cierre morfológico): bordes de la hoja nítidos
  /// y casi nada de texto ni de las líneas de los formularios.
  late final cv.Mat smooth;
  late final Uint8List smoothData;

  /// Unión de los mapas de bordes, dilatada, para medir soporte de borde.
  late final Uint8List edgeData;

  /// Mapas binarios de los que salen contornos.
  final contourMaps = <(cv.Mat, String)>[];

  /// Bordes para la transformada de Hough.
  late final cv.Mat lineEdges;

  bool flat = false;

  T _keep<T extends cv.Mat>(T m) {
    _mats.add(m);
    return m;
  }

  static _Context build(cv.Mat image, {required bool fast}) {
    final longSide = math.max(image.cols, image.rows);
    final s = math.min(1.0, detectionSide / longSide);
    final w = math.max(1, (image.cols * s).round()), h = math.max(1, (image.rows * s).round());
    final ctx = _Context._(w, h, fast);

    final small = ctx._keep(s < 1 ? cv.resize(image, (w, h), interpolation: cv.INTER_AREA) : image.clone());
    final gray = ctx._keep(small.channels == 1 ? small.clone() : cv.cvtColor(small, cv.COLOR_BGR2GRAY));
    final blurred = ctx._keep(cv.medianBlur(gray, 5));
    final k7 = ctx._keep(cv.getStructuringElement(cv.MORPH_RECT, (7, 7)));
    // dartcv usa por defecto un borde constante 0, que oscurecería el marco y
    // lo haría pasar por documento; por eso se replica.
    ctx.smooth = ctx._keep(
      cv.morphologyEx(blurred, cv.MORPH_CLOSE, k7, iterations: 2, borderType: cv.BORDER_REPLICATE),
    );
    ctx.smoothData = ctx._data(ctx.smooth);

    final (_, stddev) = cv.meanStdDev(ctx.smooth);
    if (stddev.val1 < 6) {
      ctx.flat = true;
      return ctx;
    }

    // Umbrales de Canny a partir de la distribución del gradiente (Canny
    // compara gradientes, no brillo), más dos pares fijos.
    final hi = ctx._gradientPercentile(ctx.smooth, 0.9).clamp(20.0, 300.0);
    final pairs = fast ? [(0.4 * hi, hi)] : [(0.4 * hi, hi), (15.0, 45.0), (40.0, 120.0)];
    final k3 = ctx._keep(cv.getStructuringElement(cv.MORPH_RECT, (3, 3)));
    late cv.Mat union;
    for (final (i, (lo, high)) in pairs.indexed) {
      final edges = ctx._keep(cv.canny(ctx.smooth, lo, high));
      final dil = ctx._keep(cv.dilate(edges, k3, borderType: cv.BORDER_REPLICATE));
      ctx.contourMaps.add((dil, 'canny'));
      if (i == 0) {
        ctx.lineEdges = edges;
        union = dil;
      } else {
        union = ctx._keep(cv.bitwiseOR(union, dil));
      }
    }

    if (!fast && small.channels == 3) {
      // La hoja tiene poca saturación; mesas y telas, en general no.
      final hsv = ctx._keep(cv.cvtColor(small, cv.COLOR_BGR2HSV));
      final planes = cv.split(hsv);
      final sat = ctx._keep(cv.medianBlur(planes[1], 5));
      planes.dispose();
      final satEdges = ctx._keep(cv.canny(sat, 20, 60));
      final satDil = ctx._keep(cv.dilate(satEdges, k3, borderType: cv.BORDER_REPLICATE));
      ctx.contourMaps.add((satDil, 'sat'));
      union = ctx._keep(cv.bitwiseOR(union, satDil));
      final (_, satBin) = cv.threshold(sat, 0, 255, cv.THRESH_BINARY_INV | cv.THRESH_OTSU);
      ctx.contourMaps.add((ctx._keep(ctx._open(satBin)), 'sat-otsu'));
      satBin.dispose();
    }

    // Región clara: la hoja suele ser lo más brillante. La apertura corta los
    // puentes finos con otras zonas claras del fondo.
    final (_, bright) = cv.threshold(ctx.smooth, 0, 255, cv.THRESH_BINARY | cv.THRESH_OTSU);
    ctx.contourMaps.add((ctx._keep(ctx._open(bright)), 'otsu'));
    bright.dispose();

    final k5 = ctx._keep(cv.getStructuringElement(cv.MORPH_RECT, (5, 5)));
    ctx.edgeData = ctx._data(ctx._keep(cv.dilate(union, k5, borderType: cv.BORDER_REPLICATE)));
    return ctx;
  }

  cv.Mat _open(cv.Mat bin) {
    final k = _keep(cv.getStructuringElement(cv.MORPH_RECT, (9, 9)));
    return cv.morphologyEx(bin, cv.MORPH_OPEN, k, borderType: cv.BORDER_REPLICATE);
  }

  Uint8List _data(cv.Mat m) => (m.isContinuous ? m : _keep(m.clone())).data;

  /// Percentil [q] de la magnitud del gradiente en la norma L1 (|gx|+|gy|),
  /// la misma que usa Canny por defecto.
  double _gradientPercentile(cv.Mat gray, double q) {
    final gx = _keep(cv.sobel(gray, cv.MatType.CV_16S, 1, 0));
    final gy = _keep(cv.sobel(gray, cv.MatType.CV_16S, 0, 1));
    // (|gx| + |gy|) / 2 en 8 bits; al final se deshace la escala.
    final mag = _keep(cv.add(_keep(cv.convertScaleAbs(gx, alpha: 0.5)), _keep(cv.convertScaleAbs(gy, alpha: 0.5))));
    final hist = List<int>.filled(256, 0);
    for (final v in _data(mag)) {
      hist[v]++;
    }
    final target = q * mag.rows * mag.cols;
    var acc = 0;
    for (var i = 0; i < 256; i++) {
      acc += hist[i];
      if (acc >= target) return i * 2.0;
    }
    return 510;
  }

  // ---------------- Candidatos por contorno ----------------

  List<_Candidate> contourCandidates() {
    final out = <_Candidate>[];
    final minArea = w * h * 0.10;
    for (final (map, source) in contourMaps) {
      final (contours, hierarchy) = cv.findContours(map, cv.RETR_LIST, cv.CHAIN_APPROX_SIMPLE);
      try {
        // Se ordena por área de la envolvente convexa: un contorno de bordes
        // abierto tiene área casi nula aunque rodee la hoja.
        final hulls = <(cv.VecPoint, double)>[];
        for (final c in contours) {
          if (c.length < 4) continue;
          final hullMat = cv.convexHull(c);
          final hull = cv.VecPoint.fromMat(hullMat);
          hullMat.dispose();
          final area = cv.contourArea(hull);
          if (area >= minArea) {
            hulls.add((hull, area));
          } else {
            hull.dispose();
          }
        }
        hulls.sort((a, b) => b.$2.compareTo(a.$2));
        for (final (i, (hull, _)) in hulls.indexed) {
          if (i < (fast ? 3 : 6)) {
            final quad = cv.approxPolyN(hull, 4, ensure_convex: true);
            if (quad.length == 4) {
              out.add(_Candidate(_order([for (final p in quad) Pt(p.x.toDouble(), p.y.toDouble())]), source));
            }
            quad.dispose();
          }
          hull.dispose();
        }
      } finally {
        contours.dispose();
        hierarchy.dispose();
      }
    }
    return out;
  }

  // ---------------- Candidatos por líneas ----------------

  List<_Candidate> lineCandidates() {
    final minSide = math.min(w, h);
    final segs = cv.HoughLinesP(
      lineEdges,
      1,
      math.pi / 180,
      40,
      minLineLength: 0.15 * minSide,
      maxLineGap: 0.04 * minSide,
    );
    final horizontal = <_Line>[], vertical = <_Line>[];
    try {
      final n = segs.rows;
      if (n > 0) {
        final raw = Int32List.view(segs.data.buffer, segs.data.offsetInBytes, n * 4);
        for (var i = 0; i < n; i++) {
          final line = _Line.fromSegment(
            raw[i * 4].toDouble(),
            raw[i * 4 + 1].toDouble(),
            raw[i * 4 + 2].toDouble(),
            raw[i * 4 + 3].toDouble(),
          );
          (line.isHorizontal ? horizontal : vertical).add(line);
        }
      }
    } finally {
      segs.dispose();
    }

    final diag = math.sqrt(w * w + h * h);
    final hs = _cluster(horizontal, diag)..addAll([_Line.virtual(0, 1, 0), _Line.virtual(0, 1, h - 1.0)]);
    final vs = _cluster(vertical, diag)..addAll([_Line.virtual(1, 0, 0), _Line.virtual(1, 0, w - 1.0)]);

    final out = <_Candidate>[];
    for (final (top, bottom) in _orderedPairs(hs, (l) => l.yAt(w / 2), 0.2 * h)) {
      for (final (left, right) in _orderedPairs(vs, (l) => l.xAt(h / 2), 0.2 * w)) {
        // Las cuatro virtuales = imagen completa: no aporta nada.
        if (top.virtual && bottom.virtual && left.virtual && right.virtual) continue;
        final corners = [top.intersect(left), top.intersect(right), bottom.intersect(right), bottom.intersect(left)];
        if (corners.contains(null)) continue;
        final pts = <Pt>[];
        for (final p in corners.cast<Pt>()) {
          // Se tolera que una esquina caiga un poco fuera (hoja cortada) y se recorta.
          if (p.x < -0.08 * w || p.x > 1.08 * w || p.y < -0.08 * h || p.y > 1.08 * h) break;
          pts.add(Pt(p.x.clamp(0, w - 1.0), p.y.clamp(0, h - 1.0)));
        }
        if (pts.length == 4) out.add(_Candidate(pts, 'lines'));
      }
    }
    return out;
  }

  /// Pares (menor, mayor) según [pos], separados al menos [minGap].
  Iterable<(_Line, _Line)> _orderedPairs(List<_Line> lines, double Function(_Line) pos, double minGap) sync* {
    for (var a = 0; a < lines.length; a++) {
      for (var b = a + 1; b < lines.length; b++) {
        final pa = pos(lines[a]), pb = pos(lines[b]);
        if ((pa - pb).abs() < minGap) continue;
        yield pa < pb ? (lines[a], lines[b]) : (lines[b], lines[a]);
      }
    }
  }

  /// Agrupa segmentos casi colineales y devuelve las rectas con más longitud.
  List<_Line> _cluster(List<_Line> lines, double diag) {
    lines.sort((a, b) => b.length.compareTo(a.length));
    final clusters = <_Line>[];
    for (final l in lines) {
      final match = clusters.where((c) => c.isNear(l, diag)).firstOrNull;
      if (match == null) {
        clusters.add(l);
      } else {
        match.length += l.length;
      }
    }
    clusters.sort((a, b) => b.length.compareTo(a.length));
    return clusters.take(fast ? 5 : 10).toList();
  }

  // ---------------- Puntuación ----------------

  /// 0..1, o -1 si no pasa los filtros geométricos. Combina, por lado, el
  /// soporte de borde y el contraste entre ambos lados del borde; luego área
  /// y rectangularidad.
  double score(List<Pt> pts) {
    if (!_passesGates(pts)) return -1;
    final sides = [
      for (var i = 0; i < 4; i++)
        _onFrame(pts[i], pts[(i + 1) % 4]) ? _frameSideScore : _sideScore(pts[i], pts[(i + 1) % 4], pts),
    ];
    final sideScore = 0.5 * sides.reduce(math.min) + 0.5 * sides.reduce((x, y) => x + y) / 4;
    final area = math.sqrt(_area(pts) / (w * h));
    final rect = (1 - _meanAngleDeviation(pts) / 40).clamp(0.0, 1.0);
    return 0.5 * sideScore + 0.15 * area + 0.15 * rect + 0.2 * _uniformity(pts);
  }

  /// 1 si el interior es parejo (papel sin texto en [smooth]); baja si el
  /// quad abarca fondo (pantallas, caras, muebles).
  double _uniformity(List<Pt> pts) {
    const n = 16;
    var sum = 0.0, sumSq = 0.0;
    var count = 0;
    for (var j = 1; j < n; j++) {
      final v = j / n;
      for (var i = 1; i < n; i++) {
        final u = i / n;
        // Interpolación bilineal entre las cuatro esquinas.
        final x = (1 - v) * ((1 - u) * pts[0].x + u * pts[1].x) + v * ((1 - u) * pts[3].x + u * pts[2].x);
        final y = (1 - v) * ((1 - u) * pts[0].y + u * pts[1].y) + v * ((1 - u) * pts[3].y + u * pts[2].y);
        final s = _sample(x, y);
        if (s == null) continue;
        sum += s;
        sumSq += s * s;
        count++;
      }
    }
    if (count == 0) return 0;
    final mean = sum / count;
    final std = math.sqrt(math.max(0, sumSq / count - mean * mean));
    return (1 - std / 50).clamp(0.0, 1.0);
  }

  bool _passesGates(List<Pt> pts) {
    if (!Quad(pts[0], pts[1], pts[2], pts[3]).isConvex) return false;
    final ratio = _area(pts) / (w * h);
    if (ratio < 0.10 || ratio > 0.985) return false;
    for (var i = 0; i < 4; i++) {
      final ang = _angleAt(pts, i);
      if (ang < 50 || ang > 130) return false;
    }
    final l = [for (var i = 0; i < 4; i++) pts[i].distanceTo(pts[(i + 1) % 4])];
    return math.min(l[0], l[2]) / math.max(l[0], l[2]) >= 0.35 && math.min(l[1], l[3]) / math.max(l[1], l[3]) >= 0.35;
  }

  bool _onFrame(Pt a, Pt b) {
    const t = 3.0;
    return (a.x <= t && b.x <= t) ||
        (a.y <= t && b.y <= t) ||
        (a.x >= w - 1 - t && b.x >= w - 1 - t) ||
        (a.y >= h - 1 - t && b.y >= h - 1 - t);
  }

  /// Soporte de borde (fracción de muestras sobre un borde) y contraste entre
  /// muestras a ambos lados, en la imagen sin texto.
  double _sideScore(Pt a, Pt b, List<Pt> quad) {
    final len = a.distanceTo(b);
    if (len < 1) return 0;
    final dx = (b.x - a.x) / len, dy = (b.y - a.y) / len;
    // Normal que apunta hacia fuera del quad.
    final cx = quad.fold(0.0, (s, p) => s + p.x) / 4, cy = quad.fold(0.0, (s, p) => s + p.y) / 4;
    var nx = -dy, ny = dx;
    if ((a.x - cx) * nx + (a.y - cy) * ny < 0) {
      nx = -nx;
      ny = -ny;
    }
    const offset = 6.0;
    var samples = 0, hits = 0, contrastN = 0;
    var contrast = 0.0;
    // Se ignora el 8 % de cada extremo: las esquinas suelen estar tapadas o redondeadas.
    for (var t = 0.08 * len; t <= 0.92 * len; t += 2) {
      final x = a.x + dx * t, y = a.y + dy * t;
      final xi = x.round(), yi = y.round();
      if (xi < 0 || yi < 0 || xi >= w || yi >= h) continue;
      samples++;
      if (edgeData[yi * w + xi] != 0) hits++;
      final inside = _sample(x - nx * offset, y - ny * offset);
      final outside = _sample(x + nx * offset, y + ny * offset);
      if (inside != null && outside != null) {
        contrast += (inside - outside).abs();
        contrastN++;
      }
    }
    if (samples == 0) return 0;
    final c = contrastN == 0 ? 0.0 : math.min(1.0, contrast / contrastN / 40);
    return 0.6 * hits / samples + 0.4 * c;
  }

  int? _sample(double x, double y) {
    final xi = x.round(), yi = y.round();
    if (xi < 0 || yi < 0 || xi >= w || yi >= h) return null;
    return smoothData[yi * w + xi];
  }

  void dispose() {
    for (final m in _mats) {
      m.dispose();
    }
  }
}

/// Recta en forma normal: x·nx + y·ny = rho, con (nx, ny) unitario.
class _Line {
  _Line(this.nx, this.ny, this.rho, this.length, {this.virtual = false});

  factory _Line.fromSegment(double x1, double y1, double x2, double y2) {
    final len = math.sqrt(math.pow(x2 - x1, 2) + math.pow(y2 - y1, 2));
    var nx = -(y2 - y1) / len, ny = (x2 - x1) / len;
    // Normal canónica para poder comparar rectas: ny > 0, o nx > 0 si ny == 0.
    if (ny < 0 || (ny == 0 && nx < 0)) {
      nx = -nx;
      ny = -ny;
    }
    return _Line(nx, ny, nx * x1 + ny * y1, len);
  }

  /// Borde de la imagen como lado posible del documento.
  factory _Line.virtual(double nx, double ny, double rho) => _Line(nx, ny, rho, 0, virtual: true);

  final double nx;
  final double ny;
  final double rho;
  double length;
  final bool virtual;

  /// La dirección de la recta es más horizontal que vertical.
  bool get isHorizontal => ny.abs() > nx.abs();

  bool isNear(_Line o, double diag) {
    final dot = nx * o.nx + ny * o.ny;
    return dot.abs() > math.cos(4 * math.pi / 180) && (rho - o.rho * dot.sign).abs() < 0.02 * diag;
  }

  double yAt(double x) => ny.abs() < 1e-9 ? double.infinity : (rho - nx * x) / ny;
  double xAt(double y) => nx.abs() < 1e-9 ? double.infinity : (rho - ny * y) / nx;

  Pt? intersect(_Line o) {
    final det = nx * o.ny - ny * o.nx;
    if (det.abs() < 1e-9) return null;
    return Pt((rho * o.ny - ny * o.rho) / det, (nx * o.rho - rho * o.nx) / det);
  }
}

List<Pt> _order(List<Pt> pts) {
  final q = Quad.fromUnordered(pts);
  return [q.tl, q.tr, q.br, q.bl];
}

double _area(List<Pt> p) {
  var s = 0.0;
  for (var i = 0; i < 4; i++) {
    s += p[i].x * p[(i + 1) % 4].y - p[(i + 1) % 4].x * p[i].y;
  }
  return s.abs() / 2;
}

/// Ángulo interior, en grados, en la esquina [i].
double _angleAt(List<Pt> p, int i) {
  final prev = p[(i + 3) % 4], cur = p[i], next = p[(i + 1) % 4];
  final ax = prev.x - cur.x, ay = prev.y - cur.y, bx = next.x - cur.x, by = next.y - cur.y;
  final cos = (ax * bx + ay * by) / (math.sqrt(ax * ax + ay * ay) * math.sqrt(bx * bx + by * by));
  return math.acos(cos.clamp(-1.0, 1.0)) * 180 / math.pi;
}

double _meanAngleDeviation(List<Pt> p) =>
    [for (var i = 0; i < 4; i++) (_angleAt(p, i) - 90).abs()].reduce((a, b) => a + b) / 4;
