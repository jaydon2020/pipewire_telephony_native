/*
 * Copyright (c) 2026 Jian De jiande2020@gmail.com. All rights reserved.
 *
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

import 'dart:convert';
import 'dart:io';

import 'package:pipewire_telephony_native/pipewire_telephony_native.dart';
import 'package:test/test.dart';

Future<Process> startMock(String address) async {
  final executable = Platform.environment['PWT_MOCK_SERVER'];
  if (executable == null) throw StateError('PWT_MOCK_SERVER is not set');
  final process = await Process.start(
    executable,
    const [],
    environment: {'DBUS_SESSION_BUS_ADDRESS': address},
  );
  final ready = await process.stdout
      .transform(const SystemEncoding().decoder)
      .transform(const LineSplitter())
      .first
      .timeout(const Duration(seconds: 2));
  if (ready != 'READY') throw StateError('mock service failed: $ready');
  addTearDown(() async {
    process.kill(ProcessSignal.sigkill);
    await process.exitCode;
  });
  return process;
}

void main() {
  final integrationAvailable =
      Platform.environment['PWT_MOCK_SERVER'] != null &&
      Platform.environment['PWT_NATIVE_LIB'] != null &&
      Platform.environment['PWT_AUTO_SYSTEM_BUS_ADDRESS'] != null;
  final unreachableSession =
      Platform.environment['PWT_AUTO_UNREACHABLE_SESSION'] == '1';

  test(
    'automatic mode prefers the session bus',
    () async {
      final service = await startMock(
        Platform.environment['DBUS_SESSION_BUS_ADDRESS']!,
      );
      final client = PipeWireTelephonyClient();

      await client.connect();

      expect(client.state, PipeWireTelephonyClientState.ready);
      expect(client.gateways.single.address, 'AA:BB:CC:DD:EE:FF');
      await client.close();
      service.stdin.writeln('quit');
      await service.stdin.flush();
      await service.exitCode.timeout(const Duration(seconds: 2));
    },
    skip: integrationAvailable && !unreachableSession
        ? false
        : 'session bus integration environment absent',
  );

  test(
    'automatic mode falls back from an empty session bus to the system bus',
    () async {
      final service = await startMock(
        Platform.environment['PWT_AUTO_SYSTEM_BUS_ADDRESS']!,
      );
      final client = PipeWireTelephonyClient();

      await client.connect();

      expect(client.state, PipeWireTelephonyClientState.ready);
      expect(client.gateways.single.address, 'AA:BB:CC:DD:EE:FF');
      await client.close();
      service.stdin.writeln('quit');
      await service.stdin.flush();
      await service.exitCode.timeout(const Duration(seconds: 2));
    },
    skip: integrationAvailable
        ? false
        : 'native integration environment absent',
  );
}
