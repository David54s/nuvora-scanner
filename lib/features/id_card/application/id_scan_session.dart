import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../core/imaging/id_layout.dart';
import '../../../core/imaging/paper_size.dart';
import '../../../core/imaging/quad.dart';
import '../../../core/providers.dart';
import '../../../core/ui/format.dart';
import '../../../core/ui/image_size.dart';

/// Fracción del ancho de la foto que ocupa el marco guía de la cámara.
const idGuideWidth = 0.85;

/// El marco guía de la cámara en coordenadas normalizadas de una foto de
/// [width]×[height]: tarjeta horizontal centrada. Es el recorte inicial si no
/// se detecta la tarjeta.
Quad idGuideQuad(IdTemplate t, int width, int height) {
  final hw = idGuideWidth / 2;
  final hh = (idGuideWidth * width / t.aspect / height / 2).clamp(0.05, 0.5);
  return Quad(Pt(0.5 - hw, 0.5 - hh), Pt(0.5 + hw, 0.5 - hh), Pt(0.5 + hw, 0.5 + hh), Pt(0.5 - hw, 0.5 + hh));
}

/// Un lado de la identificación en la sesión.
class IdSideDraft {
  const IdSideDraft({
    required this.id,
    required this.path,
    this.stored = false,
    this.width = 0,
    this.height = 0,
    this.quad = Quad.full,
    this.detectedQuad,
    this.rotation = 0,
    this.error,
  });

  /// Distingue capturas para descartar resultados de una foto ya reemplazada.
  final String id;

  /// Foto de la sesión (absoluta) o, si [stored], la ya guardada en la
  /// página (relativa al directorio de la app).
  final String path;
  final bool stored;
  final int width;
  final int height;
  final Quad quad;
  final Quad? detectedQuad;
  final int rotation;
  final String? error;

  /// Ya se normalizó y se pasó por el detector.
  bool get ready => width > 0 && error == null;

  IdSideDraft copyWith({int? width, int? height, Quad? quad, Quad? detectedQuad, int? rotation, String? error}) =>
      IdSideDraft(
        id: id,
        path: path,
        stored: stored,
        width: width ?? this.width,
        height: height ?? this.height,
        quad: quad ?? this.quad,
        detectedQuad: detectedQuad ?? this.detectedQuad,
        rotation: rotation ?? this.rotation,
        error: error ?? this.error,
      );

  IdSide toSide() => IdSide(originalPath: path, quad: quad, rotation: rotation);
}

class IdScanState {
  const IdScanState({required this.layout, this.sides = const [], this.current = 0, this.folderId, this.pageId});

  final IdLayout layout;

  /// Uno por lado de la plantilla; null = falta tomarlo.
  final List<IdSideDraft?> sides;

  /// Lado que se está tomando o revisando.
  final int current;

  /// Carpeta del documento nuevo.
  final int? folderId;

  /// Página que se está editando (null = identificación nueva).
  final int? pageId;

  bool get editing => pageId != null;

  /// Primer lado que falta, o null si están todos.
  int? get nextMissing {
    final i = sides.indexWhere((s) => s == null);
    return i < 0 ? null : i;
  }

  bool get complete => sides.isNotEmpty && sides.every((s) => s != null && s.ready);

  IdSideDraft? get currentSide => current < sides.length ? sides[current] : null;

  IdScanState copyWith({IdLayout? layout, List<IdSideDraft?>? sides, int? current}) => IdScanState(
    layout: layout ?? this.layout,
    sides: sides ?? this.sides,
    current: current ?? this.current,
    folderId: folderId,
    pageId: pageId,
  );
}

/// Último acomodo usado, para la siguiente identificación.
const idLayoutSetting = 'id_layout';

final idScanSessionProvider = NotifierProvider<IdScanSession, IdScanState>(IdScanSession.new);

/// Escaneo de una identificación: se toma cada lado (con revisión de bordes),
/// se acomodan en la hoja y se guardan como una página. También edita una
/// página de identificación ya guardada.
class IdScanSession extends Notifier<IdScanState> {
  static const _uuid = Uuid();

  /// Respaldo de los lados que se están volviendo a tomar.
  final _retaking = <int, IdSideDraft>{};

  @override
  IdScanState build() => const IdScanState(layout: IdLayout(template: IdTemplate.ine));

  /// Empieza una identificación nueva con el último acomodo usado.
  Future<void> start(IdTemplate template, {int? folderId}) async {
    await discard();
    final saved = await ref.read(libraryRepositoryProvider).getSetting(idLayoutSetting);
    var layout = IdLayout(template: template);
    if (saved != null) {
      try {
        layout = IdLayout.fromJson(jsonDecode(saved) as Map<String, dynamic>).copyWith(template: template);
      } on FormatException {
        // Ajuste corrupto: se usa el acomodo por defecto.
      }
    }
    state = IdScanState(layout: layout, sides: List.filled(template.sides.length, null), folderId: folderId);
  }

  /// Carga una página de identificación ya guardada para editarla.
  Future<void> startEditing(int pageId) async {
    await discard();
    final page = await ref.read(libraryRepositoryProvider).page(pageId);
    final comp = page?.composition;
    if (page == null || comp == null) throw StateError('La página ya no existe');
    final files = ref.read(fileStoreProvider);
    final sides = <IdSideDraft>[];
    for (final s in comp.sides) {
      final size = await imageFileSize(files.abs(s.originalPath));
      sides.add(
        IdSideDraft(
          id: _uuid.v4(),
          path: s.originalPath,
          stored: true,
          width: size.width.round(),
          height: size.height.round(),
          quad: s.quad,
          rotation: s.rotation,
        ),
      );
    }
    state = IdScanState(layout: comp.layout, sides: sides, pageId: page.id);
  }

