import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/ui/nuvora_nav_bar.dart';
import '../features/tools/tools.dart';

/// Pantallas principales (Inicio y Herramientas) con la barra inferior. El
/// botón redondo escanea un documento.
class MainShell extends ConsumerWidget {
  const MainShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const destinations = [
    NavDestination(
      label: 'Inicio',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
      color: Color(0xFF4FD1A5),
    ),
    NavDestination(
      label: 'Herramientas',
      icon: Icons.grid_view_outlined,
      selectedIcon: Icons.grid_view_rounded,
      color: Color(0xFF7AA2FF),
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = navigationShell.currentIndex;
    return PopScope(
      // Atrás desde otra pestaña vuelve a Inicio en lugar de cerrar la app.
      canPop: index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) navigationShell.goBranch(0);
      },
      child: Scaffold(
        extendBody: true,
        body: navigationShell,
        bottomNavigationBar: NuvoraNavBar(
          destinations: destinations,
          selectedIndex: index,
          onSelected: (i) => navigationShell.goBranch(i, initialLocation: i == index),
          actionIcon: Icons.document_scanner_rounded,
          actionTooltip: 'Escanear',
          onAction: () => openTool(context, ref, NuvoraTool.scan),
        ),
      ),
    );
  }
}
