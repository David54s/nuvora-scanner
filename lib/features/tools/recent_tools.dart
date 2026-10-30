import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'tools.dart';

/// Herramientas usadas, la más reciente primero (sin repetir).
const recentToolsSetting = 'recent_tools';

/// Cuántas se recuerdan.
const maxRecentTools = 6;

/// Pone [tool] al frente de [recent], sin repetir y con [maxRecentTools] como máximo.
List<NuvoraTool> pushRecent(List<NuvoraTool> recent, NuvoraTool tool) =>
    [tool, ...recent.where((t) => t != tool)].take(maxRecentTools).toList();

final recentToolsProvider = AsyncNotifierProvider<RecentTools, List<NuvoraTool>>(RecentTools.new);

/// Lista de herramientas usadas recientemente, guardada en los ajustes.
class RecentTools extends AsyncNotifier<List<NuvoraTool>> {
  @override
  Future<List<NuvoraTool>> build() async {
    final raw = await ref.read(libraryRepositoryProvider).getSetting(recentToolsSetting);
    final byName = NuvoraTool.values.asNameMap();
    return [
      for (final name in (raw ?? '').split(','))
        if (byName[name] != null) byName[name]!,
    ];
  }

  Future<void> record(NuvoraTool tool) async {
    final next = pushRecent(state.value ?? await future, tool);
    state = AsyncData(next);
    await ref.read(libraryRepositoryProvider).setSetting(recentToolsSetting, next.map((t) => t.name).join(','));
  }
}
