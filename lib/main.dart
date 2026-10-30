import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'app/app.dart';
import 'core/providers.dart';
import 'core/storage/file_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final files = FileStore(root: await getApplicationDocumentsDirectory(), cache: await getTemporaryDirectory());
  runApp(ProviderScope(overrides: [fileStoreProvider.overrideWithValue(files)], child: const App()));
}
