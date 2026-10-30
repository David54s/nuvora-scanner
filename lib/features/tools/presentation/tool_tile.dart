import 'package:flutter/material.dart';

import '../tools.dart';

/// Ícono de una herramienta sobre un cuadro de su color.
class ToolIcon extends StatelessWidget {
  const ToolIcon({super.key, required this.tool, this.size = 48});

  final NuvoraTool tool;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tool.color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(tool.icon, color: tool.color, size: size * 0.55),
    );
  }
}
