import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../crop/presentation/review_screen.dart';
import '../application/scan_session.dart';

/// Abre el flujo de escaneo: cámara o galería → revisión de cada foto →
/// agregar. Devuelve el id del documento, o null si no se agregó ninguna página.
Future<int?> startScan(
  BuildContext context,
  WidgetRef ref, {
  int? documentId,
  int? folderId,
  bool fromGallery = false,
}) async {
  final session = ref.read(scanSessionProvider.notifier);
  await session.start(documentId: documentId, folderId: folderId);
  if (!context.mounted) return null;

  if (!fromGallery) return context.push<int>('/scan');

  final picked = await ImagePicker().pickMultiImage();
  if (picked.isEmpty || !context.mounted) return null;
  session.enqueueImports([for (final x in picked) x.path]);
  await reviewImports(context, ref);
  final state = ref.read(scanSessionProvider);
  return state.pagesAdded > 0 ? state.documentId : null;
}

/// Revisa de a una las imágenes encoladas en la sesión. Devuelve true si el
/// usuario eligió terminar.
Future<bool> reviewImports(BuildContext context, WidgetRef ref) async {
  final session = ref.read(scanSessionProvider.notifier);
  while (await session.nextImport()) {
    if (!context.mounted) return false;
    final outcome = await context.push<ReviewOutcome>('/review');
    if (outcome == ReviewOutcome.finished) {
      await session.clearImports();
      return true;
    }
  }
  return false;
}

/// Pregunta si escanear con la cámara o importar de la galería.
Future<int?> chooseAndStartScan(BuildContext context, WidgetRef ref, {int? documentId, int? folderId}) async {
  final fromGallery = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Cámara'),
            onTap: () => Navigator.pop(context, false),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Importar de la galería'),
            onTap: () => Navigator.pop(context, true),
          ),
        ],
      ),
    ),
  );
  if (fromGallery == null || !context.mounted) return null;
  return startScan(context, ref, documentId: documentId, folderId: folderId, fromGallery: fromGallery);
}
