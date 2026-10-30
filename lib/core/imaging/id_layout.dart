import 'dart:convert';
import 'dart:math' as math;

import 'page_filter.dart';
import 'paper_size.dart';
import 'quad.dart';

/// Tipo de identificación: tamaño real (en horizontal) y lados que se escanean.
enum IdTemplate {
  ine('INE / credencial', 'INE', 85.6, 54, ['Frente', 'Reverso']),
  license('Licencia de conducir', 'Licencia', 85.6, 54, ['Frente', 'Reverso']),
  card('Tarjeta', 'Tarjeta', 85.6, 54, ['Frente', 'Reverso']),

  /// Solo la página de datos (ISO ID-3).
  passport('Pasaporte', 'Pasaporte', 125, 88, ['Página de datos']);

  const IdTemplate(this.label, this.shortLabel, this.widthMm, this.heightMm, this.sides);

  final String label;

  /// Para el título del documento.
  final String shortLabel;
  final double widthMm;
  final double heightMm;
  final List<String> sides;

  /// Ancho / alto (> 1: horizontal).
  double get aspect => widthMm / heightMm;
}

enum IdArrangement {
  stacked('Apilados'),
  sideBySide('Lado a lado');

  const IdArrangement(this.label);
  final String label;
}

enum IdAnchor {
  top('Arriba'),
  center('Centro');

  const IdAnchor(this.label);
  final String label;
}

enum IdScale {
  real('Real', 1),
  large('125 %', 1.25),
  xlarge('150 %', 1.5),

  /// Lo más grande que quepa en el papel.
  fit('Máximo', null);

  const IdScale(this.label, this.factor);
  final String label;
  final double? factor;
}

/// Rectángulo en milímetros sobre el papel (origen arriba a la izquierda).
typedef MmRect = ({double x, double y, double w, double h});

/// Margen mínimo alrededor de las tarjetas.
const idMarginMm = 12.0;

/// Distancia del borde superior al primer lado con [IdAnchor.top].
const idTopMm = 25.0;

/// Separación entre lados.
const idGapMm = 10.0;

/// Cómo se acomodan los lados de una identificación sobre la hoja.
class IdLayout {
  const IdLayout({
    required this.template,
    this.arrangement = IdArrangement.stacked,
    this.anchor = IdAnchor.top,
    this.scale = IdScale.real,
    this.paper = PaperSize.letter,
    this.swapped = false,
    this.filter = PageFilter.original,
  });

  factory IdLayout.fromJson(Map<String, dynamic> j) {
    T pick<T extends Enum>(List<T> values, Object? name, T fallback) => values.asNameMap()[name] ?? fallback;
    final defaults = IdLayout(template: pick(IdTemplate.values, j['template'], IdTemplate.ine));
    return IdLayout(
      template: defaults.template,
      arrangement: pick(IdArrangement.values, j['arrangement'], defaults.arrangement),
      anchor: pick(IdAnchor.values, j['anchor'], defaults.anchor),
      scale: pick(IdScale.values, j['scale'], defaults.scale),
      paper: pick(PaperSize.physical, j['paper'], defaults.paper),
      swapped: j['swapped'] == true,
      filter: pick(PageFilter.values, j['filter'], defaults.filter),
    );
  }

  final IdTemplate template;
  final IdArrangement arrangement;
  final IdAnchor anchor;
  final IdScale scale;

  /// Solo tamaños reales ([PaperSize.physical]); la hoja va en vertical.
  final PaperSize paper;

  /// Intercambia el orden de los lados en la hoja.
  final bool swapped;
  final PageFilter filter;

  double get paperWidthMm => paper.shortMm!;
  double get paperHeightMm => paper.longMm!;

  IdLayout copyWith({
    IdTemplate? template,
    IdArrangement? arrangement,
    IdAnchor? anchor,
    IdScale? scale,
    PaperSize? paper,
    bool? swapped,
    PageFilter? filter,
  }) => IdLayout(
    template: template ?? this.template,
    arrangement: arrangement ?? this.arrangement,
    anchor: anchor ?? this.anchor,
    scale: scale ?? this.scale,
    paper: paper ?? this.paper,
    swapped: swapped ?? this.swapped,
    filter: filter ?? this.filter,
  );

  Map<String, dynamic> toJson() => {
    'template': template.name,
    'arrangement': arrangement.name,
    'anchor': anchor.name,
    'scale': scale.name,
    'paper': paper.name,
    'swapped': swapped,
    'filter': filter.name,
  };

  /// Dónde va cada uno de los [count] lados (en el orden en que se
  /// escanearon). Si la escala elegida no cabe en el papel, se reduce.
  List<MmRect> placeCards(int count) {
    if (count <= 0) return const [];
    final w = template.widthMm, h = template.heightMm;
    final gaps = (count - 1) * idGapMm;
    final availW = paperWidthMm - 2 * idMarginMm;
    final availH = paperHeightMm - (anchor == IdAnchor.top ? idTopMm : idMarginMm) - idMarginMm;
    final stacked = arrangement == IdArrangement.stacked;
    final maxScale = stacked
        ? math.min(availW / w, (availH - gaps) / (count * h))
        : math.min((availW - gaps) / (count * w), availH / h);
    final s = math.min(scale.factor ?? maxScale, maxScale);

    final cw = w * s, ch = h * s;
    final blockW = stacked ? cw : count * cw + gaps;
    final blockH = stacked ? count * ch + gaps : ch;
    final x0 = (paperWidthMm - blockW) / 2;
    final y0 = anchor == IdAnchor.top ? idTopMm : (paperHeightMm - blockH) / 2;
    final slots = [
      for (var i = 0; i < count; i++)
        (x: stacked ? x0 : x0 + i * (cw + idGapMm), y: stacked ? y0 + i * (ch + idGapMm) : y0, w: cw, h: ch),
    ];
    return swapped ? slots.reversed.toList() : slots;
  }
}

/// Un lado escaneado: foto original (ruta relativa al directorio de la app),
/// recorte y giro para dejarlo derecho.
class IdSide {
  const IdSide({required this.originalPath, required this.quad, this.rotation = 0});

  factory IdSide.fromJson(Map<String, dynamic> j) => IdSide(
    originalPath: j['original'] as String,
    quad: Quad.fromJson(jsonEncode(j['quad'])),
    rotation: (j['rotation'] as num?)?.toInt() ?? 0,
  );

  final String originalPath;
  final Quad quad;
  final int rotation;

  IdSide copyWith({String? originalPath, Quad? quad, int? rotation}) => IdSide(
    originalPath: originalPath ?? this.originalPath,
    quad: quad ?? this.quad,
    rotation: rotation ?? this.rotation,
  );

  Map<String, dynamic> toJson() => {'original': originalPath, 'quad': jsonDecode(quad.toJson()), 'rotation': rotation};
}

/// Lo necesario para volver a componer una página de identificación.
class IdComposition {
  const IdComposition({required this.layout, required this.sides});

  factory IdComposition.fromJson(String json) {
    final j = jsonDecode(json) as Map<String, dynamic>;
    return IdComposition(
      layout: IdLayout.fromJson(j['layout'] as Map<String, dynamic>),
      sides: [for (final s in j['sides'] as List) IdSide.fromJson(s as Map<String, dynamic>)],
    );
  }

  final IdLayout layout;
  final List<IdSide> sides;

  String toJson() => jsonEncode({
    'layout': layout.toJson(),
    'sides': [for (final s in sides) s.toJson()],
  });
}
