import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/imaging/page_filter.dart';
import '../../../core/imaging/quad.dart';
import '../../../core/providers.dart';
import '../../crop/presentation/widgets/quad_editor.dart';
import '../application/id_scan_session.dart';

/// Ajuste de bordes y giro del lado actual de la [IdScanSession]. Recién
/// tomado devuelve `true` (aceptado) o `false` ("Repetir"); con [adjusting]
/// solo edita un lado ya tomado y se cierra con "Listo".
class IdSideReviewScreen extends ConsumerStatefulWidget {
  const IdSideReviewScreen({super.key, this.adjusting = false});

  final bool adjusting;

  @override
  ConsumerState<IdSideReviewScreen> createState() => _IdSideReviewScreenState();
}

class _IdSideReviewScreenState extends ConsumerState<IdSideReviewScreen> {
  Uint8List? _preview;
  int _previewRequest = 0;
  Timer? _debounce;
  (Quad, int)? _previewedFor;

  IdScanSession get _session => ref.read(idScanSessionProvider.notifier);

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  /// Miniatura del lado recortado y girado, para ver si quedó derecho.
  void _schedulePreview(IdSideDraft s) {
    if (_previewedFor == (s.quad, s.rotation)) return;
    _previewedFor = (s.quad, s.rotation);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () async {
      final request = ++_previewRequest;
      try {
        final bytes = await ref
            .read(imagePipelineProvider)
            .preview(
              _session.absolutePath(s),
              quad: s.quad,
              filter: PageFilter.original,
              rotation: s.rotation,
              sourceSize: (width: s.width, height: s.height),
              maxSide: 360,
            );
        if (mounted && request == _previewRequest) setState(() => _preview = bytes);
      } catch (_) {
        // Sin miniatura: no impide seguir.
      }
    });
  }

  Future<void> _retake() async {
    await _session.discardSide(ref.read(idScanSessionProvider).current);
    if (mounted) context.pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(idScanSessionProvider);
    final s = state.currentSide;
    final template = state.layout.template;
    final index = state.current;
    final last = state.nextMissing == null;
    if (s != null && s.ready && s.quad.isConvex) _schedulePreview(s);

    return PopScope(
      canPop: widget.adjusting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _retake();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(template.sides.length == 1 ? template.label : '${template.sides[index]} · ajustar bordes'),
        ),
        body: s == null ? const SizedBox.shrink() : _buildBody(s, last),
      ),
    );
  }

  Widget _buildBody(IdSideDraft s, bool last) {
    final theme = Theme.of(context);
    final index = ref.read(idScanSessionProvider).current;
    final Widget editor;
    if (s.error != null) {
      editor = Center(
        child: Text(s.error!, style: TextStyle(color: theme.colorScheme.error)),
      );
    } else if (!s.ready) {
      editor = const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [CircularProgressIndicator(), SizedBox(height: 12), Text('Buscando la tarjeta…')],
        ),
      );
    } else {
      editor = Padding(
        padding: const EdgeInsets.all(8),
        child: QuadEditor(
          image: FileImage(File(_session.absolutePath(s))),
          imageSize: Size(s.width.toDouble(), s.height.toDouble()),
          quad: s.quad,
          onChanged: (q) => _session.setQuad(index, q),
        ),
      );
    }

    return Column(
      children: [
        Expanded(child: editor),
        if (s.ready) ...[
          if (!s.quad.isConvex)
            Text('Las esquinas se cruzan; acomódalas para continuar.', style: TextStyle(color: theme.colorScheme.error))
          else if (s.detectedQuad == null && !s.stored)
            const Text('No se detectó la tarjeta: ajusta las esquinas a mano.'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                // Cómo quedará el lado (recortado y girado).
                SizedBox(
                  width: 120,
                  height: 80,
                  child: _preview == null
                      ? null
                      : DecoratedBox(
                          decoration: BoxDecoration(border: Border.all(color: theme.colorScheme.outlineVariant)),
                          child: Image.memory(_preview!, fit: BoxFit.contain, gaplessPlayback: true),
                        ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Girar a la izquierda',
                  icon: const Icon(Icons.rotate_left),
                  onPressed: () => _session.rotateSide(index, 270),
                ),
                IconButton(
                  tooltip: 'Girar a la derecha',
                  icon: const Icon(Icons.rotate_right),
                  onPressed: () => _session.rotateSide(index, 90),
                ),
                if (s.detectedQuad != null)
                  IconButton(
                    tooltip: 'Detección automática',
                    icon: const Icon(Icons.auto_fix_high),
                    onPressed: () => _session.setQuad(index, s.detectedQuad!),
                  ),
              ],
            ),
          ),
        ],
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(
              children: [
                if (!widget.adjusting) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _retake,
                      icon: const Icon(Icons.replay),
                      label: const Text('Repetir'),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: FilledButton.icon(
                    onPressed: s.ready && s.quad.isConvex ? () => context.pop(true) : null,
                    icon: Icon(widget.adjusting || last ? Icons.check : Icons.arrow_forward),
                    label: Text(widget.adjusting || last ? 'Listo' : 'Siguiente lado'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
