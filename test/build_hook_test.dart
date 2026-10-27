/*
 * Copyright (c) 2026 Jian De Seak jiande2020@gmail.com. All rights reserved.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import 'dart:typed_data';

import 'package:code_assets/code_assets.dart';
import 'package:pipewire_telephony_native/pipewire_telephony_native.dart';
import 'package:test/test.dart';

import '../hook/build.dart' as hook;

void main() {
  test('invalid timeouts fail before loading a native client', () {
    for (final timeout in [Duration.zero, const Duration(microseconds: -1)]) {
      expect(
        () => PipeWireTelephonyClient(startupTimeout: timeout),
        throwsArgumentError,
      );
      expect(
        () => PipeWireTelephonyClient(operationTimeout: timeout),
        throwsArgumentError,
      );
    }
    expect(
      () => PipeWireTelephonyClient(
        operationTimeout: const Duration(seconds: 30, microseconds: 1),
      ),
      throwsArgumentError,
    );
  });

  test('Linux host and target are accepted', () {
    expect(
      () => hook.validateBuildTarget(
        OS.linux,
        OS.linux,
        Architecture.arm64,
        Architecture.arm64,
        hasToolchain: false,
      ),
      returnsNormally,
    );
  });

  test('non-Linux host or target is rejected before starting CMake', () {
    for (final (host, target) in [
      (OS.windows, OS.linux),
      (OS.linux, OS.windows),
    ]) {
      expect(
        () => hook.validateBuildTarget(
          host,
          target,
          Architecture.x64,
          Architecture.x64,
          hasToolchain: false,
        ),
        throwsUnsupportedError,
      );
    }
  });

  test('cross-architecture builds require a toolchain', () {
    expect(
      () => hook.validateBuildTarget(
        OS.linux,
        OS.linux,
        Architecture.x64,
        Architecture.arm64,
        hasToolchain: false,
      ),
      throwsUnsupportedError,
    );
    expect(
      () => hook.validateBuildTarget(
        OS.linux,
        OS.linux,
        Architecture.x64,
        Architecture.arm64,
        hasToolchain: true,
      ),
      returnsNormally,
    );
  });

  test('cross-build CMake arguments use the supplied toolchain', () {
    final toolchain = Uri.file('/opt/agl/toolchain.cmake');
    final cross = hook.cmakeConfigureArguments(
      nativeRoot: '/pkg/native',
      buildDirectory: '/out/cmake/',
      hostArchitecture: Architecture.x64,
      targetArchitecture: Architecture.arm64,
      toolchainUri: toolchain,
      hasNinja: true,
    );
    expect(cross, contains('-DCMAKE_TOOLCHAIN_FILE=/opt/agl/toolchain.cmake'));
    expect(cross, contains('-DPWT_REQUIRE_CROSS_COMPILE=ON'));
    expect(cross, contains('-DPWT_HOOK_BUILD=ON'));
    expect(cross, containsAllInOrder(['-G', 'Ninja']));

    final host = hook.cmakeConfigureArguments(
      nativeRoot: '/pkg/native',
      buildDirectory: '/out/cmake/',
      hostArchitecture: Architecture.x64,
      targetArchitecture: Architecture.x64,
      toolchainUri: null,
      hasNinja: false,
    );
    expect(host, isNot(contains('-DPWT_REQUIRE_CROSS_COMPILE=ON')));
    expect(host, isNot(contains('Ninja')));
  });

  test('ELF header must match the target architecture', () {
    Uint8List elf64(int machine) {
      final bytes = Uint8List(64)..setAll(0, [0x7f, 0x45, 0x4c, 0x46, 2, 1, 1]);
      ByteData.sublistView(bytes)
        ..setUint16(16, 3, Endian.little)
        ..setUint16(18, machine, Endian.little);
      return bytes;
    }

    expect(
      () => hook.validateElfHeader(elf64(62), Architecture.x64),
      returnsNormally,
    );
    expect(
      () => hook.validateElfHeader(elf64(62), Architecture.arm64),
      throwsStateError,
    );
    expect(
      () => hook.validateElfHeader(Uint8List(64), Architecture.x64),
      throwsStateError,
    );
  });

  test('the bundled Native Asset loads through the public client', () async {
    final client = PipeWireTelephonyClient(bus: PipeWireBus.session);
    await client.close();
    expect(client.state, PipeWireTelephonyClientState.closed);
  });
}
