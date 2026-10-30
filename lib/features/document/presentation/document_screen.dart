import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/db/app_database.dart';
import '../../../core/providers.dart';
import '../../../core/ui/dialogs.dart';
import '../../../core/ui/format.dart';
import '../../capture/presentation/start_scan.dart';
import '../../export/share_service.dart';
import '../../library/application/library_providers.dart';
import 'document_actions.dart';

/// Páginas de un documento: reordenar, abrir, agregar, exportar y compartir.
class DocumentScreen extends ConsumerStatefulWidget {
  const DocumentScreen({super.key, required this.documentId});

  final int documentId;

  @override
  ConsumerState<DocumentScreen> createState() => _DocumentScreenState();
}

class _DocumentScreenState extends ConsumerState<DocumentScreen> {
  /// Orden mostrado tras arrastrar, hasta que la base emite el nuevo orden.
  List<ScanPage>? _optimistic;

  Future<void> _sharePdf(Document doc, List<ScanPage> pages) async {
    final share = ref.read(shareServiceProvider);
    try {
      final path = await runWithProgress(context, 'Generando PDF…', () => share.exportPdf(doc, pages));
      await share.sharePdfFile(path, doc.title);
    } catch (e) {
      if (mounted) showSnack(context, 'No se pudo generar el PDF: $e');
    }
  }

  Future<void> _reorder(List<ScanPage> pages, int oldIndex, int newIndex) async {
    final list = [...pages];
    list.insert(newIndex, list.removeAt(oldIndex));
    setState(() => _optimistic = list);
    await ref.read(libraryRepositoryProvider).reorderPages(widget.documentId, [for (final p in list) p.id]);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(pagesProvider(widget.documentId), (_, _) {
      if (_optimistic != null) setState(() => _optimistic = null);
    });
    final docAsync = ref.watch(documentProvider(widget.documentId));
    final pagesAsync = ref.watch(pagesProvider(widget.documentId));
    final doc = docAsync.value;
    final pages = _optimistic ?? pagesAsync.value ?? const <ScanPage>[];

    if (docAsync.hasValue && doc == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('El documento ya no existe.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: doc == null
            ? null
            : GestureDetector(onTap: () => renameDocument(context, ref, doc), child: Text(doc.title)),
        actions: [
          if (doc != null && pages.isNotEmpty)
            IconButton(
              tooltip: 'Compartir PDF',
              icon: const Icon(Icons.picture_as_pdf_outlined),
              onPressed: () => _sharePdf(doc, pages),
            ),
          if (doc != null)
            PopupMenuButton<String>(
              onSelected: (v) async {
                switch (v) {
                  case 'images':
                    await ref.read(shareServiceProvider).shareImages(doc, pages);
                  case 'rename':
                    await renameDocument(context, ref, doc);
                  case 'move':
                    await moveDocument(context, ref, doc);
                  case 'delete':
                    if (await deleteDocument(context, ref, doc) && context.mounted) context.pop();
                }
              },
              itemBuilder: (_) => [
                if (pages.isNotEmpty) const PopupMenuItem(value: 'images', child: Text('Compartir imágenes')),
                const PopupMenuItem(value: 'rename', child: Text('Renombrar')),
                const PopupMenuItem(value: 'move', child: Text('Mover a carpeta')),
                const PopupMenuItem(value: 'delete', child: Text('Borrar documento')),
              ],
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => chooseAndStartScan(context, ref, documentId: widget.documentId),
        icon: const Icon(Icons.add_a_photo_outlined),
        label: const Text('Agregar páginas'),
      ),
      body: !pagesAsync.hasValue
          ? const Center(child: CircularProgressIndicator())
          : pages.isEmpty
          ? const Center(child: Text('Este documento no tiene páginas.'))
          : ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
              buildDefaultDragHandles: false,
              itemCount: pages.length,
              onReorderItem: (o, n) => _reorder(pages, o, n),
              itemBuilder: (context, i) => _PageTile(
                key: ValueKey(pages[i].id),
                page: pages[i],
                index: i,
                onTap: () => context.push('/doc/${widget.documentId}/page/${pages[i].id}'),
              ),
            ),
    );
  }
}

class _PageTile extends ConsumerWidget {
  const _PageTile({super.key, required this.page, required this.index, required this.onTap});

  final ScanPage page;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final files = ref.watch(fileStoreProvider);
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 128,
          child: Row(
            children: [
              AspectRatio(
                aspectRatio: 0.75,
                child: ColoredBox(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Image.file(
                    File(files.abs(page.thumbPath)),
                    fit: BoxFit.contain,
                    cacheWidth: 240,
                    errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Página ${index + 1}', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text('${page.filter.label} · ${page.width}×${page.height}', style: theme.textTheme.bodySmall),
                    Text(formatDateTime(page.createdAt), style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              ReorderableDragStartListener(
                index: index,
                child: const Padding(padding: EdgeInsets.all(16), child: Icon(Icons.drag_handle)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
