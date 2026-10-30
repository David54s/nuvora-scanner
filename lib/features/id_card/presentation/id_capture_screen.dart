import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/imaging/id_layout.dart';
import '../../capture/presentation/scan_camera_view.dart';
import '../application/id_scan_session.dart';

/// Cámara para los lados que faltan de la identificación de la
/// [IdScanSession]: cada foto abre la revisión de bordes. Devuelve `true` con
/// `pop` cuando ya están todos, o `false` si se sale antes.
class IdCaptureScreen extends ConsumerStatefulWidget {
  const IdCaptureScreen({super.key});

  @override
  ConsumerState<IdCaptureScreen> createState() => _IdCaptureScreenState();
}

class _IdCaptureScreenState extends ConsumerState<IdCaptureScreen> {
  final _camera = GlobalKey<ScanCameraViewState>();

  IdScanSession get _session => ref.read(idScanSessionProvider.notifier);

  Future<void> _shoot() async {
    final path = await _camera.currentState?.takePicture();
    if (path == null || !mounted) return;
    await _review(path);
  }

  Future<void> _importFromGallery() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    await _review(picked.path);
  }

  Future<void> _review(String path) async {
    unawaited(_session.captureSide(path, deleteSource: true));
    await _camera.currentState?.pause();
    if (!mounted) return;
    await context.push<bool>('/id/review');
    if (!mounted) return;
    if (ref.read(idScanSessionProvider).nextMissing == null) {
      context.pop(true);
      return;
    }
    await _camera.currentState?.resume();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(idScanSessionProvider);
    final template = state.layout.template;
    final index = state.nextMissing ?? state.current;
    final sideName = template.sides[index.clamp(0, template.sides.length - 1)];
    final camera = _camera.currentState;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.pop(false);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text(template.label),
          actions: [
            if (camera?.hasCamera ?? false)
              IconButton(
                tooltip: camera!.flashOn ? 'Apagar linterna' : 'Encender linterna',
                icon: Icon(camera.flashOn ? Icons.flash_on : Icons.flash_off),
                onPressed: camera.toggleFlash,
              ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Text(
                template.sides.length == 1
                    ? 'Coloca la ${sideName.toLowerCase()} dentro del marco'
                    : '$sideName (${index + 1} de ${template.sides.length}): colócalo dentro del marco',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
            Expanded(
              child: Center(
                child: ScanCameraView(
                  key: _camera,
                  overlay: _GuideFrame(template: template),
                  onStateChanged: () => setState(() {}),
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      tooltip: 'Elegir de la galería',
                      iconSize: 32,
                      color: Colors.white,
                      onPressed: _importFromGallery,
                      icon: const Icon(Icons.photo_library_outlined),
                    ),
                    ShutterButton(enabled: camera?.canShoot ?? false, onPressed: _shoot),
                    _SidesProgress(state: state, session: _session),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Marco con la forma de la tarjeta; oscurece lo de fuera.
class _GuideFrame extends StatelessWidget {
  const _GuideFrame({required this.template});

  final IdTemplate template;

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _GuidePainter(template.aspect));
}

class _GuidePainter extends CustomPainter {
  _GuidePainter(this.aspect);

  final double aspect;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width * idGuideWidth;
    final h = w / aspect;
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: size.center(Offset.zero), width: w, height: h),
      Radius.circular(w * 0.04),
    );
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(rect);
    canvas.drawPath(outside, Paint()..color = Colors.black.withValues(alpha: 0.45));
    canvas.drawRRect(
      rect,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(_GuidePainter old) => old.aspect != aspect;
}

/// Miniaturas de los lados ya tomados.
class _SidesProgress extends StatelessWidget {
  const _SidesProgress({required this.state, required this.session});

  final IdScanState state;
  final IdScanSession session;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final s in state.sides)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Container(
                width: 52,
                height: 33,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white54),
                  borderRadius: BorderRadius.circular(4),
                ),
                clipBehavior: Clip.antiAlias,
                child: s == null || !s.ready
                    ? null
                    : Image.file(File(session.absolutePath(s)), fit: BoxFit.cover, cacheWidth: 120),
              ),
            ),
        ],
      ),
    );
  }
}
