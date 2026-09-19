// DynamicLibrary resolution for libpipewire_telephony_native.so.
//
// Search order adapted from https://github.com/jwinarske/bluez_native, which
// is in turn patterned after
// https://github.com/meta-flutter/appstream_dart/blob/main/lib/src/bindings.dart.
// Both upstream projects are licensed under Apache-2.0; see
// LICENSES/Apache-2.0.txt.

import 'dart:ffi';
import 'dart:io';

const _libraryName = 'libpipewire_telephony_native.so';

(DynamicLibrary, String) loadPipeWireTelephonyLibrary() {
  if (!Platform.isLinux) {
    throw UnsupportedError('PipeWire telephony is supported only on Linux');
  }
  final override = Platform.environment['PWT_NATIVE_LIB'];
  if (override != null && override.isNotEmpty) {
    return (DynamicLibrary.open(override), override);
  }

  try {
    return (DynamicLibrary.open(_libraryName), _libraryName);
  } on ArgumentError {
    // Continue with paths that survive relocated Flutter bundles.
  }

  final sibling = _findLoadedLibrarySibling();
  if (sibling != null) {
    return (DynamicLibrary.open(sibling), sibling);
  }

  final executableDirectory = File(Platform.resolvedExecutable).parent.path;
  for (final path in [
    '$executableDirectory/lib/$_libraryName',
    '$executableDirectory/$_libraryName',
    '${Directory.current.path}/build/native/$_libraryName',
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

String? _findLoadedLibrarySibling() {
  try {
    final directories = <String>{};
    for (final line in File('/proc/self/maps').readAsLinesSync()) {
      final path = line.substring(line.lastIndexOf(' ') + 1).trim();
      if (!path.startsWith('/')) continue;
      final directory = File(path).parent.path;
      if (directories.add(directory)) {
        final candidate = '$directory/$_libraryName';
        if (File(candidate).existsSync()) return candidate;
      }
    }
  } on FileSystemException {
    return null;
  }
  return null;
}
