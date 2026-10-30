import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers.dart';
import '../../../../core/ui/format.dart';
import '../../data/library_repository.dart';

class DocumentCard extends ConsumerWidget {
  const DocumentCard({super.key, required this.summary, required this.onTap, required this.onLongPress});

  final DocumentSummary summary;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final files = ref.watch(fileStoreProvider);
    final theme = Theme.of(context);
    final cover = summary.coverThumbPath;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ColoredBox(
                color: theme.colorScheme.surfaceContainerHighest,
                child: cover == null
                    ? const Icon(Icons.description_outlined, size: 48)
                    : Image.file(
                        File(files.abs(cover)),
                        fit: BoxFit.cover,
                        cacheWidth: 360,
                        errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    summary.document.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${pagesLabel(summary.pageCount)} · ${formatDateTime(summary.document.updatedAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
