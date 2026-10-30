import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/db/app_database.dart';
import '../../../core/imaging/quad.dart';
import '../../../core/providers.dart';
import '../../../core/ui/dialogs.dart';
import 'widgets/quad_editor.dart';

/// Vuelve a recortar una página ya guardada, partiendo de su original.
class PageCropScreen extends ConsumerStatefulWidget {
  const PageCropScreen({super.key, required this.pageId});

  final int pageId;

  @override
  ConsumerState<PageCropScreen> createState() => _PageCropScreenState();
}

class _PageCropScreenState extends ConsumerState<PageCropScreen> {
  ScanPage? _page;
  Size? _size;
  Quad? _quad;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final page = await ref.read(libraryRepositoryProvider).page(widget.pageId);
      if (page == null) throw StateError('La página ya no existe');
      final size = await _imageSize(ref.read(fileStoreProvider).abs(page.originalPath));
      if (!mounted) return;
      setState(() {
        _page = page;
        _size = size;
        _quad = page.quad;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  /// Lee solo la cabecera del JPEG para conocer su tamaño.
  static Future<Size> _imageSize(String path) async {
    final buffer = await ui.ImmutableBuffer.fromFilePath(path);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final size = Size(descriptor.width.toDouble(), descriptor.height.toDouble());
    descriptor.dispose();
    buffer.dispose();
    return size;
  }

  Future<void> _save() async {
    final page = _page!, quad = _quad!;
    if (quad == page.quad) {
      context.pop();
      return;
    }
    try {
      await runWithProgress(context, 'Recortando…', () => ref.read(pageServiceProvider).rerender(page, quad: quad));
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) showSnack(context, 'No se pudo recortar: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = _page, quad = _quad, size = _size;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recortar página'),
        actions: [
          if (quad != null)
            TextButton(onPressed: () => setState(() => _quad = Quad.full), child: const Text('Imagen completa')),
        ],
      ),
      body: _error != null
          ? Center(child: Text(_error!))
          : page == null || quad == null || size == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: QuadEditor(
                      image: FileImage(File(ref.read(fileStoreProvider).abs(page.originalPath))),
                      imageSize: size,
                      quad: quad,
                      onChanged: (q) => setState(() => _quad = q),
                    ),
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: quad.isConvex ? _save : null,
                        icon: const Icon(Icons.check),
                        label: const Text('Aplicar recorte'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
