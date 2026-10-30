import 'dart:io';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvora_scanner/app/router.dart';
import 'package:nuvora_scanner/core/db/app_database.dart';
import 'package:nuvora_scanner/core/providers.dart';
import 'package:nuvora_scanner/core/storage/file_store.dart';

void main() {
  late Directory tmp;
  late AppDatabase db;
  late FileStore files;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('main_shell_test');
    db = AppDatabase(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));
    files = FileStore(root: Directory('${tmp.path}/docs'), cache: Directory('${tmp.path}/cache'));
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> settle(WidgetTester tester) async {
    // Los streams de drift agrupan consultas con temporizadores: hay que avanzar el reloj falso.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db), fileStoreProvider.overrideWithValue(files)],
        child: Consumer(builder: (context, ref, _) => MaterialApp.router(routerConfig: ref.watch(routerProvider))),
      ),
    );
    await settle(tester);
  }

  Future<void> disposeAll(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await db.close();
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('la barra inferior cambia entre Inicio y Herramientas', (tester) async {
    await pumpApp(tester);
    expect(find.text('Nuvora'), findsOneWidget);
    expect(find.text('Inicio'), findsOneWidget, reason: 'la pestaña activa muestra su nombre');
    expect(find.byTooltip('Escanear'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Herramientas').last);
    await settle(tester);
    expect(find.widgetWithText(AppBar, 'Herramientas'), findsOneWidget);
    expect(find.text('Escanear documento'), findsOneWidget);
    expect(find.text('Identificación'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Inicio'));
    await settle(tester);
    expect(find.text('Mis archivos'), findsOneWidget);
    await disposeAll(tester);
  });

  testWidgets('Identificación pide el tipo y queda como reciente', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.bySemanticsLabel('Herramientas').last);
    await settle(tester);

    await tester.runAsync(() async {
      await tester.tap(find.text('Identificación'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await settle(tester);
    expect(find.text('¿Qué vas a escanear?'), findsOneWidget);
    for (final t in ['INE / credencial', 'Licencia de conducir', 'Tarjeta', 'Pasaporte']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    // Cerrar sin elegir.
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);

    await tester.tap(find.bySemanticsLabel('Inicio'));
    await settle(tester);
    expect(find.text('Recientes'), findsOneWidget);
    await disposeAll(tester);
  });
}
