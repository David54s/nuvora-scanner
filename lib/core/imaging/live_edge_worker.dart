import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:opencv_dart/opencv.dart' as cv;

import 'edge_detector.dart';
import 'quad.dart';

/// Cuadro en gris ya compactado (sin relleno de fila) y reducido.
class GrayFrame {
  const GrayFrame(this.bytes, this.width, this.height);

  final Uint8List bytes;
  final int width;
  final int height;

  /// Copia el plano Y de un cuadro YUV420 quitando el relleno de cada fila
  /// ([rowStride]) y tomando 1 de cada `step` píxeles para que el lado largo
  /// quede cerca de [targetSide].
  factory GrayFrame.fromYPlane(Uint8List y, int width, int height, int rowStride, {int targetSide = 480}) {
    final step = math.max(1, (math.max(width, height) / targetSide).floor());
    final w = width ~/ step, h = height ~/ step;
    final out = Uint8List(w * h);
    for (var r = 0; r < h; r++) {
      final src = r * step * rowStride;
      final dst = r * w;
      for (var c = 0; c < w; c++) {
        out[dst + c] = y[src + c * step];
      }
    }
    return GrayFrame(out, w, h);
  }
}

/// Detección continua de bordes para la vista previa de la cámara. Corre en
/// un isolate de larga vida para no pagar el arranque en cada cuadro; procesa
/// un cuadro a la vez (el que llama descarta los que llegan mientras tanto).
class LiveEdgeWorker {
  LiveEdgeWorker._(this._isolate, this._send, this._responses);

  final Isolate _isolate;
  final SendPort _send;
  final StreamIterator<dynamic> _responses;
  bool _busy = false;

  bool get busy => _busy;

  static Future<LiveEdgeWorker> spawn() async {
    final receive = ReceivePort();
    final isolate = await Isolate.spawn(_workerMain, receive.sendPort);
    final responses = StreamIterator<dynamic>(receive);
    await responses.moveNext();
    return LiveEdgeWorker._(isolate, responses.current as SendPort, responses);
  }

  /// Detecta el documento en [frame]. Devuelve null si no hay uno claro.
  /// El quad está normalizado respecto a [frame] (orientación del sensor).
  Future<QuadDetection?> detect(GrayFrame frame) async {
    if (_busy) throw StateError('LiveEdgeWorker ocupado');
    _busy = true;
    try {
      _send.send((TransferableTypedData.fromList([frame.bytes]), frame.width, frame.height));
      await _responses.moveNext();
      final r = _responses.current as List<double>?;
      if (r == null) return null;
      return QuadDetection(Quad(Pt(r[0], r[1]), Pt(r[2], r[3]), Pt(r[4], r[5]), Pt(r[6], r[7])), r[8], 'live');
    } finally {
      _busy = false;
    }
  }

  void dispose() {
    _responses.cancel();
    _isolate.kill(priority: Isolate.immediate);
  }
}

void _workerMain(SendPort replies) {
  final requests = ReceivePort();
  replies.send(requests.sendPort);
  requests.listen((message) {
    final (data, w, h) = message as (TransferableTypedData, int, int);
    final bytes = data.materialize().asUint8List();
    final mat = cv.Mat.create(rows: h, cols: w, type: cv.MatType.CV_8UC1);
    try {
      mat.data.setAll(0, bytes);
      final det = detectQuad(mat, fast: true);
      replies.send(
        det.found
            ? <double>[
                for (final p in det.quad.points) ...[p.x, p.y],
                det.confidence,
              ]
            : null,
      );
    } catch (_) {
      replies.send(null);
    } finally {
      mat.dispose();
    }
  });
}
