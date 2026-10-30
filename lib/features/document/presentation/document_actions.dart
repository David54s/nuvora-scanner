import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/providers.dart';
import '../../../core/ui/dialogs.dart';

Future<void> renameDocument(BuildContext context, WidgetRef ref, Document doc) async {
  final title = await showTextInputDialog(context, title: 'Renombrar documento', initialValue: doc.title);
  if (title != null) await ref.read(libraryRepositoryProvider).renameDocument(doc.id, title);
}

Future<void> moveDocument(BuildContext context, WidgetRef ref, Document doc) async {
  final repo = ref.read(libraryRepositoryProvider);
  final folders = await repo.allFolders();
  if (!context.mounted) return;
  // Envuelto en un registro para distinguir "raíz" (null) de "cancelado".
  final target = await showModalBottomSheet<({int? id})>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const ListTile(title: Text('Mover a…')),
          ListTile(
            leading: const Icon(Icons.home_outlined),
            title: const Text('Inicio (sin carpeta)'),
            selected: doc.folderId == null,
            onTap: () => Navigator.pop(context, (id: null)),
          ),
          for (final f in folders)
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: Text(f.name),
              selected: doc.folderId == f.id,
              onTap: () => Navigator.pop(context, (id: f.id)),
            ),
        ],
      ),
    ),
  );
  if (target != null && target.id != doc.folderId) await repo.moveDocument(doc.id, target.id);
}

/// Devuelve true si se borró.
Future<bool> deleteDocument(BuildContext context, WidgetRef ref, Document doc) async {
  final ok = await showConfirmDialog(
    context,
    title: '¿Borrar documento?',
    message: '"${doc.title}" y todas sus páginas se borrarán de este dispositivo.',
  );
  if (ok) await ref.read(libraryRepositoryProvider).deleteDocument(doc.id);
  return ok;
}

Future<void> showDocumentOptions(BuildContext context, WidgetRef ref, Document doc) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(title: Text(doc.title, style: Theme.of(context).textTheme.titleMedium)),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Renombrar'),
            onTap: () => Navigator.pop(context, 'rename'),
          ),
          ListTile(
            leading: const Icon(Icons.drive_file_move_outlined),
            title: const Text('Mover a carpeta'),
            onTap: () => Navigator.pop(context, 'move'),
          ),
          ListTile(
            leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
            title: const Text('Borrar'),
            onTap: () => Navigator.pop(context, 'delete'),
          ),
        ],
      ),
    ),
  );
  if (!context.mounted) return;
  switch (action) {
    case 'rename':
      await renameDocument(context, ref, doc);
    case 'move':
      await moveDocument(context, ref, doc);
    case 'delete':
      await deleteDocument(context, ref, doc);
  }
}
