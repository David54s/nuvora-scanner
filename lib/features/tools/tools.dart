import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../capture/presentation/start_scan.dart';
import '../id_card/presentation/start_id_scan.dart';
import 'recent_tools.dart';

/// Herramientas de la app (pantalla Herramientas y "Recientes" de Inicio).
enum NuvoraTool {
  scan('Escanear documento', 'Fotografía hojas y crea un PDF', Icons.document_scanner_outlined, Color(0xFF22C7CC)),
  idCard('Identificación', 'Frente y reverso en una sola hoja', Icons.badge_outlined, Color(0xFFF2994A));

  const NuvoraTool(this.label, this.description, this.icon, this.color);

  final String label;
  final String description;
  final IconData icon;
  final Color color;
}

/// Abre [tool] y la registra como usada. Si se crea un documento, lo abre.
Future<void> openTool(BuildContext context, WidgetRef ref, NuvoraTool tool) async {
  await ref.read(recentToolsProvider.notifier).record(tool);
  if (!context.mounted) return;
  final int? docId;
  switch (tool) {
    case NuvoraTool.scan:
      docId = await startScan(context, ref);
    case NuvoraTool.idCard:
      docId = await startIdScan(context, ref);
  }
  if (docId != null && context.mounted) await context.push('/doc/$docId');
}
