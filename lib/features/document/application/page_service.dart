import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../../../core/imaging/id_layout.dart';
import '../../../core/imaging/image_pipeline.dart';
import '../../../core/imaging/page_filter.dart';
import '../../../core/imaging/paper_size.dart';
import '../../../core/imaging/quad.dart';
import '../../../core/storage/file_store.dart';
import '../../library/data/library_repository.dart';

/// Una página por guardar: imagen ya normalizada (con EXIF aplicado) y los
/// ajustes elegidos en la pantalla de recorte.
class PageDraft {
  const PageDraft({
    required this.imagePath,
    required this.quad,
    required this.filter,
    this.rotation = 0,
    this.paper = PaperSize.auto,
  });

  final String imagePath;
  final Quad quad;
  final PageFilter filter;
  final int rotation;
  final PaperSize paper;
}

/// Orquesta archivos + pipeline de imagen + base de datos para crear y editar
/// páginas. Las páginas se renderizan de una en una para limitar la memoria.
class PageService {
  PageService(this._repo, this._files, this._pipeline);

  final LibraryRepository _repo;
  final FileStore _files;
  final ImagePipeline _pipeline;
  static const _uuid = Uuid();

  /// Renderiza [drafts] y los guarda en un documento nuevo, o al final de
  /// [documentId] si se indica. Devuelve el id del documento.
  Future<int> saveScan(
    List<PageDraft> drafts, {
    int? documentId,
    int? folderId,
    required String title,
    void Function(int done, int total)? onProgress,
  }) async {
    final created = <NewPage>[];
    try {
      for (final (i, d) in drafts.indexed) {
        onProgress?.call(i, drafts.length);
        created.add(await _createPage(d));
      }
      onProgress?.call(drafts.length, drafts.length);
      if (documentId != null) {
        await _repo.appendPages(documentId, created);
        return documentId;
      }
      return await _repo.createDocument(title: title, folderId: folderId, pages: created);
    } catch (_) {
      for (final p in created) {
        await _files.deletePageDir(p.uuid);
      }
      rethrow;
    }
  }

  Future<NewPage> _createPage(PageDraft d) async {
    final uuid = _uuid.v4();
    await _files.ensurePageDir(uuid);
    final originalRel = _files.originalRel(uuid);
    final processedRel = _files.processedRel(uuid, 0);
    final thumbRel = _files.thumbRel(uuid, 0);
    final ImageSize size;
    try {
      await File(d.imagePath).copy(_files.abs(originalRel));
      size = await _pipeline.render(
        RenderRequest(
          originalPath: _files.abs(originalRel),
          quad: d.quad,
          filter: d.filter,
          rotation: d.rotation,
          paper: d.paper,
          processedPath: _files.abs(processedRel),
          thumbPath: _files.abs(thumbRel),
        ),
      );
    } catch (_) {
      await _files.deletePageDir(uuid);
      rethrow;
    }
    return NewPage(
      uuid: uuid,
      originalPath: originalRel,
      processedPath: processedRel,
      thumbPath: thumbRel,
      quad: d.quad,
      filter: d.filter,
      rotation: d.rotation,
      width: size.width,
      height: size.height,
      paper: d.paper,
    );
  }

  /// Guarda una identificación como documento nuevo de una página (o al
  /// final de [documentId]). Las rutas de [sides] son las fotos de la sesión
  /// (absolutas); se copian a la carpeta de la página. Devuelve el id del
  /// documento.
  Future<int> saveIdCard(
    List<IdSide> sides,
    IdLayout layout, {
    int? documentId,
    int? folderId,
    required String title,
  }) async {
    final uuid = _uuid.v4();
    await _files.ensurePageDir(uuid);
    try {
      final stored = await _storeSides(uuid, sides, revision: 0);
      final composition = IdComposition(layout: layout, sides: stored);
      final processedRel = _files.processedRel(uuid, 0);
      final thumbRel = _files.thumbRel(uuid, 0);
      final size = await _pipeline.renderIdCard(
        IdRenderRequest(
          sides: _absolute(stored),
          layout: layout,
          processedPath: _files.abs(processedRel),
          thumbPath: _files.abs(thumbRel),
        ),
      );
      final page = NewPage(
        uuid: uuid,
        originalPath: stored.first.originalPath,
        processedPath: processedRel,
        thumbPath: thumbRel,
        quad: stored.first.quad,
        filter: layout.filter,
        rotation: 0,
        width: size.width,
        height: size.height,
        paper: layout.paper,
        composition: composition,
      );
      if (documentId != null) {
        await _repo.appendPages(documentId, [page]);
        return documentId;
      }
      return await _repo.createDocument(title: title, folderId: folderId, pages: [page]);
    } catch (_) {
      await _files.deletePageDir(uuid);
      rethrow;
    }
  }

