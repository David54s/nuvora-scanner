import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../imaging/page_filter.dart';
import '../imaging/paper_size.dart';
import '../imaging/quad.dart';
import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [Folders, Documents, Pages, Settings])
class AppDatabase extends _$AppDatabase {
  /// Sin [executor] abre `scanner.sqlite` en el directorio de documentos de la
  /// app; las pruebas pasan `NativeDatabase.memory()`.
  AppDatabase([QueryExecutor? executor]) : super(executor ?? driftDatabase(name: 'scanner'));

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      // v2: tamaño de papel por página.
      if (from < 2) await m.addColumn(pages, pages.paper);
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
