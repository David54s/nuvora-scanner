import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../core/imaging/image_pipeline.dart';
import '../../../core/imaging/page_filter.dart';
import '../../../core/imaging/paper_size.dart';
import '../../../core/imaging/quad.dart';
import '../../../core/providers.dart';
import '../../../core/ui/format.dart';
import '../../document/application/page_service.dart';

/// La foto que se está revisando, aún sin guardar.
class Capture {
  const Capture({
    required this.id,
    required this.path,
    this.width = 0,
    this.height = 0,
    this.quad = Quad.full,
    this.detectedQuad,
    this.filter = PageFilter.enhanced,
    this.rotation = 0,
    this.paper = PaperSize.auto,
    this.error,
    this.fromGallery = false,
  });

  final String id;

  /// Imagen normalizada en el directorio de capturas.
  final String path;
  final int width;
  final int height;
  final Quad quad;

  /// Resultado de la detección automática; null mientras se procesa o si no
  /// se encontró el documento.
  final Quad? detectedQuad;
  final PageFilter filter;
  final int rotation;
  final PaperSize paper;
  final String? error;

  /// Viene de la galería (descartarla no implica tomar otra foto).
  final bool fromGallery;

  /// Ya se normalizó y se pasó por el detector.
  bool get ready => width > 0;

  ImageSize get size => (width: width, height: height);

  Capture copyWith({
    int? width,
    int? height,
    Quad? quad,
    Quad? detectedQuad,
    PageFilter? filter,
    int? rotation,
    PaperSize? paper,
    String? error,
  }) => Capture(
    id: id,
    path: path,
    width: width ?? this.width,
    height: height ?? this.height,
    quad: quad ?? this.quad,
    detectedQuad: detectedQuad ?? this.detectedQuad,
    filter: filter ?? this.filter,
    rotation: rotation ?? this.rotation,
    paper: paper ?? this.paper,
    error: error ?? this.error,
    fromGallery: fromGallery,
  );

  PageDraft toDraft() => PageDraft(imagePath: path, quad: quad, filter: filter, rotation: rotation, paper: paper);
}

class ScanState {
  const ScanState({
    this.documentId,
    this.folderId,
    this.current,
    this.pagesAdded = 0,
    this.lastThumbPath,
    this.importQueue = const [],
    this.defaultFilter = PageFilter.enhanced,
    this.defaultPaper = PaperSize.auto,
  });

  /// Documento al que se agregan las páginas. Si la sesión empezó sin
  /// documento, se crea al agregar la primera página.
  final int? documentId;

  /// Carpeta del documento nuevo.
  final int? folderId;

  /// Foto en revisión.
  final Capture? current;

  /// Páginas agregadas en esta sesión.
  final int pagesAdded;

  /// Miniatura (ruta relativa) de la última página agregada.
  final String? lastThumbPath;

  /// Imágenes de la galería que faltan por revisar.
  final List<String> importQueue;
  final PageFilter defaultFilter;
  final PaperSize defaultPaper;

  ScanState copyWith({
    int? documentId,
    Capture? current,
    bool clearCurrent = false,
    int? pagesAdded,
    String? lastThumbPath,
    List<String>? importQueue,
    PageFilter? defaultFilter,
    PaperSize? defaultPaper,
  }) => ScanState(
    documentId: documentId ?? this.documentId,
    folderId: folderId,
    current: clearCurrent ? null : (current ?? this.current),
    pagesAdded: pagesAdded ?? this.pagesAdded,
    lastThumbPath: lastThumbPath ?? this.lastThumbPath,
    importQueue: importQueue ?? this.importQueue,
    defaultFilter: defaultFilter ?? this.defaultFilter,
    defaultPaper: defaultPaper ?? this.defaultPaper,
  );
}

const defaultFilterSetting = 'default_filter';
const defaultPaperSetting = 'default_paper';

final scanSessionProvider = NotifierProvider<ScanSession, ScanState>(ScanSession.new);

/// Flujo de una foto a la vez: capturar → revisar bordes y vista previa →
/// agregar (se guarda en el acto) → siguiente foto.
class ScanSession extends Notifier<ScanState> {
  static const _uuid = Uuid();

  @override
  ScanState build() => const ScanState();

  /// Empieza una sesión nueva, descartando la foto en revisión de la anterior.
  Future<void> start({int? documentId, int? folderId}) async {
    await discardCurrent();
    final repo = ref.read(libraryRepositoryProvider);
    final filter = PageFilter.values.asNameMap()[await repo.getSetting(defaultFilterSetting)] ?? PageFilter.enhanced;
    final paper = PaperSize.values.asNameMap()[await repo.getSetting(defaultPaperSetting)] ?? PaperSize.auto;
    state = ScanState(documentId: documentId, folderId: folderId, defaultFilter: filter, defaultPaper: paper);
  }

