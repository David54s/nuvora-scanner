import 'package:drift/drift.dart';

import '../imaging/page_filter.dart';
import '../imaging/paper_size.dart';
import '../imaging/quad.dart';

class Folders extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  // Permite anidar; la interfaz de la fase 1 usa un solo nivel.
  IntColumn get parentId => integer().nullable().references(Folders, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

class Documents extends Table {
  IntColumn get id => integer().autoIncrement()();
  // Al borrar una carpeta sus documentos pasan a la raíz en vez de perderse.
  IntColumn get folderId => integer().nullable().references(Folders, #id, onDelete: KeyAction.setNull)();
  TextColumn get title => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('ScanPage')
@TableIndex(name: 'pages_document_idx', columns: {#documentId, #orderIndex})
class Pages extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get documentId => integer().references(Documents, #id, onDelete: KeyAction.cascade)();

  /// Nombre de la carpeta de archivos de la página (`pages/<uuid>/`).
  TextColumn get uuid => text().unique()();
  IntColumn get orderIndex => integer()();

  // Rutas relativas al directorio de documentos de la app.
  TextColumn get originalPath => text()();
  TextColumn get processedPath => text()();
  TextColumn get thumbPath => text()();

  TextColumn get quad => text().map(const QuadConverter())();
  TextColumn get filter => textEnum<PageFilter>()();
  IntColumn get rotation => integer().withDefault(const Constant(0))();

  /// Tamaño de papel elegido (puede ser `auto`). Las páginas creadas antes de
  /// la versión 2 del esquema conservan sus proporciones (`original`).
  TextColumn get paper => textEnum<PaperSize>().withDefault(Constant(PaperSize.original.name))();

  /// Sube con cada re-render; forma parte del nombre de los archivos
  /// procesados para que la caché de imágenes de Flutter no muestre la anterior.
  IntColumn get revision => integer().withDefault(const Constant(0))();
  IntColumn get width => integer()();
  IntColumn get height => integer()();

  /// Reservado para OCR (fase 2, con una tabla FTS5).
  TextColumn get ocrText => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

class QuadConverter extends TypeConverter<Quad, String> {
  const QuadConverter();

  @override
  Quad fromSql(String fromDb) => Quad.fromJson(fromDb);

  @override
  String toSql(Quad value) => value.toJson();
}
