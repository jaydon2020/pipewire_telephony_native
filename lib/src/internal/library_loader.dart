// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2026 Joel Winarske <joel.winarske@gmail.com>
// SPDX-FileCopyrightText: 2026 Jian De

// DynamicLibrary resolution for libpipewire_telephony_native.so.
//
// Search order adapted from https://github.com/jwinarske/bluez_native, which
// is in turn patterned after
// https://github.com/meta-flutter/appstream_dart/blob/main/lib/src/bindings.dart.
// Both upstream projects are licensed under Apache-2.0; see
// LICENSES/Apache-2.0.txt.

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

  final errors = <String>[];
  try {
    return (DynamicLibrary.open(_libraryName), _libraryName);
  } catch (error) {
    errors.add('dlopen($_libraryName): $error');
  }

  final sibling = _findSiblingOfLoadedLibrary(_libraryName);
  if (sibling != null) {
    try {
      return (DynamicLibrary.open(sibling), sibling);
    } catch (error) {
      errors.add('dlopen($sibling): $error');
    }
  }

  try {
    final pointer = _nativeLibraryPath();
    if (pointer != nullptr) {
      final path = pointer.cast<Utf8>().toDartString();
      if (path.isNotEmpty) return (DynamicLibrary.open(path), path);
    }
  } catch (error) {
    errors.add('Native Asset resolution: $error');
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
    'Failed to load $_libraryName. Set PWT_NATIVE_LIB to its absolute path.\n'
    'Errors:\n${errors.join('\n')}',
  );
}

/// Finds [libraryName] beside Flutter libraries already mapped by the embedder.
String? _findSiblingOfLoadedLibrary(String libraryName) {
  try {
    final maps = File('/proc/self/maps');
    if (!maps.existsSync()) return null;
    final directories = <String>{};
    for (final line in maps.readAsLinesSync()) {
      final pathStart = line.indexOf('/');
      if (pathStart < 0) continue;
      var path = line.substring(pathStart).trim();
      if (path.endsWith(' (deleted)')) {
        path = path.substring(0, path.length - ' (deleted)'.length);
      }
      final file = File(path);
      final basename = file.uri.pathSegments.last;
      final directory = file.parent.path;
      if (basename != 'libapp.so' && !basename.startsWith('libflutter_')) {
        continue;
      }
      if (!directories.add(directory)) continue;
      final candidate = '$directory/$libraryName';
      if (File(candidate).existsSync()) return candidate;
    }
  } on FileSystemException {
    return null;
  }
  return null;
}
