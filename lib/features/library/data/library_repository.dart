import 'package:drift/drift.dart';

import '../../../core/db/app_database.dart';
import '../../../core/imaging/id_layout.dart';
import '../../../core/imaging/page_filter.dart';
import '../../../core/imaging/paper_size.dart';
import '../../../core/imaging/quad.dart';
import '../../../core/storage/file_store.dart';

class FolderSummary {
  const FolderSummary(this.folder, this.documentCount);
  final Folder folder;
  final int documentCount;
}

class DocumentSummary {
  const DocumentSummary(this.document, this.pageCount, this.coverThumbPath);
  final Document document;
  final int pageCount;

  /// Ruta relativa de la miniatura de la primera página, si hay páginas.
  final String? coverThumbPath;
}

/// Página ya renderizada en disco, lista para insertarse.
class NewPage {
  const NewPage({
    required this.uuid,
    required this.originalPath,
    required this.processedPath,
    required this.thumbPath,
    required this.quad,
    required this.filter,
    required this.rotation,
    required this.width,
    required this.height,
    this.paper = PaperSize.original,
    this.composition,
  });

  final String uuid;
  final String originalPath;
  final String processedPath;
  final String thumbPath;
  final Quad quad;
  final PageFilter filter;
  final int rotation;
  final int width;
  final int height;
  final PaperSize paper;

  /// Solo en páginas de identificación.
  final IdComposition? composition;
}

/// Acceso a carpetas, documentos y páginas. Los archivos de una página se
/// escriben antes de insertar su fila y se borran después de borrarla.
class LibraryRepository {
  LibraryRepository(this._db, this._files);

  final AppDatabase _db;
  final FileStore _files;

  // ---------- Consultas ----------

  Stream<List<FolderSummary>> watchFolders({int? parentId}) {
    return _db
        .customSelect(
          'SELECT f.*, (SELECT COUNT(*) FROM documents d WHERE d.folder_id = f.id) AS doc_count '
          'FROM folders f WHERE f.parent_id IS ? ORDER BY f.name COLLATE NOCASE',
          variables: [Variable<int>(parentId)],
          readsFrom: {_db.folders, _db.documents},
        )
        .watch()
        .map((rows) => [for (final r in rows) FolderSummary(_db.folders.map(r.data), r.read<int>('doc_count'))]);
  }

  Stream<Folder?> watchFolder(int id) => (_db.select(_db.folders)..where((f) => f.id.equals(id))).watchSingleOrNull();

  Future<List<Folder>> allFolders() =>
      (_db.select(_db.folders)..orderBy([(f) => OrderingTerm.asc(f.name.collate(Collate.noCase))])).get();

  /// Documentos de una carpeta (null = raíz), del más reciente al más antiguo.
  /// Con [query] no vacío busca por título en todas las carpetas.
  Stream<List<DocumentSummary>> watchDocuments({int? folderId, String query = ''}) {
    final q = query.trim();
    final where = q.isEmpty ? 'd.folder_id IS ?' : "d.title LIKE ? ESCAPE '\\'";
    final arg = q.isEmpty ? Variable<int>(folderId) : Variable<String>('%${_escapeLike(q)}%');
    return _db
        .customSelect(
          'SELECT d.*, '
          '(SELECT COUNT(*) FROM pages p WHERE p.document_id = d.id) AS page_count, '
          '(SELECT p.thumb_path FROM pages p WHERE p.document_id = d.id ORDER BY p.order_index LIMIT 1) AS cover '
          'FROM documents d WHERE $where ORDER BY d.updated_at DESC',
          variables: [arg],
          readsFrom: {_db.documents, _db.pages},
        )
        .watch()
        .map(
          (rows) => [
            for (final r in rows)
              DocumentSummary(_db.documents.map(r.data), r.read<int>('page_count'), r.readNullable<String>('cover')),
          ],
        );
  }

  Stream<Document?> watchDocument(int id) =>
      (_db.select(_db.documents)..where((d) => d.id.equals(id))).watchSingleOrNull();

  Future<Document?> document(int id) => (_db.select(_db.documents)..where((d) => d.id.equals(id))).getSingleOrNull();

  Stream<List<ScanPage>> watchPages(int documentId) => _pagesQuery(documentId).watch();

  Future<List<ScanPage>> pagesOf(int documentId) => _pagesQuery(documentId).get();

  Future<ScanPage?> page(int id) => (_db.select(_db.pages)..where((p) => p.id.equals(id))).getSingleOrNull();

  SimpleSelectStatement<$PagesTable, ScanPage> _pagesQuery(int documentId) => _db.select(_db.pages)
    ..where((p) => p.documentId.equals(documentId))
    ..orderBy([(p) => OrderingTerm.asc(p.orderIndex)]);

  // ---------- Carpetas ----------

  Future<int> createFolder(String name, {int? parentId}) =>
      _db.into(_db.folders).insert(FoldersCompanion.insert(name: name.trim(), parentId: Value(parentId)));

  Future<void> renameFolder(int id, String name) => (_db.update(
    _db.folders,
  )..where((f) => f.id.equals(id))).write(FoldersCompanion(name: Value(name.trim()), updatedAt: Value(DateTime.now())));

  /// Borra la carpeta; sus documentos pasan a la raíz.
  Future<void> deleteFolder(int id) => (_db.delete(_db.folders)..where((f) => f.id.equals(id))).go();

  // ---------- Documentos ----------

