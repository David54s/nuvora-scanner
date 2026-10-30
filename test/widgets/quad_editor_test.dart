import 'dart:typed_data';

import 'package:nuvora_scanner/core/imaging/quad.dart';
import 'package:nuvora_scanner/features/crop/presentation/widgets/quad_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// PNG transparente de 1×1.
final _png = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

void main() {
  testWidgets('arrastrar una esquina actualiza el quad normalizado', (tester) async {
    const initial = Quad(Pt(0.1, 0.1), Pt(0.9, 0.1), Pt(0.9, 0.9), Pt(0.1, 0.9));
    var quad = initial;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 400,
            height: 400,
            child: StatefulBuilder(
              builder: (context, setState) => QuadEditor(
                image: MemoryImage(_png),
                imageSize: const Size(1000, 1000),
                quad: quad,
                onChanged: (q) => setState(() => quad = q),
              ),
            ),
          ),
        ),
      ),
    );

    // La imagen ocupa 352×352 (400 menos el margen de las manijas): 0.1 → 35.2 px.
    await tester.drag(
      find.byKey(const ValueKey('quad-handle-0')),
      const Offset(35.2, 35.2),
      touchSlopX: 0,
      touchSlopY: 0,
    );
    await tester.pumpAndSettle();

    expect(quad.tl.x, closeTo(0.2, 0.01));
    expect(quad.tl.y, closeTo(0.2, 0.01));
    expect(quad.tr, initial.tr);
    expect(quad.br, initial.br);
    expect(quad.bl, initial.bl);
  });

  testWidgets('las esquinas no salen de la imagen', (tester) async {
    var quad = Quad.full;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 400,
            height: 400,
            child: StatefulBuilder(
              builder: (context, setState) => QuadEditor(
                image: MemoryImage(_png),
                imageSize: const Size(1000, 1000),
                quad: quad,
                onChanged: (q) => setState(() => quad = q),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.drag(find.byKey(const ValueKey('quad-handle-2')), const Offset(300, 300));
    await tester.pumpAndSettle();
    expect(quad.br, const Pt(1, 1));
  });
}
