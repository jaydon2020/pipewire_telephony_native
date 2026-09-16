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
  addTearDown(() async {
    process.kill(ProcessSignal.sigkill);
    await process.exitCode;
  });
  return process;
}

Future<void> stopMockService(Process process) async {
  process.stdin.writeln('quit');
  await process.stdin.flush();
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
        var gatewayCountAtReady = -1;
        var callCountAtReady = -1;
        final subscription = client.stateChanged.listen(states.add);
        final readySubscription = client.stateChanged.listen((state) {
          if (state == PipeWireTelephonyClientState.ready) {
            gatewayCountAtReady = client.gateways.length;
            callCountAtReady = client.calls.length;
          }
        });

        final firstConnect = client.connect();
        final secondConnect = client.connect();
        expect(identical(firstConnect, secondConnect), isTrue);
        await firstConnect;
        expect(client.state, PipeWireTelephonyClientState.ready);
        expect(client.gateways.single.address, 'AA:BB:CC:DD:EE:FF');
        expect(gatewayCountAtReady, 1);
        expect(client.calls.single.name, 'Ada');
        expect(client.gateways.single.calls.single, same(client.calls.single));
        expect(callCountAtReady, 1);

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
        await readySubscription.cancel();
        await stopMockService(service);
      });

      test('live call and gateway reuse replace object identity', () async {
        final service = await startMockService();
        final client = PipeWireTelephonyClient(bus: PipeWireBus.session);
        await client.connect();
        final original = client.gateways.single;
        final originalCall = client.calls.single;

        var callCacheWasEmptyAtRemoval = false;
        final callRemoved = client.callRemoved.first.then((call) {
          callCacheWasEmptyAtRemoval =
              client.calls.isEmpty && original.calls.isEmpty;
          return call;
        });
        service.stdin.writeln('remove-call');
        await service.stdin.flush();
        expect(
          await callRemoved.timeout(const Duration(seconds: 2)),
          originalCall,
        );
        expect(callCacheWasEmptyAtRemoval, isTrue);
        expect(client.gateways.single, same(original));
        expect(originalCall.isValid, isFalse);

        final callReadded = client.callAdded.first;
        service.stdin.writeln('add-call');
        await service.stdin.flush();
        final callBeforeParentLoss = await callReadded.timeout(
          const Duration(seconds: 2),
        );
        expect(
          callBeforeParentLoss.incarnation,
          greaterThan(originalCall.incarnation),
        );

        var cacheWasEmptyAtRemoval = false;
        final removed = client.gatewayRemoved.first.then((gateway) {
          cacheWasEmptyAtRemoval =
              client.gateways.isEmpty && client.calls.isEmpty;
          return gateway;
        });
        service.stdin.writeln('remove');
        await service.stdin.flush();
        expect(await removed.timeout(const Duration(seconds: 2)), original);
        expect(cacheWasEmptyAtRemoval, isTrue);
        expect(original.isValid, isFalse);
        expect(original.ensureValid, throwsStateError);
        expect(callBeforeParentLoss.isValid, isFalse);
        expect(callBeforeParentLoss.ensureValid, throwsStateError);

        final added = client.gatewayAdded.first;
        service.stdin.writeln('add');
        await service.stdin.flush();
        final replacement = await added.timeout(const Duration(seconds: 2));
        expect(client.gateways.single, same(replacement));
        expect(replacement, isNot(same(original)));
        expect(replacement.incarnation, greaterThan(original.incarnation));

        final callAdded = client.callAdded.first;
        service.stdin.writeln('add-call');
        await service.stdin.flush();
        final replacementCall = await callAdded.timeout(
          const Duration(seconds: 2),
        );
        expect(client.calls.single, same(replacementCall));
        expect(replacement.calls.single, same(replacementCall));
        expect(replacementCall.gateway, same(replacement));
        expect(replacementCall, isNot(same(callBeforeParentLoss)));
        expect(
          replacementCall.incarnation,
          greaterThan(callBeforeParentLoss.incarnation),
        );

        await client.close();
        await stopMockService(service);
      });

      test(
        'partial and invalidated properties preserve value semantics',
        () async {
          final service = await startMockService();
          final client = PipeWireTelephonyClient(bus: PipeWireBus.session);
          await client.connect();
          final gateway = client.gateways.single;
          final call = client.calls.single;

          final gatewayChanged = gateway.propertiesChanged.first;
          final callChanged = call.propertiesChanged.first;
          service.stdin.writeln('change-properties');
          await service.stdin.flush();
          expect(await gatewayChanged, ['SpeakerVolume']);
          expect(
            await callChanged,
            containsAll(['IncomingLine', 'Multiparty', 'State']),
          );
          expect(gateway.speakerVolume, 0);
          expect(gateway.microphoneVolume, 10);
          expect(call.incomingLine, '');
          expect(call.multiparty, isFalse);
          expect(call.rawState, 'future-ringing');
          expect(call.state, PipeWireCallState.unknown);

          final gatewayValues = <int?>[];
          final callNames = <String?>[];
          final refreshed = Completer<void>();
          void completeWhenRefreshed() {
            if (gatewayValues.length >= 2 && callNames.length >= 2) {
              if (!refreshed.isCompleted) refreshed.complete();
            }
          }

          final gatewaySubscription = gateway.propertiesChanged.listen((names) {
            if (names.contains('MicrophoneVolume')) {
              gatewayValues.add(gateway.microphoneVolume);
              completeWhenRefreshed();
            }
          });
          final callSubscription = call.propertiesChanged.listen((names) {
            if (names.contains('Name')) {
              callNames.add(call.name);
              completeWhenRefreshed();
            }
          });
          service.stdin.writeln('invalidate-properties');
          await service.stdin.flush();
          await refreshed.future.timeout(const Duration(seconds: 2));

          expect(gatewayValues, [null, 0]);
          expect(callNames, [null, 'Grace']);
          await gatewaySubscription.cancel();
          await callSubscription.cancel();
          await client.close();
          await stopMockService(service);
        },
      );

      test('disconnected state is terminal without a removal signal', () async {
        final service = await startMockService();
        final client = PipeWireTelephonyClient(bus: PipeWireBus.session);
        await client.connect();
        final call = client.calls.single;
        final removed = client.callRemoved.first;

        service.stdin.writeln('disconnect-call');
        await service.stdin.flush();
        expect(await removed.timeout(const Duration(seconds: 2)), same(call));
        expect(call.rawState, 'disconnected');
        expect(call.state, PipeWireCallState.disconnected);
        expect(call.isValid, isFalse);
        expect(client.calls, isEmpty);
        expect(client.gateways.single.calls, isEmpty);

        await client.close();
        await stopMockService(service);
      });

      test(
        'concurrent scoped refreshes share the async command contract',
        () async {
          final service = await startMockService();
          final client = PipeWireTelephonyClient(bus: PipeWireBus.session);
          await client.connect();
          final gateway = client.gateways.single;
          final call = client.calls.single;
          final gatewayChanged = gateway.propertiesChanged.first;
          final callChanged = call.propertiesChanged.first;

          service.stdin.writeln('prepare-refresh');
          await service.stdin.flush();
          await Future.wait([
            gateway.refresh(),
            gateway.refresh(),
            call.refresh(),
            call.refresh(),
          ]);
          await Future.wait([gatewayChanged, callChanged]);

          expect(gateway.address, '');
          expect(gateway.speakerVolume, 0);
          expect(gateway.microphoneVolume, 0);
          expect(call.lineIdentification, '');
          expect(call.incomingLine, '');
          expect(call.name, '');
          expect(call.multiparty, isFalse);
          expect(call.rawState, 'future-state');
          expect(call.state, PipeWireCallState.unknown);

          await client.refresh();
          await client.close();
          await stopMockService(service);
        },
      );

      test('close completes an in-flight result port exactly once', () async {
        final service = await startMockService();
        final client = PipeWireTelephonyClient(bus: PipeWireBus.session);
        await client.connect();
        service.stdin.writeln('delay-operations');
        await service.stdin.flush();
        await Future<void>.delayed(const Duration(milliseconds: 20));

        final refresh = client.gateways.single.refresh();
        final failedRefresh = expectLater(
          refresh,
          throwsA(
            isA<PipeWireTelephonyException>().having(
              (error) => error.name,
              'name',
              'org.pipewire.Telephony.Error.Closed',
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await client.close();
        await failedRefresh;
        await stopMockService(service);
      });

      test('refresh preserves exact remote errors', () async {
        final service = await startMockService();
        final client = PipeWireTelephonyClient(bus: PipeWireBus.session);
        await client.connect();

        for (final name in [
          'org.pipewire.Telephony.Error.InvalidState',
          'org.pipewire.Telephony.Error.NotSupported',
          'org.pipewire.Telephony.Error.InProgress',
          'org.ofono.Error.Cme',
        ]) {
          service.stdin.writeln('fail-refresh $name');
          await service.stdin.flush();
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await expectLater(
            client.gateways.single.refresh(),
            throwsA(
              isA<PipeWireTelephonyException>()
                  .having((error) => error.category, 'category', 'remote')
                  .having((error) => error.name, 'name', name)
                  .having(
                    (error) => error.message,
                    'message',
                    'mock refresh failure',
                  )
                  .having((error) => error.requestId, 'requestId', isNotNull),
            ),
          );
        }

        await client.close();
        await stopMockService(service);
      });

      test('a timed-out result port does not stop the client', () async {
        final service = await startMockService();
        final client = PipeWireTelephonyClient(
          bus: PipeWireBus.session,
          operationTimeout: const Duration(milliseconds: 50),
        );
        await client.connect();
        service.stdin.writeln('delay-operations');
        await service.stdin.flush();
        await Future<void>.delayed(const Duration(milliseconds: 20));

        await expectLater(
          client.gateways.single.refresh(),
          throwsA(
            isA<PipeWireTelephonyException>()
                .having(
                  (error) => error.name,
                  'name',
                  'org.pipewire.Telephony.Error.Timeout',
                )
                .having((error) => error.requestId, 'requestId', isNotNull),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 550));
        service.stdin.writeln('clear-operation-delay');
        await service.stdin.flush();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await client.gateways.single.refresh();

        await client.close();
        await stopMockService(service);
      });

      test('dial and DTMF enforce their public input contracts', () async {
        final service = await startMockService();
        final client = PipeWireTelephonyClient(bus: PipeWireBus.session);
        await client.connect();
        final gateway = client.gateways.single;
        final maxDial = List.filled(80, '1').join();
        final longDial = List.filled(81, '1').join();

        await gateway.dial('0123456789+*#,ABCD');
        await gateway.dial(maxDial);
        await gateway.sendTones('0123456789*#ABCD');
        await gateway.sendTones('');

        for (final number in ['', longDial, '12 3', 'abc', '1\u00002']) {
          expect(() => gateway.dial(number), throwsArgumentError);
        }
        for (final tones in ['+', ',', 'a', '1\u00002']) {
          expect(() => gateway.sendTones(tones), throwsArgumentError);
        }

        await client.close();
        await stopMockService(service);
      });

      test('answer and hangup commands do not mutate cached calls', () async {
        final service = await startMockService();
        final client = PipeWireTelephonyClient(bus: PipeWireBus.session);
        await client.connect();
        final gateway = client.gateways.single;
        final call = client.calls.single;

        await call.answer();
        await call.hangup();
        await gateway.hangupAll();
        expect(client.calls.single, same(call));
        expect(gateway.calls.single, same(call));
        expect(call.rawState, 'incoming');

        service.stdin.writeln('fail-answer');
        await service.stdin.flush();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await expectLater(
          call.answer(),
          throwsA(
            isA<PipeWireTelephonyException>()
                .having(
                  (error) => error.name,
                  'name',
                  'org.pipewire.Telephony.Error.InvalidState',
                )
                .having(
                  (error) => error.message,
                  'message',
                  'call cannot be answered',
                ),
          ),
        );

        await client.close();
        await stopMockService(service);
      });

      test(
        'volume writes are range checked and confirmed with GetAll',
        () async {
          final service = await startMockService();
          final client = PipeWireTelephonyClient(bus: PipeWireBus.session);
          await client.connect();
          final gateway = client.gateways.single;

          final speakerChanged = gateway.propertiesChanged.firstWhere(
            (names) => names.contains('SpeakerVolume'),
          );
          await gateway.setSpeakerVolume(0);
          await speakerChanged;
          expect(gateway.speakerVolume, 0);

          final microphoneChanged = gateway.propertiesChanged.firstWhere(
            (names) => names.contains('MicrophoneVolume'),
          );
          await gateway.setMicrophoneVolume(15);
          await microphoneChanged;
          expect(gateway.microphoneVolume, 15);

          for (final volume in [-1, 16]) {
            expect(() => gateway.setSpeakerVolume(volume), throwsRangeError);
            expect(() => gateway.setMicrophoneVolume(volume), throwsRangeError);
          }

          service.stdin.writeln('fail-speaker-volume');
          await service.stdin.flush();
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await expectLater(
            gateway.setSpeakerVolume(1),
            throwsA(
              isA<PipeWireTelephonyException>()
                  .having(
                    (error) => error.name,
                    'name',
                    'org.pipewire.Telephony.Error.NotSupported',
                  )
                  .having(
                    (error) => error.message,
                    'message',
                    'speaker volume is unavailable',
                  ),
            ),
          );
          expect(gateway.speakerVolume, 0);

          await client.close();
          await stopMockService(service);
        },
      );

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

        var cacheWasEmptyAtUnavailable = false;
        final unavailable = client.stateChanged.firstWhere((state) {
          if (state != PipeWireTelephonyClientState.unavailable) return false;
          cacheWasEmptyAtUnavailable =
              client.gateways.isEmpty && client.calls.isEmpty;
          return true;
        });
        service.kill(ProcessSignal.sigterm);
        await service.exitCode.timeout(const Duration(seconds: 2));
        await unavailable.timeout(const Duration(seconds: 2));

        expect(client.lastError?.name, contains('ServiceChanged'));
        expect(cacheWasEmptyAtUnavailable, isTrue);
        await expectLater(client.connect(), throwsStateError);
        await client.close();
      });
    },
    skip: integrationAvailable ? false : 'native integration is not configured',
  );
}
