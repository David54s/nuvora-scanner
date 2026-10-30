import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvora_scanner/core/db/app_database.dart';
import 'package:nuvora_scanner/core/imaging/id_layout.dart';
import 'package:nuvora_scanner/core/imaging/page_filter.dart';
import 'package:nuvora_scanner/core/imaging/paper_size.dart';
import 'package:nuvora_scanner/core/providers.dart';
import 'package:nuvora_scanner/core/storage/file_store.dart';
import 'package:nuvora_scanner/features/id_card/application/id_scan_session.dart';
import 'package:opencv_dart/opencv.dart' as cv;
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late AppDatabase db;
  late FileStore files;
  late ProviderContainer container;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('id_scan_session_test');
    db = AppDatabase(NativeDatabase.memory());
    files = FileStore(root: Directory(p.join(tmp.path, 'docs')), cache: Directory(p.join(tmp.path, 'cache')));
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db), fileStoreProvider.overrideWithValue(files)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  /// Foto vertical 900×1200 con una tarjeta clara sobre fondo oscuro.
  String cardPhoto(String name, {bool portraitCard = false}) {
    final img = cv.Mat.fromScalar(1200, 900, cv.MatType.CV_8UC3, cv.Scalar.all(50));
    final rect = portraitCard ? cv.Rect(280, 260, 340, 540) : cv.Rect(110, 380, 680, 430);
    cv.rectangle(img, rect, cv.Scalar(220, 200, 180), thickness: -1);
    final path = p.join(tmp.path, '$name.jpg');
    cv.imwrite(path, img);
    img.dispose();
    return path;
  }

  IdScanSession session() => container.read(idScanSessionProvider.notifier);
  IdScanState state() => container.read(idScanSessionProvider);

  test('toma los dos lados, guarda una hoja y recuerda el acomodo', () async {
    await session().start(IdTemplate.ine);
    expect(state().sides, [null, null]);
    expect(state().nextMissing, 0);

    await session().captureSide(cardPhoto('frente'), deleteSource: true);
    expect(state().sides[0]!.ready, isTrue);
    expect(state().sides[0]!.detectedQuad, isNotNull, reason: 'la tarjeta se detecta');
    expect(state().sides[0]!.rotation, 0);
    expect(state().nextMissing, 1);

    // Tarjeta en vertical: se gira para dejarla horizontal.
    await session().captureSide(cardPhoto('reverso', portraitCard: true), deleteSource: true);
    expect(state().sides[1]!.rotation, 90);
    expect(state().complete, isTrue);

    session().setLayout(state().layout.copyWith(paper: PaperSize.oficio, filter: PageFilter.grayscale));
    final preview = await session().preview(maxSide: 400);
    expect(preview, isNotEmpty);

    final docId = await session().save();
    final repo = container.read(libraryRepositoryProvider);
    expect((await repo.document(docId))!.title, startsWith('INE '));
    final page = (await repo.pagesOf(docId)).single;
    expect(page.composition!.sides, hasLength(2));
    expect(page.height / page.width, closeTo(PaperSize.oficio.ratio!, 0.01));

    final tempPhotos = [for (final s in state().sides) s!.path];
    await session().discard();
    for (final path in tempPhotos) {
      expect(File(path).existsSync(), isFalse, reason: 'las fotos temporales se borran');
    }

    // La siguiente identificación parte del último acomodo.
    await session().start(IdTemplate.license);
    expect(state().layout.template, IdTemplate.license);
    expect(state().layout.paper, PaperSize.oficio);
    expect(state().layout.filter, PageFilter.grayscale);
  });

  test('si no encuentra la tarjeta usa el marco guía', () async {
    await session().start(IdTemplate.passport);
    final blank = cv.Mat.fromScalar(1200, 900, cv.MatType.CV_8UC3, cv.Scalar.all(128));
    final path = p.join(tmp.path, 'vacia.jpg');
    cv.imwrite(path, blank);
    blank.dispose();
    await session().captureSide(path);
    final s = state().sides.single!;
    expect(s.detectedQuad, isNull);
    expect(s.quad, idGuideQuad(IdTemplate.passport, 900, 1200));
  });

  test('editar una identificación guardada y repetir un lado', () async {
    await session().start(IdTemplate.card);
    await session().captureSide(cardPhoto('a'));
    await session().captureSide(cardPhoto('b'));
    final docId = await session().save();
    await session().discard();
    final repo = container.read(libraryRepositoryProvider);
    final page = (await repo.pagesOf(docId)).single;

    await session().startEditing(page.id);
    expect(state().editing, isTrue);
    expect(state().complete, isTrue);
    expect(state().sides.every((s) => s!.stored), isTrue);

    // Repetir el reverso y cancelar: se restaura.
    session().beginRetake(1);
    expect(state().complete, isFalse);
    await session().endRetake();
    expect(state().sides[1]!.stored, isTrue);

    // Repetirlo de verdad.
    session().beginRetake(1);
    await session().captureSide(cardPhoto('c'));
    await session().endRetake();
    expect(state().sides[1]!.stored, isFalse);

    session().setLayout(state().layout.copyWith(arrangement: IdArrangement.sideBySide));
    expect(await session().save(), docId);
    final after = (await repo.pagesOf(docId)).single;
    expect(after.revision, 1);
    expect(after.composition!.layout.arrangement, IdArrangement.sideBySide);
    expect(after.composition!.sides[0].originalPath, page.composition!.sides[0].originalPath);
    expect(after.composition!.sides[1].originalPath, isNot(page.composition!.sides[1].originalPath));
    expect(File(files.abs(page.composition!.sides[1].originalPath)).existsSync(), isFalse);
  });
}
