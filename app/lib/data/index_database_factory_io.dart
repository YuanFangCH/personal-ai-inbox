import 'package:path/path.dart' as p;

import 'index_database.dart';
import 'sqlite_index_database.dart';

Future<IndexDatabase> createIndexDatabase(String appSupportPath) async {
  final database = SqliteIndexDatabase(p.join(appSupportPath, 'index.sqlite3'));
  await database.open();
  return database;
}
