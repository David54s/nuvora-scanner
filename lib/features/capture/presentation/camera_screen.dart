import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/imaging/live_edge_worker.dart';
import '../../../core/imaging/quad.dart';
import '../../../core/providers.dart';
import '../../../core/ui/dialogs.dart';
import '../../crop/presentation/review_screen.dart';
import '../application/scan_session.dart';
import 'start_scan.dart';

/// Cámara del flujo de escaneo. Muestra en vivo el borde del documento; cada
/// foto abre la revisión, y al agregarla se vuelve aquí para la siguiente.
/// Devuelve con `pop` el id del documento (o null si no se agregó nada).
class CameraScreen extends ConsumerStatefulWidget {
  const CameraScreen({super.key});

  @override
  ConsumerState<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends ConsumerState<CameraScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  String? _error;
  bool _permissionDenied = false;
  bool _taking = false;
  bool _flashOn = false;

  /// La pantalla de revisión está encima: preview pausado y sin detección.
  bool _reviewing = false;
  Offset? _focusIndicator;

  LiveEdgeWorker? _worker;
  DateTime _lastFrame = DateTime.fromMillisecondsSinceEpoch(0);
  Quad? _liveQuad;
  int _misses = 0;
  int _stableFrames = 0;

  static const _frameInterval = Duration(milliseconds: 120);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // El contorno en vivo asume la vista vertical (ver _toPreview).
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _initCamera();
    LiveEdgeWorker.spawn().then((w) {
      if (mounted) {
        _worker = w;
      } else {
        w.dispose();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    _controller?.dispose();
    _worker?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _releaseCamera();
    } else if (state == AppLifecycleState.resumed && _controller == null) {
      _initCamera();
    }
  }

  // ---------- Cámara ----------

  Future<void> _initCamera() async {
    setState(() {
      _error = null;
      _permissionDenied = false;
    });
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _error = 'No se encontró ninguna cámara.');
        return;
      }
      final back = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cameras.first);
      final controller = CameraController(
        back,
        ResolutionPreset.max,
        enableAudio: false,
        // YUV para el análisis en vivo; la foto se toma igual en JPEG.
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      await controller.setFlashMode(_flashOn ? FlashMode.torch : FlashMode.off);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
      if (_reviewing) {
        await controller.pausePreview();
      } else {
        await _startLiveDetection();
      }
    } on CameraException catch (e) {
      if (!mounted) return;
      final denied = e.code.contains('AccessDenied') || e.code.contains('Restricted');
      setState(() {
        _permissionDenied = denied;
        _error = denied
            ? 'La app necesita permiso de cámara para escanear. Puedes darlo en Ajustes > Apps > Nuvora > Permisos.'
            : 'No se pudo abrir la cámara (${e.description ?? e.code}).';
      });
    }
  }

  void _releaseCamera() {
    final c = _controller;
    if (c == null) return;
    setState(() {
      _controller = null;
      _liveQuad = null;
    });
    c.dispose();
  }

  // ---------- Contorno en vivo ----------

  Future<void> _startLiveDetection() async {
    final c = _controller;
    if (c == null || c.value.isStreamingImages) return;
    try {
      await c.startImageStream(_onFrame);
    } on CameraException {
      // Algunos equipos no admiten el análisis junto con la foto a máxima
      // resolución: se sigue sin contorno en vivo.
    }
  }

  Future<void> _stopLiveDetection() async {
    final c = _controller;
    if (c != null && c.value.isStreamingImages) {
      try {
        await c.stopImageStream();
      } on CameraException {
        // Ya estaba detenido.
      }
    }
    if (mounted) setState(() => _liveQuad = null);
  }

  void _onFrame(CameraImage image) {
    final worker = _worker;
    final now = DateTime.now();
    if (worker == null || worker.busy || _reviewing || now.difference(_lastFrame) < _frameInterval) return;
    if (image.planes.isEmpty) return;
    _lastFrame = now;
    final y = image.planes.first;
    final frame = GrayFrame.fromYPlane(y.bytes, image.width, image.height, y.bytesPerRow);
    final sensor = _controller?.description.sensorOrientation ?? 90;
    worker
        .detect(frame)
        .then((det) {
          if (!mounted || _reviewing) return;
          setState(() {
            if (det == null) {
              _stableFrames = 0;
              if (++_misses >= 3) _liveQuad = null;
              return;
            }
            _misses = 0;
            final q = _toPreview(det.quad, sensor);
            final prev = _liveQuad;
            if (prev != null && _maxCornerShift(prev, q) < 0.15) {
              // Suavizado para que el contorno no tiemble.
              _liveQuad = _blend(prev, q, 0.5);
              _stableFrames = _maxCornerShift(prev, q) < 0.02 ? _stableFrames + 1 : 0;
            } else {
              _liveQuad = q;
              _stableFrames = 0;
            }
          });
        })
        .catchError((Object _) {});
  }

  /// Pasa un quad de la orientación del sensor a la de la vista previa
  /// (pantalla vertical).
  static Quad _toPreview(Quad q, int sensorOrientation) {
    Pt map(Pt p) => switch (sensorOrientation % 360) {
      90 => Pt(1 - p.y, p.x),
      180 => Pt(1 - p.x, 1 - p.y),
      270 => Pt(p.y, 1 - p.x),
      _ => p,
    };
    return Quad.fromUnordered([for (final p in q.points) map(p)]);
  }

  static double _maxCornerShift(Quad a, Quad b) {
    var m = 0.0;
    for (var i = 0; i < 4; i++) {
      final d = a.points[i].distanceTo(b.points[i]);
      if (d > m) m = d;
    }
    return m;
  }

  static Quad _blend(Quad a, Quad b, double t) {
    Pt lerp(Pt p, Pt q) => Pt(p.x + (q.x - p.x) * t, p.y + (q.y - p.y) * t);
    return Quad(lerp(a.tl, b.tl), lerp(a.tr, b.tr), lerp(a.br, b.br), lerp(a.bl, b.bl));
  }

  // ---------- Acciones ----------

  Future<void> _shoot() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _taking) return;
    setState(() => _taking = true);
    try {
      final file = await c.takePicture();
      unawaited(ref.read(scanSessionProvider.notifier).capture(file.path, deleteSource: true));
      await _review(() => context.push<ReviewOutcome>('/review'));
    } on CameraException catch (e) {
      if (mounted) showSnack(context, 'No se pudo tomar la foto: ${e.description ?? e.code}');
    } finally {
      if (mounted) setState(() => _taking = false);
    }
  }

  Future<void> _importFromGallery() async {
    final picked = await ImagePicker().pickMultiImage();
    if (picked.isEmpty || !mounted) return;
    ref.read(scanSessionProvider.notifier).enqueueImports([for (final x in picked) x.path]);
    await _review(() async => await reviewImports(context, ref) ? ReviewOutcome.finished : ReviewOutcome.added);
  }

  /// Pausa la cámara mientras se revisa y, al volver, termina o reanuda.
  Future<void> _review(Future<ReviewOutcome?> Function() open) async {
    _reviewing = true;
    await _stopLiveDetection();
    await _controller?.pausePreview();
    final outcome = await open();
    if (!mounted) return;
    _reviewing = false;
    if (outcome == ReviewOutcome.finished) {
      _finish();
      return;
    }
    await _controller?.resumePreview();
    await _startLiveDetection();
  }

  void _finish() => context.pop(ref.read(scanSessionProvider).documentId);

  Future<void> _toggleFlash() async {
    final c = _controller;
    if (c == null) return;
    final on = !_flashOn;
    try {
      // Linterna continua: más predecible que el flash para documentos.
      await c.setFlashMode(on ? FlashMode.torch : FlashMode.off);
      setState(() => _flashOn = on);
    } on CameraException {
      if (mounted) showSnack(context, 'Este dispositivo no tiene flash');
    }
  }

  Future<void> _focusAt(Offset local, Size size) async {
    final c = _controller;
    if (c == null) return;
    final point = Offset(local.dx / size.width, local.dy / size.height);
    setState(() => _focusIndicator = local);
    try {
      if (c.value.focusPointSupported) await c.setFocusPoint(point);
      if (c.value.exposurePointSupported) await c.setExposurePoint(point);
    } on CameraException {
      // Sin enfoque por toque: no es grave.
    }
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (mounted) setState(() => _focusIndicator = null);
  }

  // ---------- Interfaz ----------

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(scanSessionProvider);
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
            if (_controller != null)
              IconButton(
                tooltip: _flashOn ? 'Apagar linterna' : 'Encender linterna',
                icon: Icon(_flashOn ? Icons.flash_on : Icons.flash_off),
                onPressed: _toggleFlash,
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
            Expanded(child: Center(child: _buildPreview())),
            _BottomBar(
              lastThumbPath: session.lastThumbPath,
              pagesAdded: session.pagesAdded,
              canShoot: _controller != null && !_taking,
              onShoot: _shoot,
              onGallery: _importFromGallery,
              onDone: session.pagesAdded > 0 ? _finish : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _permissionDenied ? Icons.no_photography_outlined : Icons.error_outline,
              color: Colors.white70,
              size: 64,
            ),
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _initCamera, child: const Text('Reintentar')),
          ],
        ),
      );
    }
    final c = _controller;
    if (c == null || !c.value.isInitialized) return const CircularProgressIndicator();
    final colors = Theme.of(context).colorScheme;
    return CameraPreview(
      c,
      child: LayoutBuilder(
        builder: (context, constraints) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => _focusAt(d.localPosition, constraints.biggest),
          child: Stack(
            children: [
              if (_liveQuad != null)
                Positioned.fill(
                  child: CustomPaint(
                    painter: _LiveQuadPainter(
                      quad: _liveQuad!,
                      color: _stableFrames >= 4 ? Colors.greenAccent : colors.primaryContainer,
                    ),
                  ),
                ),
              if (_focusIndicator != null)
                Positioned(
                  left: _focusIndicator!.dx - 32,
                  top: _focusIndicator!.dy - 32,
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LiveQuadPainter extends CustomPainter {
  _LiveQuadPainter({required this.quad, required this.color});

  final Quad quad;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..addPolygon([for (final p in quad.points) Offset(p.x * size.width, p.y * size.height)], true);
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.18));
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_LiveQuadPainter old) => old.quad != quad || old.color != color;
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
            _ShutterButton(enabled: canShoot, onPressed: onShoot),
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

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({required this.enabled, required this.onPressed});

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Tomar foto',
      child: GestureDetector(
        onTap: enabled ? onPressed : null,
        child: Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
          ),
          padding: const EdgeInsets.all(5),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(shape: BoxShape.circle, color: enabled ? Colors.white : Colors.white38),
          ),
        ),
      ),
    );
  }
}
