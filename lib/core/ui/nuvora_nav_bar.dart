import 'package:flutter/material.dart';

/// Pestaña de la barra inferior.
class NavDestination {
  const NavDestination({required this.label, required this.icon, required this.selectedIcon, required this.color});

  final String label;
  final IconData icon;
  final IconData selectedIcon;

  /// Color del ícono (como en la barra de referencia, cada uno con el suyo).
  final Color color;
}

/// Fondo del logo de Nuvora.
const nuvoraNavBackground = Color(0xFF10121B);

/// Color de marca (el turquesa del logo).
const nuvoraBrand = Color(0xFF22C7CC);

/// Barra inferior flotante: una píldora oscura con las pantallas y, a la
/// derecha, el botón redondo de acción principal (escanear).
class NuvoraNavBar extends StatelessWidget {
  const NuvoraNavBar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    required this.actionIcon,
    required this.actionTooltip,
    required this.onAction,
  });

  final List<NavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final IconData actionIcon;
  final String actionTooltip;
  final VoidCallback onAction;

  /// Alto de la barra sin el margen inferior del sistema.
  static const height = 64.0;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: SizedBox(
          height: height,
          child: Row(
            children: [
              Expanded(
                child: Material(
                  color: nuvoraNavBackground,
                  elevation: 6,
                  shadowColor: Colors.black54,
                  shape: const StadiumBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        for (final (i, d) in destinations.indexed)
                          _Tab(destination: d, selected: i == selectedIndex, onTap: () => onSelected(i)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Tooltip(
                message: actionTooltip,
                child: Material(
                  color: nuvoraBrand,
                  elevation: 6,
                  shadowColor: Colors.black54,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: onAction,
                    child: SizedBox.square(
                      dimension: height,
                      child: Icon(actionIcon, color: nuvoraNavBackground, size: 30, semanticLabel: actionTooltip),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.destination, required this.selected, required this.onTap});

  final NavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      label: destination.label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: ShapeDecoration(
            shape: const StadiumBorder(),
            color: selected ? destination.color.withValues(alpha: 0.18) : Colors.transparent,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(selected ? destination.selectedIcon : destination.icon, color: destination.color, size: 26),
              if (selected) ...[
                const SizedBox(width: 8),
                Text(
                  destination.label,
                  style: TextStyle(color: destination.color, fontWeight: FontWeight.w600),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
