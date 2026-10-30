import 'dart:io';

import 'package:path/path.dart' as p;

/// Organiza los archivos de la app. La base de datos guarda rutas relativas a
/// [root] para que sigan siendo válidas si Android cambia la ruta absoluta.
///
/// ```
/// <root>/pages/<pageUuid>/original.jpg
///                          processed_r<rev>.jpg
///                          thumb_r<rev>.jpg
///                          side<i>_r<rev>.jpg  lados de una identificación
/// <cache>/capture/<uuid>.jpg      fotos de la sesión de escaneo
/// <cache>/exports/*.pdf           PDFs generados para compartir
/// ```
class FileStore {
  FileStore({required this.root, required this.cache});

  final Directory root;
  final Directory cache;

  static const _pagesDir = 'pages';

  String abs(String relative) => p.join(root.path, relative);

  String pageDirRel(String pageUuid) => p.join(_pagesDir, pageUuid);
  String originalRel(String pageUuid) => p.join(pageDirRel(pageUuid), 'original.jpg');
  String processedRel(String pageUuid, int revision) => p.join(pageDirRel(pageUuid), 'processed_r$revision.jpg');
  String sideRel(String pageUuid, int index, int revision) =>
      p.join(pageDirRel(pageUuid), 'side${index}_r$revision.jpg');
  String thumbRel(String pageUuid, int revision) => p.join(pageDirRel(pageUuid), 'thumb_r$revision.jpg');

  Directory get captureDir => Directory(p.join(cache.path, 'capture'));
  Directory get exportsDir => Directory(p.join(cache.path, 'exports'));

  Future<void> ensurePageDir(String pageUuid) => Directory(abs(pageDirRel(pageUuid))).create(recursive: true);

  Future<void> deletePageDir(String pageUuid) => _deleteDir(Directory(abs(pageDirRel(pageUuid))));

  Future<void> deleteRelative(String relative) async {
    final f = File(abs(relative));
    if (await f.exists()) await f.delete();
  }

  /// Borra las carpetas de páginas que ya no tienen fila en la base.
  /// Devuelve cuántas se borraron.
  Future<int> sweepOrphanPages(Set<String> knownUuids) async {
    final dir = Directory(p.join(root.path, _pagesDir));
    if (!await dir.exists()) return 0;
    var removed = 0;
    await for (final entry in dir.list()) {
      if (entry is Directory && !knownUuids.contains(p.basename(entry.path))) {
        await _deleteDir(entry);
        removed++;
      }
    }
    return removed;
  }

  Future<void> clearCaptures() => _deleteDir(captureDir);
  Future<void> clearExports() => _deleteDir(exportsDir);

  Future<void> _deleteDir(Directory dir) async {
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}
