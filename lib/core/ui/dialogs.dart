import 'package:flutter/material.dart';

/// Pide un texto (nombre de carpeta, título…). Devuelve null si se cancela o
/// queda vacío.
Future<String?> showTextInputDialog(
  BuildContext context, {
  required String title,
  String initialValue = '',
  String confirmLabel = 'Guardar',
  String? hint,
}) async {
  final controller = TextEditingController(text: initialValue)
    ..selection = TextSelection(baseOffset: 0, extentOffset: initialValue.length);
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
        textCapitalization: TextCapitalization.sentences,
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: Text(confirmLabel)),
      ],
    ),
  );
  controller.dispose();
  final trimmed = result?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}

Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Borrar',
  bool destructive = true,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) {
      final colors = Theme.of(context).colorScheme;
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(backgroundColor: colors.error, foregroundColor: colors.onError)
                : null,
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return ok ?? false;
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Ejecuta [task] mostrando un diálogo de progreso que no se puede cerrar.
Future<T> runWithProgress<T>(BuildContext context, String message, Future<T> Function() task) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 24),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    ),
  );
  try {
    return await task();
  } finally {
    navigator.pop();
  }
}
