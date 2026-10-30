import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:opencv_dart/opencv.dart' as cv;

import 'edge_detector.dart';
import 'filters.dart';
import 'id_composer.dart';
import 'id_layout.dart';
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

/// Datos para componer una página de identificación. Las rutas de
/// [sides] son absolutas.
class IdRenderRequest {
  const IdRenderRequest({
    required this.sides,
    required this.layout,
    required this.processedPath,
    required this.thumbPath,
    this.rotation = 0,
  });

  final List<IdSide> sides;
  final IdLayout layout;

  /// Giro de la hoja completa.
  final int rotation;
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

  /// Compone la hoja de una identificación a [idSheetDpi] y la guarda.
  Future<ImageSize> renderIdCard(IdRenderRequest req) => Isolate.run(() => renderIdCardSync(req));

  /// Cómo quedará la hoja de una identificación, como JPEG en memoria con el
  /// lado largo de unos [maxSide] px.
  Future<Uint8List> previewIdCard(List<IdSide> sides, IdLayout layout, {int rotation = 0, int maxSide = 1280}) =>
      Isolate.run(() => previewIdCardSync(sides, layout, rotation: rotation, maxSide: maxSide));
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
  cv.Mat? warped, filtered, placed, rotated;
  final params = cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, 85]);
  try {
    final layout = pageLayout(paper, quad, sourceSize.width, sourceSize.height);
    warped = warpQuad(img, quad, maxSide: maxSide, aspect: layout.warpAspect);
    filtered = applyFilter(warped, filter);
    placed = _onPaper(filtered, layout, maxSide);
    rotated = rotateQuarterTurns(placed, rotation);
    final (ok, bytes) = cv.imencode('.jpg', rotated, params: params);
    if (!ok) throw ImageWriteException('(vista previa)');
    return bytes;
  } finally {
    img.dispose();
    warped?.dispose();
    filtered?.dispose();
    placed?.dispose();
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

/// original → recorte de perspectiva → filtro → colocación sobre el papel
/// (sin deformar) → rotación → JPEG + miniatura.
ImageSize renderSync(RenderRequest req) {
  final img = _read(req.originalPath);
  cv.Mat? warped, filtered, placed, rotated;
  try {
    final layout = pageLayout(req.paper, req.quad, img.cols, img.rows);
    warped = warpQuad(img, req.quad, aspect: layout.warpAspect);
    filtered = applyFilter(warped, req.filter);
    placed = _onPaper(filtered, layout, maxPageSide);
    rotated = rotateQuarterTurns(placed, req.rotation);
    return _writeOutputs(rotated, req.processedPath, req.thumbPath);
  } finally {
    img.dispose();
    warped?.dispose();
    filtered?.dispose();
    placed?.dispose();
    rotated?.dispose();
  }
}

/// lados → hoja compuesta a [idSheetDpi] → giro → JPEG + miniatura.
ImageSize renderIdCardSync(IdRenderRequest req) {
  final images = <cv.Mat>[];
  cv.Mat? sheet, rotated;
  try {
    for (final s in req.sides) {
      images.add(_read(s.originalPath));
    }
    sheet = composeIdSheet(_sideImages(req.sides, images), req.layout);
    rotated = rotateQuarterTurns(sheet, req.rotation);
    return _writeOutputs(rotated, req.processedPath, req.thumbPath);
  } finally {
    for (final m in images) {
      m.dispose();
    }
    sheet?.dispose();
    rotated?.dispose();
  }
}

Uint8List previewIdCardSync(List<IdSide> sides, IdLayout layout, {int rotation = 0, int maxSide = 1280}) {
  final images = <cv.Mat>[];
  cv.Mat? sheet, rotated;
  final params = cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, 85]);
  try {
    // Cada lado ocupa una fracción de la hoja: con media resolución sobra.
    for (final s in sides) {
      images.add(_read(s.originalPath, flags: cv.IMREAD_REDUCED_COLOR_2));
    }
    final dpi = maxSide / (layout.paperHeightMm / 25.4);
    sheet = composeIdSheet(_sideImages(sides, images), layout, dpi: dpi);
    rotated = rotateQuarterTurns(sheet, rotation);
    final (ok, bytes) = cv.imencode('.jpg', rotated, params: params);
    if (!ok) throw ImageWriteException('(vista previa)');
    return bytes;
  } finally {
    for (final m in images) {
      m.dispose();
    }
    sheet?.dispose();
    rotated?.dispose();
    params.dispose();
  }
}

List<IdSideImage> _sideImages(List<IdSide> sides, List<cv.Mat> images) => [
  for (final (i, s) in sides.indexed) (image: images[i], quad: s.quad, rotation: s.rotation),
];

/// Escribe [page] y su miniatura. Devuelve el tamaño de [page].
ImageSize _writeOutputs(cv.Mat page, String processedPath, String thumbPath) {
  _writeJpeg(processedPath, page, _processedJpegQuality);
  final s = thumbnailSide / math.max(page.cols, page.rows);
  final thumb = s < 1
      ? cv.resize(page, (
          math.max(1, (page.cols * s).round()),
          math.max(1, (page.rows * s).round()),
        ), interpolation: cv.INTER_AREA)
      : page.clone();
  try {
    _writeJpeg(thumbPath, thumb, 85);
  } finally {
    thumb.dispose();
  }
  return (width: page.cols, height: page.rows);
}

/// Coloca la página sobre el papel si el [layout] lo pide; si no, la copia.
/// El margen se agrega después del filtro para que quede blanco puro.
cv.Mat _onPaper(cv.Mat page, PageLayout layout, int maxSide) {
  final paper = layout.paperAspect;
  return paper == null ? page.clone() : placeOnPaper(page, paper, maxSide: maxSide);
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
