import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../recent_tools.dart';
import '../tools.dart';
import 'tool_tile.dart';

/// Fila de herramientas usadas recientemente (o todas, si aún no se usó
/// ninguna) para el Inicio.
class RecentToolsStrip extends ConsumerWidget {
  const RecentToolsStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(recentToolsProvider).value ?? const [];
    final tools = recent.isEmpty ? NuvoraTool.values : recent;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
          child: Row(
            children: [
              Expanded(child: Text(recent.isEmpty ? 'Herramientas' : 'Recientes', style: theme.textTheme.titleMedium)),
              TextButton(onPressed: () => context.go('/tools'), child: const Text('Ver todas')),
            ],
          ),
        ),
        SizedBox(
          height: 104,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: tools.length,
            separatorBuilder: (_, _) => const SizedBox(width: 4),
            itemBuilder: (context, i) => SizedBox(
              width: 92,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => openTool(context, ref, tools[i]),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  child: Column(
                    children: [
                      ToolIcon(tool: tools[i]),
                      const SizedBox(height: 6),
                      Text(
                        tools[i].label,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
