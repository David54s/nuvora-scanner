import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/db/app_database.dart';
import '../../../core/providers.dart';
import '../../../core/ui/dialogs.dart';
import '../../capture/presentation/start_scan.dart';
import '../../document/presentation/document_actions.dart';
import '../application/library_providers.dart';
import '../data/library_repository.dart';
import 'widgets/document_card.dart';

/// Logo de la app (también es el ícono del launcher).
const nuvoraLogo = 'assets/branding/nuvora.png';

/// Inicio (sin [folderId]) o contenido de una carpeta.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key, this.folderId});

  final int? folderId;

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  bool _searching = false;
  String _query = '';

  bool get _isRoot => widget.folderId == null;

  Future<void> _scan({required bool fromGallery}) async {
    final docId = await startScan(context, ref, folderId: widget.folderId, fromGallery: fromGallery);
    if (docId != null && mounted) context.push('/doc/$docId');
  }

  Future<void> _newFolder() async {
    final name = await showTextInputDialog(context, title: 'Nueva carpeta', confirmLabel: 'Crear', hint: 'Nombre');
    if (name != null) await ref.read(libraryRepositoryProvider).createFolder(name);
  }

  Future<void> _renameFolder(Folder folder) async {
    final name = await showTextInputDialog(context, title: 'Renombrar carpeta', initialValue: folder.name);
    if (name != null) await ref.read(libraryRepositoryProvider).renameFolder(folder.id, name);
  }

  /// Devuelve true si se borró.
  Future<bool> _deleteFolder(Folder folder) async {
    final ok = await showConfirmDialog(
      context,
      title: '¿Borrar carpeta?',
      message: 'Se borrará "${folder.name}". Sus documentos no se pierden: pasan a Inicio.',
    );
    if (ok) await ref.read(libraryRepositoryProvider).deleteFolder(folder.id);
    return ok;
  }

  @override
  Widget build(BuildContext context) {
    final folder = _isRoot ? null : ref.watch(folderProvider(widget.folderId!)).value;
    final docs = ref.watch(documentsProvider((folderId: widget.folderId, query: _query)));
    final showFolders = _isRoot && _query.trim().isEmpty;
    final folders = showFolders ? ref.watch(foldersProvider(null)) : const AsyncData(<FolderSummary>[]);

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Buscar por título', border: InputBorder.none),
                onChanged: (v) => setState(() => _query = v),
              )
            : _isRoot
            ? const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image(image: AssetImage(nuvoraLogo), width: 32, height: 32),
                  SizedBox(width: 10),
                  Text('Nuvora'),
                ],
              )
            : Text(folder?.name ?? ''),
        actions: [
          IconButton(
            tooltip: _searching ? 'Cerrar búsqueda' : 'Buscar',
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              _searching = !_searching;
              _query = '';
            }),
          ),
          if (_isRoot)
            IconButton(
              tooltip: 'Nueva carpeta',
              icon: const Icon(Icons.create_new_folder_outlined),
              onPressed: _newFolder,
            )
          else if (folder != null)
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'rename') await _renameFolder(folder);
                if (v == 'delete' && await _deleteFolder(folder) && context.mounted) context.pop();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text('Renombrar carpeta')),
                PopupMenuItem(value: 'delete', child: Text('Borrar carpeta')),
              ],
            ),
        ],
      ),
      body: _buildBody(folders, docs),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.small(
            heroTag: 'import',
            tooltip: 'Importar de la galería',
            onPressed: () => _scan(fromGallery: true),
            child: const Icon(Icons.photo_library_outlined),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'scan',
            onPressed: () => _scan(fromGallery: false),
            icon: const Icon(Icons.document_scanner_outlined),
            label: const Text('Escanear'),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(AsyncValue<List<FolderSummary>> folders, AsyncValue<List<DocumentSummary>> docs) {
    if (docs.hasError || folders.hasError) {
      return Center(child: Text('Error al cargar la biblioteca:\n${docs.error ?? folders.error}'));
    }
    if (!docs.hasValue || !folders.hasValue) return const Center(child: CircularProgressIndicator());
    final f = folders.requireValue;
    final d = docs.requireValue;
    if (f.isEmpty && d.isEmpty) return _EmptyState(searching: _query.trim().isNotEmpty);

    return CustomScrollView(
      slivers: [
        if (f.isNotEmpty)
          SliverList.list(
            children: [
              for (final s in f)
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(s.folder.name),
                  subtitle: Text(s.documentCount == 1 ? '1 documento' : '${s.documentCount} documentos'),
                  onTap: () => context.push('/folder/${s.folder.id}'),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'rename') _renameFolder(s.folder);
                      if (v == 'delete') _deleteFolder(s.folder);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'rename', child: Text('Renombrar')),
                      PopupMenuItem(value: 'delete', child: Text('Borrar')),
                    ],
                  ),
                ),
              const Divider(height: 1),
            ],
          ),
        SliverPadding(
          // Espacio inferior para que los botones flotantes no tapen la última fila.
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 160),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 200,
              childAspectRatio: 0.68,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            itemCount: d.length,
            itemBuilder: (context, i) => DocumentCard(
              summary: d[i],
              onTap: () => context.push('/doc/${d[i].document.id}'),
              onLongPress: () => showDocumentOptions(context, ref, d[i].document),
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.searching});

  final bool searching;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (searching)
              Icon(Icons.search_off, size: 72, color: theme.colorScheme.outline)
            else
              const Image(image: AssetImage(nuvoraLogo), width: 120, height: 120),
            const SizedBox(height: 16),
            Text(
              searching ? 'Ningún documento coincide' : 'Todavía no hay documentos',
              style: theme.textTheme.titleMedium,
            ),
            if (!searching) ...[
              const SizedBox(height: 8),
              Text(
                'Toca "Escanear" para fotografiar un documento o importa fotos de la galería.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
