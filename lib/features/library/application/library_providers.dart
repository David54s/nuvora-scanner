import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/providers.dart';
import '../data/library_repository.dart';

typedef DocumentsQuery = ({int? folderId, String query});

final foldersProvider = StreamProvider.family<List<FolderSummary>, int?>(
  (ref, parentId) => ref.watch(libraryRepositoryProvider).watchFolders(parentId: parentId),
);

final folderProvider = StreamProvider.family<Folder?, int>(
  (ref, id) => ref.watch(libraryRepositoryProvider).watchFolder(id),
);

final documentsProvider = StreamProvider.family<List<DocumentSummary>, DocumentsQuery>(
  (ref, q) => ref.watch(libraryRepositoryProvider).watchDocuments(folderId: q.folderId, query: q.query),
);

final documentProvider = StreamProvider.family<Document?, int>(
  (ref, id) => ref.watch(libraryRepositoryProvider).watchDocument(id),
);

final pagesProvider = StreamProvider.family<List<ScanPage>, int>(
  (ref, documentId) => ref.watch(libraryRepositoryProvider).watchPages(documentId),
);
