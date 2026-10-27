/*
 * Copyright (c) 2026 Jian De Seak jiande2020@gmail.com. All rights reserved.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import 'dart:io';

import 'package:pipewire_telephony_native/pipewire_telephony_native.dart';
import 'package:test/test.dart';

void main() {
  final integrationAvailable =
      Platform.environment['PWT_NATIVE_LIB'] != null &&
      Platform.environment['DBUS_SESSION_BUS_ADDRESS'] != null;
  test(
    'access denial is distinct from a missing service',
    () async {
      final client = PipeWireTelephonyClient(
        bus: PipeWireBus.session,
        startupTimeout: const Duration(seconds: 2),
      );

      await expectLater(
        client.connect(),
        throwsA(
          isA<PipeWireTelephonyException>().having(
            (error) => error.name,
            'name',
            contains('AccessDenied'),
          ),
        ),
      );
      expect(client.state, PipeWireTelephonyClientState.unavailable);
      await client.close();
    },
    skip: integrationAvailable ? false : 'native integration is not configured',
  );
}
