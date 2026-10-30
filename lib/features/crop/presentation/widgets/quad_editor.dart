import 'package:flutter/material.dart';

import '../../../../core/imaging/quad.dart';

/// Muestra una imagen con el cuadrilátero del documento encima y permite
/// arrastrar sus cuatro esquinas. Mientras se arrastra aparece una lupa.
class QuadEditor extends StatefulWidget {
  const QuadEditor({
    super.key,
    required this.image,
    required this.imageSize,
    required this.quad,
    required this.onChanged,
  });

  final ImageProvider image;

  /// Tamaño en píxeles de la imagen, para encajarla con BoxFit.contain.
  final Size imageSize;

  /// Esquinas normalizadas (0..1) en orden TL, TR, BR, BL.
  final Quad quad;
  final ValueChanged<Quad> onChanged;

  @override
  State<QuadEditor> createState() => _QuadEditorState();
}

class _QuadEditorState extends State<QuadEditor> {
  static const _handleHitSize = 48.0;
  static const _magnifierSize = 120.0;
  static const _labels = ['superior izquierda', 'superior derecha', 'inferior derecha', 'inferior izquierda'];

  int? _dragging;
  Offset? _dragPos;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Margen para que las manijas de los bordes se puedan tocar.
        final area = (Offset.zero & constraints.biggest).deflate(_handleHitSize / 2);
        final fitted = applyBoxFit(BoxFit.contain, widget.imageSize, area.size).destination;
        final rect = Alignment.center.inscribe(fitted, area);

        Offset toLocal(Pt p) => Offset(rect.left + p.x * rect.width, rect.top + p.y * rect.height);
        Pt toNorm(Offset o) =>
            Pt(((o.dx - rect.left) / rect.width).clamp(0.0, 1.0), ((o.dy - rect.top) / rect.height).clamp(0.0, 1.0));

        final points = [for (final p in widget.quad.points) toLocal(p)];
        final colors = Theme.of(context).colorScheme;
        final lineColor = widget.quad.isConvex ? colors.primary : colors.error;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fromRect(
              rect: rect,
              child: Image(image: widget.image, fit: BoxFit.fill, gaplessPlayback: true),
            ),
            Positioned.fill(
              child: CustomPaint(
                painter: _QuadPainter(points: points, color: lineColor),
              ),
            ),
            for (var i = 0; i < 4; i++)
              Positioned(
                left: points[i].dx - _handleHitSize / 2,
                top: points[i].dy - _handleHitSize / 2,
                child: Semantics(
                  label: 'Esquina ${_labels[i]}',
                  child: GestureDetector(
                    key: ValueKey('quad-handle-$i'),
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (_) => setState(() {
                      _dragging = i;
                      _dragPos = points[i];
                    }),
                    onPanUpdate: (d) {
                      final next = Offset(
                        (_dragPos!.dx + d.delta.dx).clamp(rect.left, rect.right),
                        (_dragPos!.dy + d.delta.dy).clamp(rect.top, rect.bottom),
                      );
                      setState(() => _dragPos = next);
                      widget.onChanged(widget.quad.copyWithPoint(i, toNorm(next)));
                    },
                    onPanEnd: (_) => setState(() {
                      _dragging = null;
                      _dragPos = null;
                    }),
                    child: SizedBox.square(
                      dimension: _handleHitSize,
                      child: Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 100),
                          width: _dragging == i ? 28 : 22,
                          height: _dragging == i ? 28 : 22,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: lineColor.withValues(alpha: 0.35),
                            border: Border.all(color: lineColor, width: 3),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (_dragPos != null) _buildMagnifier(constraints.biggest),
          ],
        );
      },
    );
  }

  /// Lupa en la esquina superior opuesta al dedo, para que no lo tape.
  Widget _buildMagnifier(Size size) {
    final pos = _dragPos!;
    final onLeft = pos.dx < size.width / 2 && pos.dy < size.height / 2 + _magnifierSize;
    final center = Offset(
      onLeft ? size.width - _magnifierSize / 2 - 8 : _magnifierSize / 2 + 8,
      _magnifierSize / 2 + 8,
    );
    return Positioned(
      left: center.dx - _magnifierSize / 2,
      top: center.dy - _magnifierSize / 2,
      child: IgnorePointer(
        child: RawMagnifier(
          size: const Size.square(_magnifierSize),
          magnificationScale: 2.5,
          focalPointOffset: pos - center,
          decoration: const MagnifierDecoration(
            shape: CircleBorder(side: BorderSide(color: Colors.white, width: 3)),
            shadows: [BoxShadow(blurRadius: 8, color: Colors.black45)],
          ),
          child: const Center(child: Icon(Icons.add, color: Colors.white, size: 20)),
        ),
      ),
    );
  }
}

class _QuadPainter extends CustomPainter {
  _QuadPainter({required this.points, required this.color});

  final List<Offset> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final poly = Path()..addPolygon(points, true);
    // Oscurece lo que queda fuera del documento.
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addPath(poly, Offset.zero);
    canvas.drawPath(outside, Paint()..color = Colors.black.withValues(alpha: 0.45));
    canvas.drawPath(
      poly,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(_QuadPainter old) => old.color != color || !_listEquals(old.points, points);

  static bool _listEquals(List<Offset> a, List<Offset> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
