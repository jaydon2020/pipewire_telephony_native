import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pipewire_telephony_native/pipewire_telephony_native.dart';
import 'package:test/test.dart';

Future<Process> startMockService() async {
  final executable = Platform.environment['PWT_MOCK_SERVER'];
  if (executable == null) throw StateError('PWT_MOCK_SERVER is not set');
  final process = await Process.start(executable, const []);
  final ready = await process.stdout
      .transform(const SystemEncoding().decoder)
      .transform(const LineSplitter())
      .first
      .timeout(const Duration(seconds: 2));
  if (ready != 'READY') throw StateError('mock service failed: $ready');
  return process;
}

Future<void> stopMockService(Process process) async {
  process.kill(ProcessSignal.sigterm);
  await process.exitCode.timeout(const Duration(seconds: 2));
}

void main() {
  final integrationAvailable =
      Platform.environment['PWT_MOCK_SERVER'] != null &&
      Platform.environment['PWT_NATIVE_LIB'] != null;
  group(
    'native client lifecycle',
    () {
      test('connect and close are shared and idempotent', () async {
        final service = await startMockService();
        final client = PipeWireTelephonyClient(bus: PipeWireBus.session);
        final states = <PipeWireTelephonyClientState>[];
        final subscription = client.stateChanged.listen(states.add);

        final firstConnect = client.connect();
        final secondConnect = client.connect();
        expect(identical(firstConnect, secondConnect), isTrue);
        await firstConnect;
        expect(client.state, PipeWireTelephonyClientState.ready);

        final firstClose = client.close();
        final secondClose = client.close();
        expect(identical(firstClose, secondClose), isTrue);
        await firstClose;
        expect(client.state, PipeWireTelephonyClientState.closed);
        expect(
          states,
          containsAllInOrder([
            PipeWireTelephonyClientState.connecting,
            PipeWireTelephonyClientState.ready,
            PipeWireTelephonyClientState.closing,
            PipeWireTelephonyClientState.closed,
          ]),
        );
        await subscription.cancel();
        await stopMockService(service);
      });

      test('missing service has a bounded unavailable result', () async {
        final client = PipeWireTelephonyClient(
          bus: PipeWireBus.session,
          startupTimeout: const Duration(seconds: 2),
        );
        await expectLater(
          client.connect(),
          throwsA(isA<PipeWireTelephonyException>()),
        );
        expect(client.state, PipeWireTelephonyClientState.unavailable);
        expect(client.lastError?.name, isNotEmpty);
        await client.close();
      });

      test(
        'close during startup completes without waiting for readiness',
        () async {
          final client = PipeWireTelephonyClient(
            bus: PipeWireBus.session,
            startupTimeout: const Duration(seconds: 2),
          );
          final connecting = client.connect();
          final failedConnect = expectLater(connecting, throwsA(anything));
          await client.close();
          await failedConnect;
          expect(client.state, PipeWireTelephonyClientState.closed);
        },
      );

      test('owner loss invalidates the client generation', () async {
        final service = await startMockService();
        final client = PipeWireTelephonyClient(bus: PipeWireBus.session);
        await client.connect();

        final unavailable = client.stateChanged.firstWhere(
          (state) => state == PipeWireTelephonyClientState.unavailable,
        );
        await stopMockService(service);
        await unavailable.timeout(const Duration(seconds: 2));

        expect(client.lastError?.name, contains('ServiceChanged'));
        await expectLater(client.connect(), throwsStateError);
        await client.close();
      });
    },
    skip: integrationAvailable ? false : 'native integration is not configured',
  );
}
