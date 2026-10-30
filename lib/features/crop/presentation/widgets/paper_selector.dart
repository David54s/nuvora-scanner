import 'package:flutter/material.dart';

import '../../../../core/imaging/paper_size.dart';

/// Fila de chips para elegir el tamaño de papel de una página.
class PaperSelector extends StatelessWidget {
  const PaperSelector({
    super.key,
    required this.selected,
    required this.onSelected,
    this.autoResolved,
    this.enabled = true,
  });

  final PaperSize selected;
  final ValueChanged<PaperSize> onSelected;

  /// Lo que eligió el modo automático, para mostrarlo en su chip ("Auto · Carta").
  final PaperSize? autoResolved;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Icon(Icons.straighten, size: 20, color: Theme.of(context).colorScheme.outline),
          ),
          for (final p in PaperSize.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(p == PaperSize.auto && autoResolved != null ? 'Auto · ${autoResolved!.label}' : p.label),
                selected: p == selected,
                onSelected: enabled ? (_) => onSelected(p) : null,
              ),
            ),
        ],
      ),
    );
  }
}
