import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/document/application/page_service.dart';
import '../features/library/data/library_repository.dart';
import 'db/app_database.dart';
import 'imaging/image_pipeline.dart';
import 'storage/file_store.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// Se sobrescribe en `main()` una vez resueltos los directorios de la app.
final fileStoreProvider = Provider<FileStore>(
  (ref) => throw UnimplementedError('fileStoreProvider debe sobrescribirse en main()'),
);

final imagePipelineProvider = Provider<ImagePipeline>((ref) => const ImagePipeline());

final libraryRepositoryProvider = Provider<LibraryRepository>(
  (ref) => LibraryRepository(ref.watch(databaseProvider), ref.watch(fileStoreProvider)),
);

final pageServiceProvider = Provider<PageService>(
  (ref) =>
      PageService(ref.watch(libraryRepositoryProvider), ref.watch(fileStoreProvider), ref.watch(imagePipelineProvider)),
);
