import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import 'router.dart';

class App extends ConsumerStatefulWidget {
  const App({super.key});

  @override
  ConsumerState<App> createState() => _AppState();
}

class _AppState extends ConsumerState<App> {
  @override
  void initState() {
    super.initState();
    _startupMaintenance();
  }

  /// Limpia restos de sesiones anteriores: capturas sin guardar, PDFs ya
  /// compartidos y carpetas de páginas que quedaron sin fila.
  Future<void> _startupMaintenance() async {
    final files = ref.read(fileStoreProvider);
    try {
      await files.clearCaptures();
      await files.clearExports();
      await ref.read(libraryRepositoryProvider).sweepOrphans();
    } catch (e) {
      debugPrint('Mantenimiento al iniciar falló: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Nuvora',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      routerConfig: ref.watch(routerProvider),
    );
  }

  ThemeData _theme(Brightness b) => ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF22C7CC), brightness: b),
    useMaterial3: true,
  );
}
