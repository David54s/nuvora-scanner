import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/capture/presentation/camera_screen.dart';
import '../features/crop/presentation/page_crop_screen.dart';
import '../features/crop/presentation/review_screen.dart';
import '../features/document/presentation/document_screen.dart';
import '../features/document/presentation/page_editor_screen.dart';
import '../features/library/presentation/library_screen.dart';

/// Rutas planas que se abren con `push`. En el flujo de escaneo, `/review`
/// devuelve un [ReviewOutcome] y `/scan` el id del documento.
final routerProvider = Provider<GoRouter>((ref) {
  int id(GoRouterState s, String name) => int.parse(s.pathParameters[name]!);
  return GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const LibraryScreen()),
      GoRoute(
        path: '/folder/:folderId',
        builder: (_, s) => LibraryScreen(folderId: id(s, 'folderId')),
      ),
      GoRoute(path: '/scan', builder: (_, _) => const CameraScreen()),
      GoRoute(path: '/review', builder: (_, _) => const ReviewScreen()),
      GoRoute(
        path: '/doc/:docId',
        builder: (_, s) => DocumentScreen(documentId: id(s, 'docId')),
      ),
      GoRoute(
        path: '/doc/:docId/page/:pageId',
        builder: (_, s) => PageEditorScreen(documentId: id(s, 'docId'), initialPageId: id(s, 'pageId')),
      ),
      GoRoute(
        path: '/page/:pageId/crop',
        builder: (_, s) => PageCropScreen(pageId: id(s, 'pageId')),
      ),
    ],
  );
});
