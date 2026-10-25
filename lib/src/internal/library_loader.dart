// DynamicLibrary resolution for libpipewire_telephony_native.so.
//
// Search order adapted from https://github.com/jwinarske/bluez_native, which
// is in turn patterned after
// https://github.com/meta-flutter/appstream_dart/blob/main/lib/src/bindings.dart.
// Derived portions are Copyright 2026 Joel Winarske and licensed under
// Apache-2.0; see LICENSES/Apache-2.0.txt. Subsequent modifications are
// Copyright 2026 Jian De and licensed under the package's BSD-3-Clause license.

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

const _libraryName = 'libpipewire_telephony_native.so';

@Native<Pointer<Char> Function()>(
  symbol: 'pwt_library_path',
  assetId:
      'package:pipewire_telephony_native/src/ffi/'
      'pipewire_telephony_native_asset.dart',
)
external Pointer<Char> _nativeLibraryPath();

(DynamicLibrary, String) loadPipeWireTelephonyLibrary() {
  if (!Platform.isLinux) {
    throw UnsupportedError('PipeWire telephony is supported only on Linux');
  }
  final override = Platform.environment['PWT_NATIVE_LIB'];
  if (override != null && override.isNotEmpty) {
    return (DynamicLibrary.open(override), override);
  }

  try {
    final pointer = _nativeLibraryPath();
    if (pointer != nullptr) {
      final path = pointer.cast<Utf8>().toDartString();
      if (path.isNotEmpty) return (DynamicLibrary.open(path), path);
    }
  } catch (_) {
    // The Native Asset is optional for legacy Flutter CMake deployments.
  }

  final executableDirectory = File(Platform.resolvedExecutable).parent.path;
  for (final path in [
    '$executableDirectory/lib/$_libraryName',
    '$executableDirectory/../lib/$_libraryName',
    '$executableDirectory/$_libraryName',
  ]) {
    if (File(path).existsSync()) {
      final absolute = File(path).absolute.path;
      return (DynamicLibrary.open(absolute), absolute);
    }
  }
  throw StateError(
    'Failed to load $_libraryName. Set PWT_NATIVE_LIB to its absolute path.',
  );
}
