import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/capture/presentation/camera_screen.dart';
import '../features/crop/presentation/page_crop_screen.dart';
import '../features/crop/presentation/review_screen.dart';
import '../features/document/presentation/document_screen.dart';
import '../features/document/presentation/page_editor_screen.dart';
import '../features/id_card/presentation/id_capture_screen.dart';
import '../features/id_card/presentation/id_layout_screen.dart';
import '../features/id_card/presentation/id_side_review_screen.dart';
import '../features/library/presentation/library_screen.dart';
import '../features/tools/presentation/tools_screen.dart';
import 'main_shell.dart';

/// Inicio y Herramientas son pestañas con la barra inferior; el resto son
/// rutas planas que se abren con `push` encima de la barra. En el flujo de
/// escaneo, `/review` devuelve un [ReviewOutcome] y `/scan` el id del
/// documento; en el de identificación, `/id/capture` devuelve si ya están
/// todos los lados y `/id/layout` el id del documento.
final routerProvider = Provider<GoRouter>((ref) {
  int id(GoRouterState s, String name) => int.parse(s.pathParameters[name]!);
  return GoRouter(
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => MainShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: '/', builder: (_, _) => const LibraryScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/tools', builder: (_, _) => const ToolsScreen())],
          ),
        ],
      ),
      GoRoute(
        path: '/folder/:folderId',
        builder: (_, s) => LibraryScreen(folderId: id(s, 'folderId')),
      ),
      GoRoute(path: '/scan', builder: (_, _) => const CameraScreen()),
      GoRoute(path: '/review', builder: (_, _) => const ReviewScreen()),
      GoRoute(path: '/id/capture', builder: (_, _) => const IdCaptureScreen()),
      GoRoute(
        path: '/id/review',
        builder: (_, s) => IdSideReviewScreen(adjusting: s.uri.queryParameters['adjust'] == '1'),
      ),
      GoRoute(path: '/id/layout', builder: (_, _) => const IdLayoutScreen()),
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
      GoRoute(
        path: '/page/:pageId/id-layout',
        builder: (_, s) => IdLayoutScreen(pageId: id(s, 'pageId')),
      ),
    ],
  );
});
