import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/imaging/paper_size.dart';
import '../../../core/imaging/quad.dart';
import '../../../core/providers.dart';
import '../../../core/ui/dialogs.dart';
import '../../capture/application/scan_session.dart';
import 'widgets/filter_selector.dart';
import 'widgets/paper_selector.dart';
import 'widgets/quad_editor.dart';

/// Cómo terminó la revisión de una foto.
enum ReviewOutcome {
  /// Se agregó la página; seguir escaneando.
  added,

  /// Se agregó la página y se termina el escaneo.
  finished,

  /// Se descartó la foto para tomar otra.
  retake,
}

/// Revisión de la foto actual de la [ScanSession] en dos pasos, como en los
/// escáneres comerciales: 1) ajustar los bordes, 2) ver cómo quedará con el
/// filtro y agregarla al documento. Devuelve un [ReviewOutcome] con `pop`.
class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  bool _previewStep = false;
  Uint8List? _preview;
  bool _rendering = false;
  int _previewRequest = 0;
  Timer? _debounce;

  ScanSession get _session => ref.read(scanSessionProvider.notifier);

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  /// Recalcula la vista previa con un pequeño retardo; solo vale la última.
  void _schedulePreview() {
    _debounce?.cancel();
    setState(() => _rendering = true);
    _debounce = Timer(const Duration(milliseconds: 150), _renderPreview);
  }

  Future<void> _renderPreview() async {
    final c = ref.read(scanSessionProvider).current;
    if (c == null || !c.ready) return;
    final request = ++_previewRequest;
    try {
      final bytes = await ref
          .read(imagePipelineProvider)
          .preview(c.path, quad: c.quad, filter: c.filter, rotation: c.rotation, sourceSize: c.size, paper: c.paper);
      if (!mounted || request != _previewRequest) return;
      setState(() {
        _preview = bytes;
        _rendering = false;
      });
    } catch (e) {
      if (!mounted || request != _previewRequest) return;
      setState(() => _rendering = false);
      showSnack(context, 'No se pudo generar la vista previa: $e');
    }
  }

  void _goToPreview() {
    setState(() {
      _previewStep = true;
      _preview = null;
    });
    _schedulePreview();
  }

  Future<void> _retake() async {
    await _session.discardCurrent();
    if (mounted) context.pop(ReviewOutcome.retake);
  }

  Future<void> _add({required bool finish}) async {
    try {
      await runWithProgress(context, 'Guardando página…', _session.commitCurrent);
      if (mounted) context.pop(finish ? ReviewOutcome.finished : ReviewOutcome.added);
    } catch (e) {
      if (mounted) showSnack(context, 'No se pudo guardar: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(scanSessionProvider);
    final c = state.current;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_previewStep) {
          setState(() => _previewStep = false);
        } else {
          _retake();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_previewStep ? 'Vista previa' : 'Ajustar bordes'),
          actions: [
            if (state.pagesAdded > 0)
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Text(state.pagesAdded == 1 ? '1 página agregada' : '${state.pagesAdded} páginas agregadas'),
                ),
              ),
          ],
        ),
        body: c == null
            ? const SizedBox.shrink()
            : _previewStep
            ? _buildPreviewStep(c, state)
            : _buildEdgesStep(c),
      ),
    );
  }

  // ---------- Paso 1: bordes ----------

  Widget _buildEdgesStep(Capture c) {
    final Widget body;
    if (c.error != null) {
      body = Center(
        child: Text(c.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      );
    } else if (!c.ready) {
      body = const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [CircularProgressIndicator(), SizedBox(height: 12), Text('Buscando el documento…')],
        ),
      );
    } else {
      body = Padding(
        padding: const EdgeInsets.all(8),
        child: QuadEditor(
          image: FileImage(File(c.path)),
          imageSize: Size(c.width.toDouble(), c.height.toDouble()),
          quad: c.quad,
          onChanged: _session.setQuad,
        ),
      );
    }
    final isFull = c.quad == Quad.full;
    return Column(
      children: [
        Expanded(child: body),
        if (c.ready) ...[
          if (!c.quad.isConvex)
            Text(
              'Las esquinas se cruzan; acomódalas para continuar.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            )
          else if (c.detectedQuad == null && isFull)
            const Text('No se detectó el documento: ajusta las esquinas a mano.'),
          TextButton.icon(
            onPressed: () => _session.setQuad(isFull ? (c.detectedQuad ?? Quad.full) : Quad.full),
            icon: Icon(isFull ? Icons.auto_fix_high : Icons.fullscreen),
            label: Text(isFull ? 'Detección automática' : 'Usar imagen completa'),
          ),
        ],
        _BottomButtons(
          secondary: OutlinedButton.icon(
            onPressed: _retake,
            icon: Icon(c.fromGallery ? Icons.close : Icons.replay),
            label: Text(c.fromGallery ? 'Descartar' : 'Repetir'),
          ),
          primary: FilledButton.icon(
            onPressed: c.ready && c.quad.isConvex ? _goToPreview : null,
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Siguiente'),
          ),
        ),
      ],
    );
  }

  // ---------- Paso 2: vista previa ----------

  Widget _buildPreviewStep(Capture c, ScanState state) {
    final remaining = state.importQueue.length;
    return Column(
      children: [
        Expanded(
          child: ColoredBox(
            color: Colors.black,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (_preview != null)
                  InteractiveViewer(maxScale: 4, child: Center(child: Image.memory(_preview!, gaplessPlayback: true))),
                if (_rendering) const CircularProgressIndicator(),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        PaperSelector(
          selected: c.paper,
          autoResolved: resolvePaper(PaperSize.auto, c.quad, c.width, c.height),
          onSelected: (p) {
            _session.setPaper(p);
            _schedulePreview();
          },
        ),
        if (c.paper == PaperSize.auto && touchesFrame(c.quad))
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'La hoja se sale de la foto: el tamaño automático solo se aplica si lo visible ya se parece a Carta u Oficio.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        FilterSelector(
          selected: c.filter,
          onSelected: (f) {
            _session.setFilter(f);
            _schedulePreview();
          },
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: 'Girar a la izquierda',
              icon: const Icon(Icons.rotate_left),
              onPressed: () {
                _session.rotate(270);
                _schedulePreview();
              },
            ),
            IconButton(
              tooltip: 'Girar a la derecha',
              icon: const Icon(Icons.rotate_right),
              onPressed: () {
                _session.rotate(90);
                _schedulePreview();
              },
            ),
            TextButton.icon(
              onPressed: () => setState(() => _previewStep = false),
              icon: const Icon(Icons.crop),
              label: const Text('Bordes'),
            ),
          ],
        ),
        _BottomButtons(
          secondary: OutlinedButton(
            onPressed: () => _add(finish: false),
            child: Text(remaining > 0 ? 'Agregar y siguiente ($remaining)' : 'Agregar y seguir'),
          ),
          primary: FilledButton.icon(
            onPressed: () => _add(finish: true),
            icon: const Icon(Icons.check),
            label: const Text('Agregar y terminar'),
          ),
        ),
      ],
    );
  }
}

class _BottomButtons extends StatelessWidget {
  const _BottomButtons({required this.secondary, required this.primary});

  final Widget secondary;
  final Widget primary;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            Expanded(child: secondary),
            const SizedBox(width: 12),
            Expanded(child: primary),
          ],
        ),
      ),
    );
  }
}
