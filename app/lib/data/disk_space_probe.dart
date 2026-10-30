import 'disk_space_probe_stub.dart'
    if (dart.library.io) 'disk_space_probe_io.dart'
    as platform;

Future<int?> availableBytesForPath(String path) =>
    platform.availableBytesForPath(path);
