import 'package:flutter/material.dart';

import '../../../../core/imaging/page_filter.dart';

/// Fila de chips para elegir el filtro de una página.
class FilterSelector extends StatelessWidget {
  const FilterSelector({
    super.key,
    required this.selected,
    required this.onSelected,
    this.onApplyToAll,
    this.enabled = true,
  });

  final PageFilter selected;
  final ValueChanged<PageFilter> onSelected;

  /// Si no es null se muestra un botón para aplicar [selected] a todas las páginas.
  final VoidCallback? onApplyToAll;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          for (final f in PageFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(f.label),
                selected: f == selected,
                onSelected: enabled ? (_) => onSelected(f) : null,
              ),
            ),
          if (onApplyToAll != null)
            TextButton(onPressed: enabled ? onApplyToAll : null, child: const Text('Aplicar a todas')),
        ],
      ),
    );
  }
}
