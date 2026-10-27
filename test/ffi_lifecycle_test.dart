/*
 * Copyright (c) 2026 Jian De Seak jiande2020@gmail.com. All rights reserved.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:pipewire_telephony_native/src/ffi/bindings.dart';
import 'package:test/test.dart';

String? findNativeLibrary() {
  final override = Platform.environment['PWT_NATIVE_LIB'];
  if (override != null && File(override).existsSync()) return override;
  const local = 'build/native/libpipewire_telephony_native.so';
  return File(local).existsSync() ? File(local).absolute.path : null;
}

void main() {
  final libraryPath = findNativeLibrary();

  test('generated facade owns the native lifecycle', () {
    final bindings = PwtNativeBindings(DynamicLibrary.open(libraryPath!));
    expect(bindings.abiVersion, PwtNativeBindings.expectedAbiVersion);
    expect(bindings.initializeDartApi(), PwtNativeStatus.ok);
    expect(bindings.initializeDartApi(), PwtNativeStatus.ok);

    final handle = bindings.createClient(0, bus: PwtNativeBus.session);
    expect(bindings.start(handle), PwtNativeStatus.ok);
    expect(bindings.start(handle), PwtNativeStatus.invalidState);
    expect(
      bindings.submit(handle, Uint8List.fromList([123]), 0),
      PwtNativeStatus.protocolError,
    );
    expect(bindings.stop(handle), PwtNativeStatus.ok);
    bindings.destroy(handle);
    bindings.destroy(handle);
    expect(handle.isDestroyed, isTrue);
    bindings.freeNativeBuffer(nullptr);
  }, skip: libraryPath == null ? 'native test library is not built' : false);
}