  /// Pone [srcPath] en revisión: la normaliza y detecta el documento en
  /// segundo plano. Si [deleteSource] es verdadero borra [srcPath] al terminar
  /// (fotos temporales de la cámara o copias del selector de fotos).
  Future<void> capture(String srcPath, {bool deleteSource = false, bool fromGallery = false}) async {
    await discardCurrent();
    final files = ref.read(fileStoreProvider);
    await files.captureDir.create(recursive: true);
    final id = _uuid.v4();
    final dst = p.join(files.captureDir.path, '$id.jpg');
    state = state.copyWith(
      current: Capture(
        id: id,
        path: dst,
        filter: state.defaultFilter,
        paper: state.defaultPaper,
        fromGallery: fromGallery,
      ),
    );
    try {
      final (size, det) = await ref.read(imagePipelineProvider).ingestAndDetect(srcPath, dst);
      _updateCurrent(
        id,
        (c) => c.copyWith(
          width: size.width,
          height: size.height,
          quad: det.quad,
          detectedQuad: det.found ? det.quad : null,
        ),
      );
    } catch (_) {
      _updateCurrent(id, (c) => c.copyWith(error: 'No se pudo procesar la imagen'));
    } finally {
      if (deleteSource) {
        final f = File(srcPath);
        if (await f.exists()) await f.delete();
      }
    }
  }

  void setQuad(Quad quad) => _edit((c) => c.copyWith(quad: quad));

  void setFilter(PageFilter filter) => _edit((c) => c.copyWith(filter: filter));

  void setPaper(PaperSize paper) => _edit((c) => c.copyWith(paper: paper));

  void rotate(int delta) => _edit((c) => c.copyWith(rotation: (c.rotation + delta) % 360));

  /// Guarda la foto en revisión como página del documento (creándolo si hace
  /// falta). Devuelve el id del documento.
  Future<int> commitCurrent() async {
    final c = state.current;
    if (c == null || !c.ready) throw StateError('No hay una foto lista para agregar');
    final repo = ref.read(libraryRepositoryProvider);
    final docId = await ref
        .read(pageServiceProvider)
        .saveScan(
          [c.toDraft()],
          documentId: state.documentId,
          folderId: state.folderId,
          title: defaultScanTitle(DateTime.now()),
        );
    final pages = await repo.pagesOf(docId);
    await repo.setSetting(defaultFilterSetting, c.filter.name);
    await repo.setSetting(defaultPaperSetting, c.paper.name);
    await _deleteFile(c.path);
    state = state.copyWith(
      documentId: docId,
      clearCurrent: true,
      pagesAdded: state.pagesAdded + 1,
      lastThumbPath: pages.lastOrNull?.thumbPath,
      defaultFilter: c.filter,
      defaultPaper: c.paper,
    );
    return docId;
  }

  /// Descarta la foto en revisión ("Repetir").
  Future<void> discardCurrent() async {
    final c = state.current;
    if (c == null) return;
    state = state.copyWith(clearCurrent: true);
    await _deleteFile(c.path);
  }

  /// Encola imágenes de la galería para revisarlas de a una.
  void enqueueImports(List<String> paths) => state = state.copyWith(importQueue: [...state.importQueue, ...paths]);

  /// Pone en revisión la siguiente imagen de la cola. Devuelve false si no
  /// quedaban.
  Future<bool> nextImport() async {
    if (state.importQueue.isEmpty) return false;
    final next = state.importQueue.first;
    state = state.copyWith(importQueue: state.importQueue.sublist(1));
    // No se espera: la pantalla de revisión muestra el progreso.
    unawaited(capture(next, deleteSource: true, fromGallery: true));
    return true;
  }

  Future<void> clearImports() async {
    final pending = state.importQueue;
    state = state.copyWith(importQueue: const []);
    for (final path in pending) {
      await _deleteFile(path);
    }
  }

  void _edit(Capture Function(Capture c) f) {
    final c = state.current;
    if (c != null && c.ready) state = state.copyWith(current: f(c));
  }

  /// Aplica [f] solo si la foto en revisión sigue siendo [id] (el usuario
  /// pudo descartarla mientras se procesaba).
  void _updateCurrent(String id, Capture Function(Capture c) f) {
    final c = state.current;
    if (c != null && c.id == id) state = state.copyWith(current: f(c));
  }

  Future<void> _deleteFile(String path) async {
    final f = File(path);
    if (await f.exists()) await f.delete();
  }
}