  /// Vuelve a componer una página de identificación con [composition]. Los
  /// lados con ruta absoluta son fotos nuevas (se volvió a tomar ese lado) y
  /// se copian a la carpeta de la página; los demás se reutilizan.
  Future<void> recomposeIdCard(ScanPage page, IdComposition composition, {int? rotation}) async {
    final old = page.composition;
    if (old == null) throw ArgumentError('La página ${page.id} no es una identificación');
    final rev = page.revision + 1;
    final r = (rotation ?? page.rotation) % 360;
    final processedRel = _files.processedRel(page.uuid, rev);
    final thumbRel = _files.thumbRel(page.uuid, rev);
    final stored = await _storeSides(page.uuid, composition.sides, revision: rev);
    final copied = {for (final s in stored) s.originalPath}.difference({for (final s in old.sides) s.originalPath});
    final next = IdComposition(layout: composition.layout, sides: stored);
    try {
      final size = await _pipeline.renderIdCard(
        IdRenderRequest(
          sides: _absolute(stored),
          layout: next.layout,
          rotation: r,
          processedPath: _files.abs(processedRel),
          thumbPath: _files.abs(thumbRel),
        ),
      );
      await _repo.updatePageRender(
        page,
        quad: stored.first.quad,
        filter: next.layout.filter,
        rotation: r,
        paper: next.layout.paper,
        revision: rev,
        processedPath: processedRel,
        thumbPath: thumbRel,
        width: size.width,
        height: size.height,
        composition: next,
      );
    } catch (_) {
      await _files.deleteRelative(processedRel);
      await _files.deleteRelative(thumbRel);
      for (final rel in copied) {
        await _files.deleteRelative(rel);
      }
      rethrow;
    }
    // Fotos de lados que se reemplazaron.
    final kept = {for (final s in stored) s.originalPath};
    for (final s in old.sides) {
      if (!kept.contains(s.originalPath)) await _files.deleteRelative(s.originalPath);
    }
  }

  /// Copia a la carpeta de la página los lados con ruta absoluta y devuelve
  /// todos con ruta relativa.
  Future<List<IdSide>> _storeSides(String uuid, List<IdSide> sides, {required int revision}) async {
    final out = <IdSide>[];
    for (final (i, s) in sides.indexed) {
      if (!p.isAbsolute(s.originalPath)) {
        out.add(s);
        continue;
      }
      final rel = _files.sideRel(uuid, i, revision);
      await File(s.originalPath).copy(_files.abs(rel));
      out.add(s.copyWith(originalPath: rel));
    }
    return out;
  }

  List<IdSide> _absolute(List<IdSide> sides) => [
    for (final s in sides) s.copyWith(originalPath: _files.abs(s.originalPath)),
  ];

  /// Vuelve a renderizar [page] desde su original con los ajustes cambiados.
  /// En una identificación, [filter] y [paper] cambian su acomodo.
  Future<void> rerender(ScanPage page, {Quad? quad, PageFilter? filter, int? rotation, PaperSize? paper}) async {
    final comp = page.composition;
    if (comp != null) {
      final physical = PaperSize.physical.contains(paper) ? paper : null;
      return recomposeIdCard(
        page,
        IdComposition(
          layout: comp.layout.copyWith(filter: filter, paper: physical),
          sides: comp.sides,
        ),
        rotation: rotation,
      );
    }
    final rev = page.revision + 1;
    final q = quad ?? page.quad;
    final f = filter ?? page.filter;
    final r = (rotation ?? page.rotation) % 360;
    final pp = paper ?? page.paper;
    final processedRel = _files.processedRel(page.uuid, rev);
    final thumbRel = _files.thumbRel(page.uuid, rev);
    try {
      final size = await _pipeline.render(
        RenderRequest(
          originalPath: _files.abs(page.originalPath),
          quad: q,
          filter: f,
          rotation: r,
          paper: pp,
          processedPath: _files.abs(processedRel),
          thumbPath: _files.abs(thumbRel),
        ),
      );
      await _repo.updatePageRender(
        page,
        quad: q,
        filter: f,
        rotation: r,
        paper: pp,
        revision: rev,
        processedPath: processedRel,
        thumbPath: thumbRel,
        width: size.width,
        height: size.height,
      );
    } catch (_) {
      await _files.deleteRelative(processedRel);
      await _files.deleteRelative(thumbRel);
      rethrow;
    }
  }
}
