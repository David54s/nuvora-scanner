import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../tools.dart';
import 'tool_tile.dart';

/// Todas las herramientas disponibles.
class ToolsScreen extends ConsumerWidget {
  const ToolsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Herramientas')),
      body: ListView.separated(
        // Espacio inferior para la barra de navegación.
        padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.paddingOf(context).bottom + 16),
        itemCount: NuvoraTool.values.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          final tool = NuvoraTool.values[i];
          return Card.outlined(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => openTool(context, ref, tool),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    ToolIcon(tool: tool, size: 56),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tool.label, style: theme.textTheme.titleMedium),
                          const SizedBox(height: 4),
                          Text(tool.description, style: theme.textTheme.bodyMedium),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
