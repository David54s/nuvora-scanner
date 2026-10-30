import 'dart:io';

import 'package:nuvora_scanner/core/db/app_database.dart';
import 'package:nuvora_scanner/core/imaging/page_filter.dart';
import 'package:nuvora_scanner/core/imaging/paper_size.dart';
import 'package:nuvora_scanner/core/imaging/quad.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('una base v1 (sin tamaño de papel) se actualiza a v2 sin perder páginas', () async {
    final dir = Directory.systemTemp.createTempSync('migration_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/scanner.sqlite');

    // Base v1: el esquema actual sin la columna `paper` y con user_version = 1.
    final v1 = AppDatabase(NativeDatabase(file));
    final docId = await v1.into(v1.documents).insert(DocumentsCompanion.insert(title: 'Viejo'));
    await v1
        .into(v1.pages)
        .insert(
          PagesCompanion.insert(
            documentId: docId,
            uuid: 'u1',
            orderIndex: 0,
            originalPath: 'o',
            processedPath: 'p',
            thumbPath: 't',
            quad: Quad.full,
            filter: PageFilter.bw,
            width: 10,
            height: 10,
          ),
        );
    await v1.customStatement('ALTER TABLE pages DROP COLUMN paper');
    await v1.customStatement('PRAGMA user_version = 1');
    await v1.close();

    final v2 = AppDatabase(NativeDatabase(file));
    addTearDown(v2.close);
    final old = await v2.select(v2.pages).getSingle();
    expect(old.uuid, 'u1');
    expect(old.paper, PaperSize.original, reason: 'las páginas viejas conservan sus proporciones');

    await (v2.update(v2.pages)).write(const PagesCompanion(paper: Value(PaperSize.letter)));
    expect((await v2.select(v2.pages).getSingle()).paper, PaperSize.letter);
  });
}
