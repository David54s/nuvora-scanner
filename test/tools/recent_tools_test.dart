import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvora_scanner/core/db/app_database.dart';
import 'package:nuvora_scanner/core/providers.dart';
import 'package:nuvora_scanner/core/storage/file_store.dart';
import 'package:nuvora_scanner/features/tools/recent_tools.dart';
import 'package:nuvora_scanner/features/tools/tools.dart';

void main() {
  test('pushRecent pone al frente sin repetir y con límite', () {
    expect(pushRecent([], NuvoraTool.scan), [NuvoraTool.scan]);
    expect(pushRecent([NuvoraTool.scan], NuvoraTool.idCard), [NuvoraTool.idCard, NuvoraTool.scan]);
    expect(pushRecent([NuvoraTool.idCard, NuvoraTool.scan], NuvoraTool.scan), [NuvoraTool.scan, NuvoraTool.idCard]);
    final many = List.filled(maxRecentTools + 3, NuvoraTool.scan);
    expect(pushRecent(many, NuvoraTool.idCard).length, lessThanOrEqualTo(maxRecentTools));
  });

  test('las herramientas recientes se guardan en los ajustes', () async {
    final tmp = Directory.systemTemp.createTempSync('recent_tools_test');
    final db = AppDatabase(NativeDatabase.memory());
    final files = FileStore(root: tmp, cache: tmp);
    addTearDown(() async {
      await db.close();
      tmp.deleteSync(recursive: true);
    });
    ProviderContainer container() => ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db), fileStoreProvider.overrideWithValue(files)],
    );

    final a = container();
    expect(await a.read(recentToolsProvider.future), isEmpty);
    await a.read(recentToolsProvider.notifier).record(NuvoraTool.scan);
    await a.read(recentToolsProvider.notifier).record(NuvoraTool.idCard);
    expect(a.read(recentToolsProvider).value, [NuvoraTool.idCard, NuvoraTool.scan]);
    a.dispose();

    // Otra "sesión" de la app lee lo guardado.
    final b = container();
    addTearDown(b.dispose);
    expect(await b.read(recentToolsProvider.future), [NuvoraTool.idCard, NuvoraTool.scan]);
  });
}
