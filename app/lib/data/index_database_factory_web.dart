import 'index_database.dart';
import 'memory_index_database.dart';

Future<IndexDatabase> createIndexDatabase(String appSupportPath) async {
  final database = MemoryIndexDatabase();
  await database.open();
  return database;
}
