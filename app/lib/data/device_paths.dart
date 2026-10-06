import 'device_paths_io.dart'
    if (dart.library.js_interop) 'device_paths_web.dart'
    as platform;

Future<String> appSupportPath() => platform.appSupportPath();
