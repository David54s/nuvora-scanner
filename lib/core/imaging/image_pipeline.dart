import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:opencv_dart/opencv.dart' as cv;

import 'edge_detector.dart';
import 'filters.dart';
import 'page_filter.dart';
import 'paper_size.dart';
import 'perspective.dart';
import 'quad.dart';

const _originalJpegQuality = 92;
const _processedJpegQuality = 90;
const thumbnailSide = 480;

/// Datos para renderizar una página a partir de su original.
class RenderRequest {
  const RenderRequest({
    required this.originalPath,
    required this.quad,
    required this.filter,
    required this.rotation,
    required this.processedPath,
    required this.thumbPath,
    this.paper = PaperSize.original,
  });

  final String originalPath;
  final Quad quad;
  final PageFilter filter;
  final int rotation;
  final PaperSize paper;
  final String processedPath;
  final String thumbPath;
}

typedef ImageSize = ({int width, int height});

/// Operaciones de imagen pesadas. Cada llamada corre entera en un isolate
/// aparte; entre isolates solo viajan rutas y datos simples, nunca Mats.
class ImagePipeline {
  const ImagePipeline();

  /// Lee [srcPath] (aplicando la orientación EXIF) y lo guarda normalizado
  /// como JPEG en [dstPath], para que Flutter y OpenCV vean los mismos píxeles.
  Future<ImageSize> ingest(String srcPath, String dstPath) => Isolate.run(() => ingestSync(srcPath, dstPath));

  Future<QuadDetection> detect(String path) => Isolate.run(() => detectSync(path));

  /// [ingest] y [detect] en una sola pasada, sin volver a decodificar la foto.
  Future<(ImageSize, QuadDetection)> ingestAndDetect(String srcPath, String dstPath) =>
      Isolate.run(() => ingestAndDetectSync(srcPath, dstPath));

  Future<ImageSize> render(RenderRequest req) => Isolate.run(() => renderSync(req));

  /// Cómo quedará la página (recorte + tamaño de papel + filtro + rotación), como JPEG en memoria
  /// de como mucho [maxSide] px. [sourceSize] permite decodificar a menor
  /// resolución las fotos grandes.
  Future<Uint8List> preview(
    String path, {
    required Quad quad,
    required PageFilter filter,
    required int rotation,
    required ImageSize sourceSize,
    PaperSize paper = PaperSize.original,
    int maxSide = 1280,
  }) => Isolate.run(() => previewSync(path, quad, filter, rotation, sourceSize, maxSide, paper: paper));
}

(ImageSize, QuadDetection) ingestAndDetectSync(String srcPath, String dstPath) {
  final img = _read(srcPath);
  try {
    _writeJpeg(dstPath, img, _originalJpegQuality);
    return ((width: img.cols, height: img.rows), detectQuad(img));
  } finally {
    img.dispose();
  }
}

Uint8List previewSync(
  String path,
  Quad quad,
  PageFilter filter,
  int rotation,
  ImageSize sourceSize,
  int maxSide, {
  PaperSize paper = PaperSize.original,
}) {
  final longSide = math.max(sourceSize.width, sourceSize.height);
  // El quad está normalizado, así que se puede decodificar a 1/2 o 1/4; se
  // deja margen para que el recorte siga llegando a [maxSide].
  final flags = longSide >= 6 * maxSide
      ? cv.IMREAD_REDUCED_COLOR_4
      : longSide >= 3 * maxSide
      ? cv.IMREAD_REDUCED_COLOR_2
      : cv.IMREAD_COLOR;
  final img = _read(path, flags: flags);
  cv.Mat? warped, filtered, rotated;
  final params = cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, 85]);
  try {
    warped = warpQuad(
      img,
      quad,
      maxSide: maxSide,
      aspect: targetAspect(paper, quad, sourceSize.width, sourceSize.height),
    );
    filtered = applyFilter(warped, filter);
    rotated = rotateQuarterTurns(filtered, rotation);
    final (ok, bytes) = cv.imencode('.jpg', rotated, params: params);
    if (!ok) throw ImageWriteException('(vista previa)');
    return bytes;
  } finally {
    img.dispose();
    warped?.dispose();
    filtered?.dispose();
    rotated?.dispose();
    params.dispose();
  }
}

ImageSize ingestSync(String srcPath, String dstPath) {
  final img = _read(srcPath);
  try {
    _writeJpeg(dstPath, img, _originalJpegQuality);
    return (width: img.cols, height: img.rows);
  } finally {
    img.dispose();
  }
}

QuadDetection detectSync(String path) {
  final img = _read(path);
  try {
    return detectQuad(img);
  } finally {
    img.dispose();
  }
}

/// original → recorte de perspectiva (ajustado al papel) → filtro → rotación
/// → JPEG + miniatura.
ImageSize renderSync(RenderRequest req) {
  final img = _read(req.originalPath);
  cv.Mat? warped, filtered, rotated, thumb;
  try {
    warped = warpQuad(img, req.quad, aspect: targetAspect(req.paper, req.quad, img.cols, img.rows));
    filtered = applyFilter(warped, req.filter);
    rotated = rotateQuarterTurns(filtered, req.rotation);
    _writeJpeg(req.processedPath, rotated, _processedJpegQuality);

    final s = thumbnailSide / math.max(rotated.cols, rotated.rows);
    thumb = s < 1
        ? cv.resize(rotated, (
            math.max(1, (rotated.cols * s).round()),
            math.max(1, (rotated.rows * s).round()),
          ), interpolation: cv.INTER_AREA)
        : rotated.clone();
    _writeJpeg(req.thumbPath, thumb, 85);
    return (width: rotated.cols, height: rotated.rows);
  } finally {
    img.dispose();
    warped?.dispose();
    filtered?.dispose();
    rotated?.dispose();
    thumb?.dispose();
  }
}

cv.Mat _read(String path, {int flags = cv.IMREAD_COLOR}) {
  final img = cv.imread(path, flags: flags);
  if (img.isEmpty) {
    img.dispose();
    throw ImageReadException(path);
  }
  return img;
}

void _writeJpeg(String path, cv.Mat img, int quality) {
  final params = cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, quality]);
  try {
    if (!cv.imwrite(path, img, params: params)) {
      throw ImageWriteException(path);
    }
  } finally {
    params.dispose();
  }
}

class ImageReadException implements Exception {
  ImageReadException(this.path);
  final String path;
  @override
  String toString() => 'No se pudo leer la imagen: $path';
}

class ImageWriteException implements Exception {
  ImageWriteException(this.path);
  final String path;
  @override
  String toString() => 'No se pudo escribir la imagen: $path';
}
