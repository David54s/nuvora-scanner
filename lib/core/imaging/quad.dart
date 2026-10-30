import 'dart:convert';
import 'dart:math' as math;

/// Punto 2D en coordenadas normalizadas (0..1) o en píxeles, según el contexto.
class Pt {
  const Pt(this.x, this.y);

  final double x;
  final double y;

  Pt operator -(Pt o) => Pt(x - o.x, y - o.y);

  double distanceTo(Pt o) => math.sqrt(math.pow(x - o.x, 2) + math.pow(y - o.y, 2));

  Pt clamp01() => Pt(x.clamp(0.0, 1.0), y.clamp(0.0, 1.0));

  @override
  bool operator ==(Object other) => other is Pt && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'Pt(${x.toStringAsFixed(3)}, ${y.toStringAsFixed(3)})';
}

/// Cuadrilátero del documento con esquinas normalizadas (0..1) respecto a la
/// imagen original, en orden TL, TR, BR, BL.
class Quad {
  const Quad(this.tl, this.tr, this.br, this.bl);

  /// La imagen completa.
  static const full = Quad(Pt(0, 0), Pt(1, 0), Pt(1, 1), Pt(0, 1));

  /// Ordena cuatro puntos arbitrarios como TL, TR, BR, BL.
  factory Quad.fromUnordered(List<Pt> pts) {
    assert(pts.length == 4);
    Pt pick(double Function(Pt p) key, {required bool max}) => pts.reduce((a, b) => (key(a) > key(b)) == max ? a : b);
    final tl = pick((p) => p.x + p.y, max: false);
    final br = pick((p) => p.x + p.y, max: true);
    final tr = pick((p) => p.y - p.x, max: false);
    final bl = pick((p) => p.y - p.x, max: true);
    // Si un quad muy girado hace que dos claves elijan el mismo punto,
    // se ordena por ángulo alrededor del centroide.
    if ({tl, tr, br, bl}.length < 4) return Quad._byAngle(pts);
    return Quad(tl, tr, br, bl);
  }

  factory Quad._byAngle(List<Pt> pts) {
    final cx = pts.fold(0.0, (s, p) => s + p.x) / 4;
    final cy = pts.fold(0.0, (s, p) => s + p.y) / 4;
    final sorted = [...pts]..sort((a, b) => math.atan2(a.y - cy, a.x - cx).compareTo(math.atan2(b.y - cy, b.x - cx)));
    // atan2 creciente con el eje y hacia abajo recorre en sentido horario
    // empezando por el lado izquierdo-superior; rotar para que el primero sea TL.
    var start = 0;
    for (var i = 1; i < 4; i++) {
      if (sorted[i].x + sorted[i].y < sorted[start].x + sorted[start].y) start = i;
    }
    final o = [for (var i = 0; i < 4; i++) sorted[(start + i) % 4]];
    return Quad(o[0], o[1], o[2], o[3]);
  }

  factory Quad.fromJson(String json) {
    final v = (jsonDecode(json) as List).map((e) => (e as num).toDouble()).toList();
    return Quad(Pt(v[0], v[1]), Pt(v[2], v[3]), Pt(v[4], v[5]), Pt(v[6], v[7]));
  }

  final Pt tl;
  final Pt tr;
  final Pt br;
  final Pt bl;

  List<Pt> get points => [tl, tr, br, bl];

  String toJson() => jsonEncode([
    for (final p in points) ...[p.x, p.y],
  ]);

  Quad copyWithPoint(int index, Pt p) {
    final pts = points..[index] = p;
    return Quad(pts[0], pts[1], pts[2], pts[3]);
  }

  /// Escala de coordenadas normalizadas a píxeles.
  List<Pt> toPixels(int width, int height) => [for (final p in points) Pt(p.x * width, p.y * height)];

  /// Área con la fórmula del polígono (shoelace), en las unidades del quad.
  double get area {
    final p = points;
    var s = 0.0;
    for (var i = 0; i < 4; i++) {
      final a = p[i], b = p[(i + 1) % 4];
      s += a.x * b.y - b.x * a.y;
    }
    return s.abs() / 2;
  }

  /// Verdadero si el polígono es convexo y no está degenerado.
  bool get isConvex {
    final p = points;
    double? sign;
    for (var i = 0; i < 4; i++) {
      final a = p[i], b = p[(i + 1) % 4], c = p[(i + 2) % 4];
      final cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x);
      if (cross.abs() < 1e-9) return false;
      sign ??= cross.sign;
      if (cross.sign != sign) return false;
    }
    return area > 1e-4;
  }

  @override
  bool operator ==(Object other) =>
      other is Quad && other.tl == tl && other.tr == tr && other.br == br && other.bl == bl;

  @override
  int get hashCode => Object.hash(tl, tr, br, bl);

  @override
  String toString() => 'Quad($tl, $tr, $br, $bl)';
}
