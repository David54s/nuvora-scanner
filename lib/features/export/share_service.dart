import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/db/app_database.dart';
import '../../core/providers.dart';
import '../../core/storage/file_store.dart';
import 'pdf_exporter.dart';

final shareServiceProvider = Provider<ShareService>((ref) => ShareService(ref.watch(fileStoreProvider)));

/// Exporta documentos y los entrega al menú de compartir de Android.
class ShareService {
  ShareService(this._files, [this._exporter = const PdfExporter()]);

  final FileStore _files;
  final PdfExporter _exporter;

  Future<String> exportPdf(Document doc, List<ScanPage> pages) => _exporter.export(
    title: doc.title,
    pages: [for (final p in pages) PdfPageInput(_files.abs(p.processedPath), p.width, p.height)],
    outDir: _files.exportsDir,
  );

  Future<void> sharePdfFile(String path, String title) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path, mimeType: 'application/pdf')],
        subject: title,
        title: title,
      ),
    );
  }

  Future<void> shareImages(Document doc, List<ScanPage> pages) => SharePlus.instance.share(
    ShareParams(
      files: [for (final p in pages) XFile(_files.abs(p.processedPath), mimeType: 'image/jpeg')],
      subject: doc.title,
      title: doc.title,
    ),
  );
}
