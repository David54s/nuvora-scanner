import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/providers.dart';
import '../../crop/presentation/review_screen.dart';
import '../application/scan_session.dart';
import 'scan_camera_view.dart';
import 'start_scan.dart';

/// Cámara del flujo de escaneo. Muestra en vivo el borde del documento; cada
/// foto abre la revisión, y al agregarla se vuelve aquí para la siguiente.
/// Devuelve con `pop` el id del documento (o null si no se agregó nada).
class CameraScreen extends ConsumerStatefulWidget {
  const CameraScreen({super.key});

  @override
  ConsumerState<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends ConsumerState<CameraScreen> {
  final _camera = GlobalKey<ScanCameraViewState>();

  Future<void> _shoot() async {
    final path = await _camera.currentState?.takePicture();
    if (path == null || !mounted) return;
    unawaited(ref.read(scanSessionProvider.notifier).capture(path, deleteSource: true));
    await _review(() => context.push<ReviewOutcome>('/review'));
  }

  Future<void> _importFromGallery() async {
    final picked = await ImagePicker().pickMultiImage();
    if (picked.isEmpty || !mounted) return;
    ref.read(scanSessionProvider.notifier).enqueueImports([for (final x in picked) x.path]);
    await _review(() async => await reviewImports(context, ref) ? ReviewOutcome.finished : ReviewOutcome.added);
  }

  /// Pausa la cámara mientras se revisa y, al volver, termina o reanuda.
  Future<void> _review(Future<ReviewOutcome?> Function() open) async {
    await _camera.currentState?.pause();
    final outcome = await open();
    if (!mounted) return;
    if (outcome == ReviewOutcome.finished) {
      _finish();
      return;
    }
    await _camera.currentState?.resume();
  }

  void _finish() => context.pop(ref.read(scanSessionProvider).documentId);

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(scanSessionProvider);
    final camera = _camera.currentState;
    return PopScope(
      // Las páginas ya están guardadas: salir siempre devuelve el documento.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _finish();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: const Text('Escanear'),
          actions: [
            if (camera?.hasCamera ?? false)
              IconButton(
                tooltip: camera!.flashOn ? 'Apagar linterna' : 'Encender linterna',
                icon: Icon(camera.flashOn ? Icons.flash_on : Icons.flash_off),
                onPressed: camera.toggleFlash,
              ),
            if (session.pagesAdded > 0)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton(onPressed: _finish, child: Text('Listo (${session.pagesAdded})')),
              ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: Center(
                child: ScanCameraView(key: _camera, onStateChanged: () => setState(() {})),
              ),
            ),
            _BottomBar(
              lastThumbPath: session.lastThumbPath,
              pagesAdded: session.pagesAdded,
              canShoot: camera?.canShoot ?? false,
              onShoot: _shoot,
              onGallery: _importFromGallery,
              onDone: session.pagesAdded > 0 ? _finish : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.lastThumbPath,
    required this.pagesAdded,
    required this.canShoot,
    required this.onShoot,
    required this.onGallery,
    required this.onDone,
  });

  final String? lastThumbPath;
  final int pagesAdded;
  final bool canShoot;
  final VoidCallback onShoot;
  final VoidCallback onGallery;
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              tooltip: 'Importar de la galería',
              iconSize: 32,
              color: Colors.white,
              onPressed: onGallery,
              icon: const Icon(Icons.photo_library_outlined),
            ),
            ShutterButton(enabled: canShoot, onPressed: onShoot),
            // Última página agregada; tocarla termina el escaneo.
            SizedBox(
              width: 56,
              height: 56,
              child: lastThumbPath == null
                  ? null
                  : Consumer(
                      builder: (context, ref, _) => GestureDetector(
                        onTap: onDone,
                        child: Badge.count(
                          count: pagesAdded,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              File(ref.watch(fileStoreProvider).abs(lastThumbPath!)),
                              width: 56,
                              height: 56,
                              fit: BoxFit.cover,
                              cacheWidth: 160,
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
