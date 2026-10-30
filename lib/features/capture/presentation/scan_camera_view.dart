import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/imaging/live_edge_worker.dart';
import '../../../core/imaging/quad.dart';
import '../../../core/ui/dialogs.dart';

/// Vista de la cámara trasera con el contorno del documento en vivo, enfoque
/// por toque y linterna. La pantalla que la usa la controla con una
/// `GlobalKey<ScanCameraViewState>`: [ScanCameraViewState.takePicture],
/// [ScanCameraViewState.pause] / [ScanCameraViewState.resume] (mientras se
/// revisa una foto) y [ScanCameraViewState.toggleFlash].
class ScanCameraView extends StatefulWidget {
  const ScanCameraView({super.key, this.overlay, this.onStateChanged});

  /// Se dibuja sobre la vista previa, con su mismo tamaño (p. ej. un marco guía).
  final Widget? overlay;

  /// Avisa cuando cambia algo que la pantalla muestra (cámara lista, linterna).
  final VoidCallback? onStateChanged;

  @override
  State<ScanCameraView> createState() => ScanCameraViewState();
}

class ScanCameraViewState extends State<ScanCameraView> with WidgetsBindingObserver {
  CameraController? _controller;
  String? _error;
  bool _permissionDenied = false;
  bool _taking = false;
  bool _flashOn = false;

  /// Hay una pantalla de revisión encima: preview pausado y sin detección.
  bool _paused = false;
  Offset? _focusIndicator;

  LiveEdgeWorker? _worker;
  DateTime _lastFrame = DateTime.fromMillisecondsSinceEpoch(0);
  Quad? _liveQuad;
  int _misses = 0;
  int _stableFrames = 0;

  static const _frameInterval = Duration(milliseconds: 120);

  /// Hay cámara abierta (se puede usar la linterna).
  bool get hasCamera => _controller != null;

  /// Se puede tomar una foto ahora.
  bool get canShoot => _controller?.value.isInitialized == true && !_taking;

  bool get flashOn => _flashOn;

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

  void _changed(VoidCallback f) {
    setState(f);
    widget.onStateChanged?.call();
  }

  // ---------- Cámara ----------

  Future<void> _initCamera() async {
    // Desde initState no se puede llamar a setState (y ahí no hay error previo).
    if (_error != null || _permissionDenied) {
      _changed(() {
        _error = null;
        _permissionDenied = false;
      });
    }
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _changed(() => _error = 'No se encontró ninguna cámara.');
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
      _changed(() => _controller = controller);
      if (_paused) {
        await controller.pausePreview();
      } else {
        await _startLiveDetection();
      }
    } on CameraException catch (e) {
      if (!mounted) return;
      final denied = e.code.contains('AccessDenied') || e.code.contains('Restricted');
      _changed(() {
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
    _changed(() {
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
    if (worker == null || worker.busy || _paused || now.difference(_lastFrame) < _frameInterval) return;
    if (image.planes.isEmpty) return;
    _lastFrame = now;
    final y = image.planes.first;
    final frame = GrayFrame.fromYPlane(y.bytes, image.width, image.height, y.bytesPerRow);
    final sensor = _controller?.description.sensorOrientation ?? 90;
    worker
        .detect(frame)
        .then((det) {
          if (!mounted || _paused) return;
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

  /// Toma una foto (JPEG temporal). Devuelve su ruta, o null si no se pudo.
  Future<String?> takePicture() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _taking) return null;
    _changed(() => _taking = true);
    try {
      return (await c.takePicture()).path;
    } on CameraException catch (e) {
      if (mounted) showSnack(context, 'No se pudo tomar la foto: ${e.description ?? e.code}');
      return null;
    } finally {
      if (mounted) _changed(() => _taking = false);
    }
  }

  /// Pausa la vista previa y la detección (al abrir una revisión).
  Future<void> pause() async {
    _paused = true;
    await _stopLiveDetection();
    await _controller?.pausePreview();
  }

  Future<void> resume() async {
    _paused = false;
    await _controller?.resumePreview();
    await _startLiveDetection();
  }

  Future<void> toggleFlash() async {
    final c = _controller;
    if (c == null) return;
    final on = !_flashOn;
    try {
      // Linterna continua: más predecible que el flash para documentos.
      await c.setFlashMode(on ? FlashMode.torch : FlashMode.off);
      _changed(() => _flashOn = on);
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
              if (widget.overlay != null) Positioned.fill(child: IgnorePointer(child: widget.overlay)),
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

/// Botón redondo del obturador.
class ShutterButton extends StatelessWidget {
  const ShutterButton({super.key, required this.enabled, required this.onPressed});

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
