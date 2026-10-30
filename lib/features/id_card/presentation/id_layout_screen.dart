import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/imaging/id_layout.dart';
import '../../../core/imaging/paper_size.dart';
import '../../../core/ui/dialogs.dart';
import '../../crop/presentation/widgets/filter_selector.dart';
import '../application/id_scan_session.dart';

/// Menú de la identificación: vista previa de la hoja y opciones de acomodo,
/// tamaño, orden, papel y filtro. Sin [pageId] guarda una identificación
/// nueva (devuelve el id del documento con `pop`); con [pageId] edita esa
/// página.
class IdLayoutScreen extends ConsumerStatefulWidget {
  const IdLayoutScreen({super.key, this.pageId});

  final int? pageId;

  @override
  ConsumerState<IdLayoutScreen> createState() => _IdLayoutScreenState();
}

class _IdLayoutScreenState extends ConsumerState<IdLayoutScreen> {
  Uint8List? _preview;
  bool _rendering = false;
  int _previewRequest = 0;
  Timer? _debounce;
  String? _loadError;
  bool _loaded = false;
  bool _dirty = false;

  IdScanSession get _session => ref.read(idScanSessionProvider.notifier);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      if (widget.pageId != null) await _session.startEditing(widget.pageId!);
      if (!mounted) return;
      setState(() => _loaded = true);
      // Cada cambio de acomodo o de un lado vuelve a componer la vista previa.
      ref.listenManual(idScanSessionProvider, (prev, next) {
        if (prev?.layout != next.layout || prev?.sides != next.sides) {
          _dirty = true;
          _schedulePreview();
        }
      });
      _schedulePreview();
    } catch (e) {
      if (mounted) setState(() => _loadError = '$e');
    }
  }

  void _schedulePreview() {
    _debounce?.cancel();
    if (!ref.read(idScanSessionProvider).complete) return;
    setState(() => _rendering = true);
    _debounce = Timer(const Duration(milliseconds: 150), _renderPreview);
  }

  Future<void> _renderPreview() async {
    final request = ++_previewRequest;
    try {
      final bytes = await _session.preview();
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

  void _setLayout(IdLayout Function(IdLayout l) f) => _session.setLayout(f(ref.read(idScanSessionProvider).layout));

  Future<void> _save() async {
    try {
      final docId = await runWithProgress(context, 'Guardando identificación…', _session.save);
      if (!mounted) return;
      if (widget.pageId != null) await _session.discard();
      if (mounted) context.pop(docId);
    } catch (e) {
      if (mounted) showSnack(context, 'No se pudo guardar: $e');
    }
  }

  Future<void> _leave() async {
    final editing = widget.pageId != null;
    if (_dirty || !editing) {
      final ok = await showConfirmDialog(
        context,
        title: editing ? '¿Descartar los cambios?' : '¿Descartar la identificación?',
        message: editing ? 'La página se quedará como estaba.' : 'Se perderán las fotos tomadas.',
        confirmLabel: 'Descartar',
      );
      if (!ok) return;
    }
    if (editing) await _session.discard();
    if (mounted) context.pop();
  }

  Future<void> _sideActions(int index) async {
    final template = ref.read(idScanSessionProvider).layout.template;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(template.sides[index], style: Theme.of(context).textTheme.titleMedium)),
            ListTile(
              leading: const Icon(Icons.crop_rotate),
              title: const Text('Ajustar bordes y giro'),
              onTap: () => Navigator.pop(context, 'adjust'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Volver a tomar'),
              onTap: () => Navigator.pop(context, 'retake'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'adjust') {
      _session.select(index);
      await context.push('/id/review?adjust=1');
    } else {
      _session.beginRetake(index);
      await context.push<bool>('/id/capture');
      await _session.endRetake();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(idScanSessionProvider);
    final layout = state.layout;
    final template = layout.template;
    final twoSided = template.sides.length > 1;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(template.label),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.icon(
                onPressed: _loaded && state.complete ? _save : null,
                icon: const Icon(Icons.check),
                label: const Text('Guardar'),
              ),
            ),
          ],
        ),
        body: _loadError != null
            ? Center(child: Text('No se pudo abrir la identificación:\n$_loadError', textAlign: TextAlign.center))
            : !_loaded
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Expanded(child: _buildPreview()),
                  _SidesRow(state: state, session: _session, onTap: _sideActions),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.38),
                    child: SingleChildScrollView(
                      child: SafeArea(
                        top: false,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (twoSided)
                              _OptionRow<IdTemplate>(
                                label: 'Tipo',
                                values: [
                                  for (final t in IdTemplate.values)
                                    if (t.sides.length == template.sides.length) t,
                                ],
                                selected: template,
                                labelOf: (t) => t.label,
                                onSelected: (t) => _setLayout((l) => l.copyWith(template: t)),
                              ),
                            if (twoSided)
                              _OptionRow<IdArrangement>(
                                label: 'Acomodo',
                                values: IdArrangement.values,
                                selected: layout.arrangement,
                                labelOf: (a) => a.label,
                                onSelected: (a) => _setLayout((l) => l.copyWith(arrangement: a)),
                                trailing: ActionChip(
                                  avatar: const Icon(Icons.swap_vert, size: 18),
                                  label: const Text('Intercambiar'),
                                  onPressed: () => _setLayout((l) => l.copyWith(swapped: !l.swapped)),
                                ),
                              ),
                            _OptionRow<IdAnchor>(
                              label: 'Posición',
                              values: IdAnchor.values,
                              selected: layout.anchor,
                              labelOf: (a) => a.label,
                              onSelected: (a) => _setLayout((l) => l.copyWith(anchor: a)),
                            ),
                            _OptionRow<IdScale>(
                              label: 'Tamaño',
                              values: IdScale.values,
                              selected: layout.scale,
                              labelOf: (s) => s.label,
                              onSelected: (s) => _setLayout((l) => l.copyWith(scale: s)),
                            ),
                            _OptionRow<PaperSize>(
                              label: 'Papel',
                              values: PaperSize.physical,
                              selected: layout.paper,
                              labelOf: (p) => p.label,
                              onSelected: (p) => _setLayout((l) => l.copyWith(paper: p)),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(left: 16, top: 4),
                              child: Text('Filtro', style: Theme.of(context).textTheme.labelLarge),
                            ),
                            FilterSelector(
                              selected: layout.filter,
                              onSelected: (f) => _setLayout((l) => l.copyWith(filter: f)),
                            ),
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildPreview() {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (_preview != null)
            InteractiveViewer(
              maxScale: 4,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: DecoratedBox(
                    decoration: const BoxDecoration(boxShadow: [BoxShadow(blurRadius: 8, color: Colors.black26)]),
                    child: Image.memory(_preview!, gaplessPlayback: true),
                  ),
                ),
              ),
            ),
          if (_rendering) const CircularProgressIndicator(),
        ],
      ),
    );
  }
}

/// Miniaturas de los lados; tocarlas abre sus acciones.
class _SidesRow extends StatelessWidget {
  const _SidesRow({required this.state, required this.session, required this.onTap});

  final IdScanState state;
  final IdScanSession session;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final template = state.layout.template;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          for (final (i, s) in state.sides.indexed)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => onTap(i),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: SizedBox(
                          width: 48,
                          height: 36,
                          child: s == null
                              ? const Icon(Icons.photo_camera_outlined)
                              : Image.file(File(session.absolutePath(s)), fit: BoxFit.cover, cacheWidth: 120),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(template.sides[i]),
                      const Icon(Icons.more_vert, size: 18),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Etiqueta y chips de una opción.
class _OptionRow<T> extends StatelessWidget {
  const _OptionRow({
    required this.label,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
    this.trailing,
  });

  final String label;
  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onSelected;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(label, style: Theme.of(context).textTheme.labelLarge),
            ),
          ),
          for (final v in values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(label: Text(labelOf(v)), selected: v == selected, onSelected: (_) => onSelected(v)),
            ),
          ?trailing,
        ],
      ),
    );
  }
}
