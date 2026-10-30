import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/db/app_database.dart';
import '../../../core/imaging/page_filter.dart';
import '../../../core/imaging/paper_size.dart';
import '../../../core/providers.dart';
import '../../../core/ui/dialogs.dart';
import '../../crop/presentation/widgets/filter_selector.dart';
import '../../crop/presentation/widgets/paper_selector.dart';
import '../../library/application/library_providers.dart';

/// Vista de las páginas de un documento con edición de filtro, rotación y
/// recorte. Cada cambio vuelve a renderizar la página desde su original.
class PageEditorScreen extends ConsumerStatefulWidget {
  const PageEditorScreen({super.key, required this.documentId, required this.initialPageId});

  final int documentId;
  final int initialPageId;

  @override
  ConsumerState<PageEditorScreen> createState() => _PageEditorScreenState();
}

class _PageEditorScreenState extends ConsumerState<PageEditorScreen> {
  PageController? _controller;
  int _index = 0;

  /// Páginas que se están renderizando.
  final _busy = <int>{};

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _rerender(ScanPage page, {PageFilter? filter, int? rotation, PaperSize? paper}) async {
    setState(() => _busy.add(page.id));
    try {
      await ref.read(pageServiceProvider).rerender(page, filter: filter, rotation: rotation, paper: paper);
    } catch (e) {
      if (mounted) showSnack(context, 'No se pudo aplicar el cambio: $e');
    } finally {
      if (mounted) setState(() => _busy.remove(page.id));
    }
  }

  Future<void> _delete(ScanPage page, int total) async {
    final ok = await showConfirmDialog(
      context,
      title: '¿Borrar página?',
      message: total == 1 ? 'Es la única página: el documento quedará vacío.' : 'La página se borrará del documento.',
    );
    if (!ok) return;
    await ref.read(libraryRepositoryProvider).deletePage(page);
    if (total == 1 && mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final pagesAsync = ref.watch(pagesProvider(widget.documentId));
    final pages = pagesAsync.value;
    if (pages == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (pages.isEmpty) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('No hay páginas.')),
      );
    }

    if (_controller == null) {
      _index = pages.indexWhere((p) => p.id == widget.initialPageId).clamp(0, pages.length - 1);
      _controller = PageController(initialPage: _index);
    }
    final index = _index.clamp(0, pages.length - 1);
    final page = pages[index];
    final busy = _busy.contains(page.id);
    final files = ref.watch(fileStoreProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('Página ${index + 1} de ${pages.length}'),
        actions: [
          IconButton(
            tooltip: 'Borrar página',
            icon: const Icon(Icons.delete_outline),
            onPressed: busy ? null : () => _delete(page, pages.length),
          ),
        ],
        bottom: busy ? const PreferredSize(preferredSize: Size.fromHeight(4), child: LinearProgressIndicator()) : null,
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _controller,
              itemCount: pages.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) => InteractiveViewer(
                maxScale: 5,
                child: Center(
                  child: Image.file(
                    // La ruta incluye la revisión, así que un cambio carga la imagen nueva.
                    File(files.abs(pages[i].processedPath)),
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 64),
                  ),
                ),
              ),
            ),
          ),
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  PaperSelector(
                    selected: page.paper,
                    enabled: !busy,
                    onSelected: (p) {
                      if (p != page.paper) _rerender(page, paper: p);
                    },
                  ),
                  FilterSelector(
                    selected: page.filter,
                    enabled: !busy,
                    onSelected: (f) {
                      if (f != page.filter) _rerender(page, filter: f);
                    },
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _ToolButton(
                        icon: Icons.rotate_left,
                        label: 'Girar izq.',
                        onPressed: busy ? null : () => _rerender(page, rotation: page.rotation + 270),
                      ),
                      _ToolButton(
                        icon: Icons.rotate_right,
                        label: 'Girar der.',
                        onPressed: busy ? null : () => _rerender(page, rotation: page.rotation + 90),
                      ),
                      _ToolButton(
                        icon: Icons.crop,
                        label: 'Recortar',
                        onPressed: busy ? null : () => context.push('/page/${page.id}/crop'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.icon, required this.label, required this.onPressed});

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon), const SizedBox(height: 4), Text(label)]),
    );
  }
}
