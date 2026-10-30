import 'dart:io';

import 'package:nuvora_scanner/core/db/app_database.dart';
import 'package:nuvora_scanner/core/imaging/page_filter.dart';
import 'package:nuvora_scanner/core/imaging/paper_size.dart';
import 'package:nuvora_scanner/core/imaging/quad.dart';
import 'package:nuvora_scanner/core/storage/file_store.dart';
import 'package:nuvora_scanner/features/library/data/library_repository.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory tmp;
  late AppDatabase db;
  late FileStore files;
  late LibraryRepository repo;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('repo_test');
    db = AppDatabase(NativeDatabase.memory());
    files = FileStore(root: Directory(p.join(tmp.path, 'docs')), cache: Directory(p.join(tmp.path, 'cache')));
    repo = LibraryRepository(db, files);
  });

  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  /// Crea los archivos de una página en disco y devuelve su [NewPage].
  Future<NewPage> fakePage(String uuid) async {
    await files.ensurePageDir(uuid);
    for (final rel in [files.originalRel(uuid), files.processedRel(uuid, 0), files.thumbRel(uuid, 0)]) {
      File(files.abs(rel)).writeAsBytesSync([1, 2, 3]);
    }
    return NewPage(
      uuid: uuid,
      originalPath: files.originalRel(uuid),
      processedPath: files.processedRel(uuid, 0),
      thumbPath: files.thumbRel(uuid, 0),
      quad: Quad.full,
      filter: PageFilter.enhanced,
      rotation: 0,
      width: 100,
      height: 140,
    );
  }

  bool pageDirExists(String uuid) => Directory(files.abs(files.pageDirRel(uuid))).existsSync();

  test('crea un documento con páginas ordenadas y la portada es la primera', () async {
    final id = await repo.createDocument(title: 'Factura', pages: [await fakePage('a'), await fakePage('b')]);
    final pages = await repo.pagesOf(id);
    expect(pages.map((p) => (p.uuid, p.orderIndex)), [('a', 0), ('b', 1)]);
    expect(pages.first.quad, Quad.full);
    expect(pages.first.filter, PageFilter.enhanced);

    final docs = await repo.watchDocuments().first;
    expect(docs.single.pageCount, 2);
    expect(docs.single.coverThumbPath, files.thumbRel('a', 0));
  });

  test('agregar páginas continúa el orden', () async {
    final id = await repo.createDocument(title: 'Doc', pages: [await fakePage('a')]);
    await repo.appendPages(id, [await fakePage('b'), await fakePage('c')]);
    final pages = await repo.pagesOf(id);
    expect(pages.map((p) => p.orderIndex), [0, 1, 2]);
  });

  test('reordenar y borrar dejan order_index contiguo', () async {
    final id = await repo.createDocument(
      title: 'Doc',
      pages: [await fakePage('a'), await fakePage('b'), await fakePage('c')],
    );
    var pages = await repo.pagesOf(id);
    await repo.reorderPages(id, [pages[2].id, pages[0].id, pages[1].id]);
    pages = await repo.pagesOf(id);
    expect(pages.map((p) => p.uuid), ['c', 'a', 'b']);

    await repo.deletePage(pages[1]);
    pages = await repo.pagesOf(id);
    expect(pages.map((p) => (p.uuid, p.orderIndex)), [('c', 0), ('b', 1)]);
    expect(pageDirExists('a'), isFalse);
  });

  test('borrar un documento borra sus páginas y archivos', () async {
    final id = await repo.createDocument(title: 'Doc', pages: [await fakePage('a'), await fakePage('b')]);
    await repo.deleteDocument(id);
    expect(await repo.pagesOf(id), isEmpty);
    expect(pageDirExists('a'), isFalse);
    expect(pageDirExists('b'), isFalse);
  });

  test('borrar una carpeta mueve sus documentos a la raíz', () async {
    final folder = await repo.createFolder('Trabajo');
    final id = await repo.createDocument(title: 'Doc', folderId: folder, pages: [await fakePage('a')]);
    expect((await repo.watchFolders().first).single.documentCount, 1);
    expect(await repo.watchDocuments().first, isEmpty);

    await repo.deleteFolder(folder);
    final root = await repo.watchDocuments().first;
    expect(root.single.document.id, id);
    expect(await repo.pagesOf(id), hasLength(1));
  });

  test('buscar por título ignora la carpeta y escapa comodines', () async {
    final folder = await repo.createFolder('F');
    await repo.createDocument(title: 'Contrato 100%', folderId: folder, pages: []);
    await repo.createDocument(title: 'Contrato 1000', pages: []);
    expect((await repo.watchDocuments(query: 'contrato').first), hasLength(2));
    expect((await repo.watchDocuments(query: '100%').first).single.document.title, 'Contrato 100%');
  });

  test('updatePageRender guarda la revisión nueva y borra los archivos viejos', () async {
    final id = await repo.createDocument(title: 'Doc', pages: [await fakePage('a')]);
    final old = (await repo.pagesOf(id)).single;
    File(files.abs(files.processedRel('a', 1))).writeAsBytesSync([1]);
    File(files.abs(files.thumbRel('a', 1))).writeAsBytesSync([1]);

    await repo.updatePageRender(
      old,
      quad: Quad.full,
      filter: PageFilter.bw,
      rotation: 90,
      paper: PaperSize.letter,
      revision: 1,
      processedPath: files.processedRel('a', 1),
      thumbPath: files.thumbRel('a', 1),
      width: 140,
      height: 100,
    );
    final updated = (await repo.pagesOf(id)).single;
    expect(
      (updated.filter, updated.rotation, updated.paper, updated.revision),
      (PageFilter.bw, 90, PaperSize.letter, 1),
    );
    expect(File(files.abs(old.processedPath)).existsSync(), isFalse);
    expect(File(files.abs(old.thumbPath)).existsSync(), isFalse);
    expect(File(files.abs(files.originalRel('a'))).existsSync(), isTrue);
  });

  test('sweepOrphans borra carpetas de páginas sin fila', () async {
    await repo.createDocument(title: 'Doc', pages: [await fakePage('a')]);
    await fakePage('huerfana');
    expect(await repo.sweepOrphans(), 1);
    expect(pageDirExists('a'), isTrue);
    expect(pageDirExists('huerfana'), isFalse);
  });

  test('ajustes', () async {
    expect(await repo.getSetting('filtro'), isNull);
    await repo.setSetting('filtro', 'bw');
    await repo.setSetting('filtro', 'enhanced');
    expect(await repo.getSetting('filtro'), 'enhanced');
  });
}