  /// Ruta absoluta de la foto de un lado.
  String absolutePath(IdSideDraft s) => s.stored ? ref.read(fileStoreProvider).abs(s.path) : s.path;

  /// Pone [srcPath] como el lado que falta (o [current] si se está
  /// repitiendo), lo normaliza y busca la tarjeta en segundo plano.
  Future<void> captureSide(String srcPath, {bool deleteSource = false}) async {
    final index = state.nextMissing ?? state.current;
    await _deleteTemp(state.sides[index]);
    final files = ref.read(fileStoreProvider);
    await files.captureDir.create(recursive: true);
    final id = _uuid.v4();
    final dst = p.join(files.captureDir.path, 'id_$id.jpg');
    _setSide(index, IdSideDraft(id: id, path: dst));
    state = state.copyWith(current: index);
    try {
      final (size, det) = await ref.read(imagePipelineProvider).ingestAndDetect(srcPath, dst);
      final template = state.layout.template;
      final quad = det.found ? det.quad : idGuideQuad(template, size.width, size.height);
      // Tarjeta en vertical en la foto: se gira para dejarla horizontal.
      final portrait = estimateAspect(quad, size.width, size.height) < 1;
      _updateSide(
        id,
        (s) => s.copyWith(
          width: size.width,
          height: size.height,
          quad: quad,
          detectedQuad: det.found ? det.quad : null,
          rotation: portrait == (template.aspect > 1) ? 90 : 0,
        ),
      );
    } catch (_) {
      _updateSide(id, (s) => s.copyWith(error: 'No se pudo procesar la imagen'));
    } finally {
      if (deleteSource) {
        final f = File(srcPath);
        if (await f.exists()) await f.delete();
      }
    }
  }

  void select(int index) => state = state.copyWith(current: index);

  void setQuad(int index, Quad quad) => _editSide(index, (s) => s.copyWith(quad: quad));

  void rotateSide(int index, int delta) => _editSide(index, (s) => s.copyWith(rotation: (s.rotation + delta) % 360));

  void setLayout(IdLayout layout) => state = state.copyWith(layout: layout);

  /// Descarta la foto del lado [index] para volver a tomarla ("Repetir").
  Future<void> discardSide(int index) async {
    final s = state.sides[index];
    _setSide(index, null);
    await _deleteTemp(s);
  }

  /// Quita el lado [index] para tomarlo de nuevo, guardando un respaldo por
  /// si se cancela ([cancelRetake]).
  void beginRetake(int index) {
    final s = state.sides[index];
    if (s != null && !_retaking.containsKey(index)) _retaking[index] = s;
    _setSide(index, null);
    state = state.copyWith(current: index);
  }

  /// Termina las repeticiones: restaura los lados que quedaron sin foto y
  /// borra las fotos reemplazadas.
  Future<void> endRetake() async {
    final backups = Map.of(_retaking);
    _retaking.clear();
    for (final MapEntry(key: i, value: old) in backups.entries) {
      if (state.sides[i] == null) {
        _setSide(i, old);
      } else {
        await _deleteTemp(old);
      }
    }
  }

  /// Hoja compuesta como JPEG en memoria.
  Future<Uint8List> preview({int maxSide = 1280}) {
    final sides = [for (final s in state.sides) s!.toSide().copyWith(originalPath: absolutePath(s))];
    return ref.read(imagePipelineProvider).previewIdCard(sides, state.layout, maxSide: maxSide);
  }

  /// Guarda la identificación nueva como documento (o los cambios de la
  /// página editada). Devuelve el id del documento.
  Future<int> save() async {
    if (!state.complete) throw StateError('Faltan lados por tomar');
    final repo = ref.read(libraryRepositoryProvider);
    final service = ref.read(pageServiceProvider);
    final sides = [for (final s in state.sides) s!.toSide()];
    final int docId;
    if (state.editing) {
      final page = await repo.page(state.pageId!);
      if (page == null) throw StateError('La página ya no existe');
      await service.recomposeIdCard(page, IdComposition(layout: state.layout, sides: sides));
      docId = page.documentId;
    } else {
      final t = state.layout.template;
      docId = await service.saveIdCard(
        sides,
        state.layout,
        folderId: state.folderId,
        title: '${t.shortLabel} ${titleDate(DateTime.now())}',
      );
    }
    await repo.setSetting(idLayoutSetting, jsonEncode(state.layout.toJson()));
    return docId;
  }

  /// Borra las fotos temporales de la sesión (las guardadas en páginas se
  /// conservan).
  Future<void> discard() async {
    final old = [...state.sides, ..._retaking.values];
    _retaking.clear();
    state = IdScanState(layout: state.layout);
    for (final s in old) {
      await _deleteTemp(s);
    }
  }

  void _setSide(int index, IdSideDraft? side) {
    final sides = [...state.sides];
    sides[index] = side;
    state = state.copyWith(sides: sides);
  }

  void _editSide(int index, IdSideDraft Function(IdSideDraft s) f) {
    final s = state.sides[index];
    if (s != null && s.ready) _setSide(index, f(s));
  }

  /// Aplica [f] solo si el lado sigue siendo la captura [id].
  void _updateSide(String id, IdSideDraft Function(IdSideDraft s) f) {
    final i = state.sides.indexWhere((s) => s?.id == id);
    if (i >= 0) _setSide(i, f(state.sides[i]!));
  }

  Future<void> _deleteTemp(IdSideDraft? s) async {
    if (s == null || s.stored) return;
    final f = File(s.path);
    if (await f.exists()) await f.delete();
  }
}
