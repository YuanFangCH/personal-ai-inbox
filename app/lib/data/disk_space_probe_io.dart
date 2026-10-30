import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

const _androidChannel = MethodChannel(
  'com.yuanfang.aitext.personal_ai_inbox/share',
);

Future<int?> availableBytesForPath(String path) async {
  if (Platform.isAndroid) {
    return _androidChannel.invokeMethod<int>('getAvailableSpaceBytes', {
      'path': path,
    });
  }
  if (Platform.isWindows) return _windowsAvailableBytes(path);
  return null;
}

int _windowsAvailableBytes(String path) {
  final library = ffi.DynamicLibrary.open('kernel32.dll');
  final getDiskSpace = library
      .lookupFunction<_GetDiskFreeSpaceNative, _GetDiskFreeSpaceDart>(
        'GetDiskFreeSpaceExW',
      );
  final widePath = path.toNativeUtf16();
  final available = calloc<ffi.Uint64>();
  try {
    final succeeded = getDiskSpace(
      widePath,
      available,
      ffi.nullptr,
      ffi.nullptr,
    );
    if (succeeded == 0) {
      throw FileSystemException('无法读取磁盘剩余空间', path);
    }
    return available.value;
  } finally {
    calloc.free(widePath);
    calloc.free(available);
  }
}

typedef _GetDiskFreeSpaceNative = ffi.Int32 Function(
  ffi.Pointer<Utf16>,
  ffi.Pointer<ffi.Uint64>,
  ffi.Pointer<ffi.Uint64>,
  ffi.Pointer<ffi.Uint64>,
);
typedef _GetDiskFreeSpaceDart = int Function(
  ffi.Pointer<Utf16>,
  ffi.Pointer<ffi.Uint64>,
  ffi.Pointer<ffi.Uint64>,
  ffi.Pointer<ffi.Uint64>,
);
