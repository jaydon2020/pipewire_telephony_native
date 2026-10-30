/*
 * Copyright (c) 2026 Jian De Seak jiande2020@gmail.com. All rights reserved.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

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

  test('CMake uses the compiler environment without a toolchain define', () {
    final arguments = hook.cmakeConfigureArguments(
      nativeRoot: '/pkg/native',
      buildDirectory: '/out/cmake/',
      hasNinja: true,
    );
    expect(arguments, contains('-DPWT_HOOK_BUILD=ON'));
    expect(arguments, isNot(contains(startsWith('-DCMAKE_TOOLCHAIN_FILE='))));
    expect(arguments, isNot(contains('-DPWT_REQUIRE_CROSS_COMPILE=ON')));
    expect(arguments, containsAllInOrder(['-G', 'Ninja']));

    final host = hook.cmakeConfigureArguments(
      nativeRoot: '/pkg/native',
      buildDirectory: '/out/cmake/',
      hasNinja: false,
    );
    expect(host, isNot(contains('Ninja')));
  });

  test('the bundled Native Asset loads through the public client', () async {
    final client = PipeWireTelephonyClient(bus: PipeWireBus.session);
    await client.close();
    expect(client.state, PipeWireTelephonyClientState.closed);
  });
}