  Future<int> createDocument({required String title, int? folderId, required List<NewPage> pages}) {
    return _db.transaction(() async {
      final id = await _db
          .into(_db.documents)
          .insert(DocumentsCompanion.insert(title: title.trim(), folderId: Value(folderId)));
      await _insertPages(id, pages, startIndex: 0);
      return id;
    });
  }

  Future<void> appendPages(int documentId, List<NewPage> pages) {
    return _db.transaction(() async {
      final maxIndex = _db.pages.orderIndex.max();
      final row =
          await (_db.selectOnly(_db.pages)
                ..addColumns([maxIndex])
                ..where(_db.pages.documentId.equals(documentId)))
              .getSingle();
      await _insertPages(documentId, pages, startIndex: (row.read(maxIndex) ?? -1) + 1);
      await _touch(documentId);
    });
  }

  Future<void> _insertPages(int documentId, List<NewPage> pages, {required int startIndex}) async {
    await _db.batch((b) {
      b.insertAll(_db.pages, [
        for (final (i, p) in pages.indexed)
          PagesCompanion.insert(
            documentId: documentId,
            uuid: p.uuid,
            orderIndex: startIndex + i,
            originalPath: p.originalPath,
            processedPath: p.processedPath,
            thumbPath: p.thumbPath,
            quad: p.quad,
            filter: p.filter,
            rotation: Value(p.rotation),
            paper: Value(p.paper),
            composition: Value(p.composition),
            width: p.width,
            height: p.height,
          ),
      ]);
    });
  }

  Future<void> renameDocument(int id, String title) => (_db.update(_db.documents)..where((d) => d.id.equals(id))).write(
    DocumentsCompanion(title: Value(title.trim()), updatedAt: Value(DateTime.now())),
  );

  Future<void> moveDocument(int id, int? folderId) => (_db.update(_db.documents)..where((d) => d.id.equals(id))).write(
    DocumentsCompanion(folderId: Value(folderId), updatedAt: Value(DateTime.now())),
  );

  Future<void> deleteDocument(int id) async {
    final uuids = (await pagesOf(id)).map((p) => p.uuid).toList();
    await (_db.delete(_db.documents)..where((d) => d.id.equals(id))).go();
    for (final u in uuids) {
      await _files.deletePageDir(u);
    }
  }

  // ---------- Páginas ----------

  /// Guarda el resultado de un re-render (filtro, rotación, papel o recorte nuevos) y
  /// borra los archivos de la revisión anterior.
  Future<void> updatePageRender(
    ScanPage old, {
    required Quad quad,
    required PageFilter filter,
    required int rotation,
    required PaperSize paper,
    required int revision,
    required String processedPath,
    required String thumbPath,
    required int width,
    required int height,
    IdComposition? composition,
  }) async {
    await _db.transaction(() async {
      await (_db.update(_db.pages)..where((p) => p.id.equals(old.id))).write(
        PagesCompanion(
          composition: composition == null ? const Value.absent() : Value(composition),
          quad: Value(quad),
          filter: Value(filter),
          rotation: Value(rotation),
          paper: Value(paper),
          revision: Value(revision),
          processedPath: Value(processedPath),
          thumbPath: Value(thumbPath),
          width: Value(width),
          height: Value(height),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await _touch(old.documentId);
    });
    if (old.processedPath != processedPath) await _files.deleteRelative(old.processedPath);
    if (old.thumbPath != thumbPath) await _files.deleteRelative(old.thumbPath);
  }

  /// Reescribe `order_index` como 0..n-1 en el orden de [pageIdsInOrder].
  Future<void> reorderPages(int documentId, List<int> pageIdsInOrder) {
    return _db.transaction(() async {
      for (final (i, id) in pageIdsInOrder.indexed) {
        await (_db.update(
          _db.pages,
        )..where((p) => p.id.equals(id) & p.documentId.equals(documentId))).write(PagesCompanion(orderIndex: Value(i)));
      }
      await _touch(documentId);
    });
  }

  Future<void> deletePage(ScanPage page) async {
    await _db.transaction(() async {
      await (_db.delete(_db.pages)..where((p) => p.id.equals(page.id))).go();
      final rest = await pagesOf(page.documentId);
      for (final (i, p) in rest.indexed) {
        if (p.orderIndex != i) {
          await (_db.update(_db.pages)..where((x) => x.id.equals(p.id))).write(PagesCompanion(orderIndex: Value(i)));
        }
      }
      await _touch(page.documentId);
    });
    await _files.deletePageDir(page.uuid);
  }

  Future<void> _touch(int documentId) => (_db.update(
    _db.documents,
  )..where((d) => d.id.equals(documentId))).write(DocumentsCompanion(updatedAt: Value(DateTime.now())));

  // ---------- Mantenimiento y ajustes ----------

  /// Borra carpetas de páginas sin fila (p. ej. si la app murió a mitad de un guardado).
  Future<int> sweepOrphans() async {
    final uuids = await (_db.selectOnly(
      _db.pages,
    )..addColumns([_db.pages.uuid])).map((r) => r.read(_db.pages.uuid)!).get();
    return _files.sweepOrphanPages(uuids.toSet());
  }

  Future<String?> getSetting(String key) async =>
      (await (_db.select(_db.settings)..where((s) => s.key.equals(key))).getSingleOrNull())?.value;

  Future<void> setSetting(String key, String value) =>
      _db.into(_db.settings).insertOnConflictUpdate(SettingsCompanion.insert(key: key, value: value));
}

String _escapeLike(String s) => s.replaceAll('\\', '\\\\').replaceAll('%', '\\%').replaceAll('_', '\\_');
