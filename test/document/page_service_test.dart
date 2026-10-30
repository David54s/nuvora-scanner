import 'dart:io';

import 'package:nuvora_scanner/core/db/app_database.dart';
import 'package:nuvora_scanner/core/imaging/id_layout.dart';
import 'package:nuvora_scanner/core/imaging/image_pipeline.dart';
import 'package:nuvora_scanner/core/imaging/page_filter.dart';
import 'package:nuvora_scanner/core/imaging/paper_size.dart';
import 'package:nuvora_scanner/core/imaging/quad.dart';
import 'package:nuvora_scanner/core/storage/file_store.dart';
import 'package:nuvora_scanner/features/document/application/page_service.dart';
import 'package:nuvora_scanner/features/library/data/library_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opencv_dart/opencv.dart' as cv;
import 'package:path/path.dart' as p;

/// Flujo completo con el pipeline real (en isolates), base en memoria y
/// archivos en un directorio temporal.
void main() {
  late Directory tmp;
  late AppDatabase db;
  late FileStore files;
  late LibraryRepository repo;
  late PageService service;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('page_service_test');
    db = AppDatabase(NativeDatabase.memory());
    files = FileStore(root: Directory(p.join(tmp.path, 'docs')), cache: Directory(p.join(tmp.path, 'cache')));
    repo = LibraryRepository(db, files);
    service = PageService(repo, files, const ImagePipeline());
  });

  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  String photo(String name) {
    final path = p.join(tmp.path, '$name.jpg');
    final m = cv.Mat.fromScalar(600, 400, cv.MatType.CV_8UC3, cv.Scalar(60, 60, 60));
    cv.imwrite(path, m);
    m.dispose();
    return path;
  }

  const quad = Quad(Pt(0.1, 0.1), Pt(0.9, 0.1), Pt(0.9, 0.9), Pt(0.1, 0.9));

  test('saveScan crea el documento y los archivos de cada página', () async {
    final progress = <int>[];
    final id = await service.saveScan(
      [
        PageDraft(imagePath: photo('a'), quad: quad, filter: PageFilter.bw, paper: PaperSize.original),
        PageDraft(
          imagePath: photo('b'),
          quad: Quad.full,
          filter: PageFilter.original,
          rotation: 90,
          paper: PaperSize.original,
        ),
      ],
      title: 'Prueba',
      onProgress: (done, _) => progress.add(done),
    );
    expect(progress, [0, 1, 2]);

    final pages = await repo.pagesOf(id);
    expect(pages, hasLength(2));
    for (final page in pages) {
      for (final rel in [page.originalPath, page.processedPath, page.thumbPath]) {
        expect(File(files.abs(rel)).existsSync(), isTrue, reason: rel);
      }
    }
    // 0.8 de 400×600 = 320×480.
    expect((pages[0].width, pages[0].height), (320, 480));
    // Rotada 90°: 600×400.
    expect((pages[1].width, pages[1].height), (600, 400));
  });

  test('saveScan agrega a un documento existente', () async {
    final id = await service.saveScan([
      PageDraft(imagePath: photo('a'), quad: quad, filter: PageFilter.bw, paper: PaperSize.original),
    ], title: 'D');
    final again = await service.saveScan(
      [PageDraft(imagePath: photo('b'), quad: quad, filter: PageFilter.bw, paper: PaperSize.original)],
      documentId: id,
      title: 'ignorado',
    );
    expect(again, id);
    expect(await repo.pagesOf(id), hasLength(2));
  });

  test('si una página falla no queda nada a medias', () async {
    await expectLater(
      service.saveScan([
        PageDraft(imagePath: photo('a'), quad: quad, filter: PageFilter.bw, paper: PaperSize.original),
        PageDraft(
          imagePath: p.join(tmp.path, 'no_existe.jpg'),
          quad: quad,
          filter: PageFilter.bw,
          paper: PaperSize.original,
        ),
      ], title: 'Roto'),
      throwsA(anything),
    );
    expect(await repo.watchDocuments().first, isEmpty);
    final pagesDir = Directory(p.join(files.root.path, 'pages'));
    expect(pagesDir.existsSync() ? pagesDir.listSync() : [], isEmpty);
  });

  test('auto ajusta una hoja de proporción 1.5 a oficio', () async {
    final id = await service.saveScan([
      PageDraft(imagePath: photo('a'), quad: quad, filter: PageFilter.bw),
    ], title: 'D');
    final page = (await repo.pagesOf(id)).single;
    expect(page.paper, PaperSize.auto);
    expect(page.height / page.width, closeTo(PaperSize.oficio.ratio!, 0.01));
  });

  test('rerender sube la revisión y reemplaza los archivos', () async {
    final id = await service.saveScan([
      PageDraft(imagePath: photo('a'), quad: quad, filter: PageFilter.bw, paper: PaperSize.original),
    ], title: 'D');
    final before = (await repo.pagesOf(id)).single;
    await service.rerender(before, rotation: 90, filter: PageFilter.grayscale);
    final after = (await repo.pagesOf(id)).single;

    expect(after.revision, 1);
    expect((after.rotation, after.filter), (90, PageFilter.grayscale));
    expect((after.width, after.height), (480, 320));
    expect(File(files.abs(before.processedPath)).existsSync(), isFalse);
    expect(File(files.abs(after.processedPath)).existsSync(), isTrue);
  });

  group('identificación', () {
    const layout = IdLayout(template: IdTemplate.ine);
    List<IdSide> sides() => [
      IdSide(originalPath: photo('frente'), quad: quad),
      IdSide(originalPath: photo('reverso'), quad: quad),
    ];

    test('saveIdCard crea un documento de una hoja con los lados guardados', () async {
      final id = await service.saveIdCard(sides(), layout, title: 'INE');
      final page = (await repo.pagesOf(id)).single;
      final comp = page.composition!;
      expect(comp.sides, hasLength(2));
      for (final s in comp.sides) {
        expect(p.isAbsolute(s.originalPath), isFalse);
        expect(File(files.abs(s.originalPath)).existsSync(), isTrue, reason: s.originalPath);
      }
      expect(page.originalPath, comp.sides.first.originalPath);
      expect((page.width, page.height), (2550, 3300), reason: 'Carta a 300 dpi');
      expect(page.paper, PaperSize.letter);
      expect(File(files.abs(page.processedPath)).existsSync(), isTrue);
      expect(File(files.abs(page.thumbPath)).existsSync(), isTrue);
    });

    test('recomposeIdCard cambia el acomodo y reemplaza un lado tomado de nuevo', () async {
      final id = await service.saveIdCard(sides(), layout, title: 'INE');
      final before = (await repo.pagesOf(id)).single;
      final oldBack = before.composition!.sides[1].originalPath;
      await service.recomposeIdCard(
        before,
        IdComposition(
          layout: layout.copyWith(paper: PaperSize.oficio, swapped: true),
          sides: [
            before.composition!.sides[0],
            IdSide(originalPath: photo('otro'), quad: Quad.full),
          ],
        ),
      );
      final after = (await repo.pagesOf(id)).single;
      expect(after.revision, 1);
      expect(after.paper, PaperSize.oficio);
      expect(after.composition!.layout.swapped, isTrue);
      expect(after.composition!.sides[0].originalPath, before.composition!.sides[0].originalPath);
      expect(after.composition!.sides[1].originalPath, isNot(oldBack));
      expect(File(files.abs(after.composition!.sides[1].originalPath)).existsSync(), isTrue);
      expect(File(files.abs(oldBack)).existsSync(), isFalse, reason: 'el lado reemplazado se borra');
      expect(File(files.abs(before.processedPath)).existsSync(), isFalse);
      expect(after.height / after.width, closeTo(PaperSize.oficio.ratio!, 0.01));
    });

    test('rerender de una identificación gira la hoja y cambia el filtro', () async {
      final id = await service.saveIdCard(sides(), layout, title: 'INE');
      final before = (await repo.pagesOf(id)).single;
      await service.rerender(before, rotation: 90, filter: PageFilter.grayscale, paper: PaperSize.auto);
      final after = (await repo.pagesOf(id)).single;
      expect((after.width, after.height), (3300, 2550));
      expect(after.composition!.layout.filter, PageFilter.grayscale);
      expect(after.composition!.layout.paper, PaperSize.letter, reason: 'Auto no aplica a identificaciones');
    });
  });
}
