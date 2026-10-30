import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/imaging/id_layout.dart';
import '../application/id_scan_session.dart';

/// Flujo completo de una identificación: elegir plantilla → tomar cada lado →
/// acomodar → guardar. Devuelve el id del documento creado, o null si se
/// canceló.
Future<int?> startIdScan(BuildContext context, WidgetRef ref, {int? folderId}) async {
  final template = await showIdTemplateSheet(context);
  if (template == null || !context.mounted) return null;
  final session = ref.read(idScanSessionProvider.notifier);
  await session.start(template, folderId: folderId);
  try {
    if (!context.mounted) return null;
    final captured = await context.push<bool>('/id/capture');
    if (captured != true || !context.mounted) return null;
    return await context.push<int>('/id/layout');
  } finally {
    await session.discard();
  }
}

/// Pide el tipo de identificación.
Future<IdTemplate?> showIdTemplateSheet(BuildContext context) {
  return showModalBottomSheet<IdTemplate>(
    context: context,
    showDragHandle: true,
    // Alto según el contenido, con desplazamiento si no cabe.
    isScrollControlled: true,
    builder: (context) {
      final theme = Theme.of(context);
      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text('¿Qué vas a escanear?', style: theme.textTheme.titleLarge),
              ),
              for (final t in IdTemplate.values)
                ListTile(
                  leading: IdCardIcon(template: t),
                  title: Text(t.label),
                  subtitle: Text(
                    '${t.sides.length == 1 ? '1 lado' : '${t.sides.length} lados'} · '
                    '${_mm(t.widthMm)} × ${_mm(t.heightMm)} mm',
                  ),
                  onTap: () => Navigator.pop(context, t),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
}

String _mm(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

/// Dibujo de la tarjeta con su proporción real.
class IdCardIcon extends StatelessWidget {
  const IdCardIcon({super.key, required this.template, this.width = 44});

  final IdTemplate template;
  final double width;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final passport = template == IdTemplate.passport;
    return Container(
      width: width,
      height: width / template.aspect,
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(width * 0.08),
        border: Border.all(color: colors.primary, width: 1.5),
      ),
      padding: EdgeInsets.all(width * 0.08),
      child: Row(
        children: [
          // Foto del titular.
          AspectRatio(
            aspectRatio: 0.8,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: passport ? 0.35 : 0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          SizedBox(width: width * 0.08),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (var i = 0; i < 3; i++) Container(height: 2, color: colors.primary.withValues(alpha: 0.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
