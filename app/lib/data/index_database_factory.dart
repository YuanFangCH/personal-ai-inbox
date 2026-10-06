import 'index_database.dart';
import 'index_database_factory_io.dart'
    if (dart.library.js_interop) 'index_database_factory_web.dart'
    as platform;

Future<IndexDatabase> createPlatformIndexDatabase(String appSupportPath) {
  return platform.createIndexDatabase(appSupportPath);
}
