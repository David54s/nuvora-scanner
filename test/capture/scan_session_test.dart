import 'dart:io';

import 'package:nuvora_scanner/core/db/app_database.dart';
import 'package:nuvora_scanner/core/imaging/page_filter.dart';
import 'package:nuvora_scanner/core/providers.dart';
import 'package:nuvora_scanner/core/storage/file_store.dart';
import 'package:nuvora_scanner/features/capture/application/scan_session.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opencv_dart/opencv.dart' as cv;
import 'package:path/path.dart' as p;

/// Flujo de una foto a la vez con el pipeline real, base en memoria y
/// archivos temporales.
void main() {
  late Directory tmp;
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('scan_session_test');
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        fileStoreProvider.overrideWithValue(
          FileStore(root: Directory(p.join(tmp.path, 'docs')), cache: Directory(p.join(tmp.path, 'cache'))),
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  /// Foto sintética: hoja clara sobre fondo oscuro.
  String photo(String name) {
    final path = p.join(tmp.path, '$name.jpg');
    final m = cv.Mat.fromScalar(900, 600, cv.MatType.CV_8UC3, cv.Scalar.all(50));
    final poly = cv.VecVecPoint.fromList([
      [cv.Point(100, 120), cv.Point(500, 140), cv.Point(520, 780), cv.Point(80, 760)],
    ]);
    cv.fillPoly(m, poly, cv.Scalar.all(235));
    cv.imwrite(path, m);
    poly.dispose();
    m.dispose();
    return path;
  }

  ScanSession session() => container.read(scanSessionProvider.notifier);
  ScanState state() => container.read(scanSessionProvider);

  test('capturar → agregar → capturar → agregar crea un solo documento', () async {
    await session().start();
    await session().capture(photo('a'), deleteSource: true);
    expect(state().current!.ready, isTrue);
    expect(state().current!.detectedQuad, isNotNull, reason: 'debería detectar la hoja');

    session().setFilter(PageFilter.bw);
    final docId = await session().commitCurrent();
    expect(state().current, isNull);
    expect(state().pagesAdded, 1);
    expect(state().documentId, docId);
    expect(state().lastThumbPath, isNotNull);
    expect(File(p.join(tmp.path, 'a.jpg')).existsSync(), isFalse, reason: 'la foto de origen se borra');

    await session().capture(photo('b'));
    final again = await session().commitCurrent();
    expect(again, docId);

    final pages = await container.read(libraryRepositoryProvider).pagesOf(docId);
    expect(pages.map((p) => p.orderIndex), [0, 1]);
    // El filtro elegido pasa a ser el predeterminado de la siguiente foto.
    expect(pages.map((p) => p.filter), [PageFilter.bw, PageFilter.bw]);
  });

  test('repetir descarta la foto sin guardar nada', () async {
    await session().start();
    await session().capture(photo('a'));
    final capturePath = state().current!.path;
    await session().discardCurrent();
    expect(state().current, isNull);
    expect(File(capturePath).existsSync(), isFalse);
    expect(await container.read(libraryRepositoryProvider).watchDocuments().first, isEmpty);
  });

  test('cola de importación de la galería', () async {
    await session().start();
    session().enqueueImports([photo('a'), photo('b')]);
    expect(await session().nextImport(), isTrue);
    expect(state().importQueue, hasLength(1));
    await session().clearImports();
    expect(state().importQueue, isEmpty);
    expect(await session().nextImport(), isFalse);
  });
}
