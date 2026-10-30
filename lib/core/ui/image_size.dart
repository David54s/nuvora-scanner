import 'dart:ui' as ui;

/// Lee solo la cabecera de la imagen en [path] para conocer su tamaño en px.
Future<ui.Size> imageFileSize(String path) async {
  final buffer = await ui.ImmutableBuffer.fromFilePath(path);
  final descriptor = await ui.ImageDescriptor.encoded(buffer);
  final size = ui.Size(descriptor.width.toDouble(), descriptor.height.toDouble());
  descriptor.dispose();
  buffer.dispose();
  return size;
}
