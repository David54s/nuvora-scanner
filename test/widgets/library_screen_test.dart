import 'dart:io';

import 'package:nuvora_scanner/core/db/app_database.dart';
import 'package:nuvora_scanner/core/providers.dart';
import 'package:nuvora_scanner/core/storage/file_store.dart';
import 'package:nuvora_scanner/features/library/data/library_repository.dart';
import 'package:nuvora_scanner/features/library/presentation/library_screen.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  late AppDatabase db;
  late FileStore files;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('library_widget_test');
    db = AppDatabase(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));
    files = FileStore(root: Directory('${tmp.path}/docs'), cache: Directory('${tmp.path}/cache'));
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> pumpLibrary(WidgetTester tester, {int? folderId}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db), fileStoreProvider.overrideWithValue(files)],
        child: MaterialApp(home: LibraryScreen(folderId: folderId)),
      ),
    );
    // Los streams de drift agrupan consultas con temporizadores: hay que avanzar el reloj falso.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
  }

  Future<void> disposeAll(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await db.close();
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('Inicio vacío muestra las herramientas y la invitación a escanear', (tester) async {
    await pumpLibrary(tester);
    expect(find.text('Todavía no hay documentos'), findsOneWidget);
    // Sin herramientas usadas todavía, se sugieren todas.
    expect(find.text('Herramientas'), findsOneWidget);
    expect(find.text('Escanear documento'), findsOneWidget);
    expect(find.text('Identificación'), findsOneWidget);
    expect(find.text('Mis archivos'), findsOneWidget);
    // Escanear está en la barra inferior, no en un botón flotante.
    expect(find.byType(FloatingActionButton), findsNothing);
    await disposeAll(tester);
  });

  testWidgets('una carpeta conserva los botones flotantes para escanear en ella', (tester) async {
    final folder = await tester.runAsync(() => LibraryRepository(db, files).createFolder('Trabajo'));
    await pumpLibrary(tester, folderId: folder);
    expect(find.text('Escanear'), findsOneWidget);
    expect(find.text('Mis archivos'), findsNothing);
    await disposeAll(tester);
  });

  testWidgets('muestra carpetas y documentos de la raíz', (tester) async {
    await tester.runAsync(() async {
      final repo = LibraryRepository(db, files);
      final folder = await repo.createFolder('Trabajo');
      await repo.createDocument(title: 'Contrato', folderId: folder, pages: []);
      await repo.createDocument(title: 'Recibo de luz', pages: []);
    });
    await pumpLibrary(tester);

    expect(find.text('Trabajo'), findsOneWidget);
    expect(find.text('1 documento'), findsOneWidget);
    expect(find.text('Recibo de luz'), findsOneWidget);
    // El documento de la carpeta no aparece en la raíz.
    expect(find.text('Contrato'), findsNothing);
    await disposeAll(tester);
  });
}
