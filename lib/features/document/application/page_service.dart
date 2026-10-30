import 'dart:io';

import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
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

  /// Vuelve a renderizar [page] desde su original con los ajustes cambiados.
  Future<void> rerender(ScanPage page, {Quad? quad, PageFilter? filter, int? rotation, PaperSize? paper}) async {
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
