import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pipewire_telephony_native/pipewire_telephony_native.dart';
import 'package:test/test.dart';

final class SignalSimulator {
  SignalSimulator(this.process, this.lines);

  final Process process;
  final StreamIterator<String> lines;

  static Future<SignalSimulator> start() async {
    final process = await Process.start(
      Platform.environment['PWT_PYTHON'] ?? 'python3',
      [Platform.environment['PWT_SIGNAL_SERVER']!],
    );
    final lines = StreamIterator(
      process.stdout
          .transform(const SystemEncoding().decoder)
          .transform(const LineSplitter()),
    );
    final simulator = SignalSimulator(process, lines);
    expect(await simulator._nextLine(), 'READY');
    addTearDown(simulator.stop);
    return simulator;
  }

  Future<void> command(String command) async {
    process.stdin.writeln(command);
    await process.stdin.flush();
    expect(await _nextLine(), 'DONE $command');
  }

  Future<String> _nextLine() async {
    if (!await lines.moveNext().timeout(const Duration(seconds: 2))) {
      final error = await process.stderr
          .transform(const SystemEncoding().decoder)
          .join();
      throw StateError('signal simulator exited early: $error');
    }
    return lines.current;
  }

  Future<void> stop() async {
    if (await process.exitCode.timeout(Duration.zero, onTimeout: () => -1) !=
        -1) {
      return;
    }
    process.stdin.writeln('quit');
    await process.stdin.flush();
    await process.exitCode.timeout(const Duration(seconds: 2));
  }
}

void main() {
  final integrationAvailable =
      Platform.environment['PWT_NATIVE_LIB'] != null &&
      Platform.environment['PWT_SIGNAL_SERVER'] != null;

  test(
    'interprets signal types, invalidation, identity, and irrelevant senders',
    () async {
      final simulator = await SignalSimulator.start();
      final client = PipeWireTelephonyClient(bus: PipeWireBus.session);
      addTearDown(client.close);
      await client.connect();

      final gateway = client.gateways.single;
      final call = client.calls.single;
      final transport = gateway.transport!;
      expect(gateway.address, 'AA:BB:CC:DD:EE:FF');
      expect(gateway.speakerVolume, 12);
      expect(gateway.microphoneVolume, 10);
      expect(call.state, PipeWireCallState.incoming);
      expect(call.multiparty, isTrue);
      expect(transport.codec, 2);

      final gatewayChanged = gateway.propertiesChanged.first;
      final callChanged = call.propertiesChanged.first;
      final transportChanged = transport.propertiesChanged.first;
      await simulator.command('edge-properties');

      expect(await gatewayChanged, ['SpeakerVolume', 'MicrophoneVolume']);
      expect(gateway.speakerVolume, isNull);
      expect(gateway.microphoneVolume, 0);
      expect(await transportChanged, ['State', 'Codec', 'RejectSCO']);
      expect(transport.rawState, isNull);
      expect(transport.codec, 255);
      expect(transport.rejectSco, isFalse);
      expect(await callChanged, ['Name', 'Multiparty', 'State']);
      expect(call.name, isNull);
      expect(call.multiparty, isFalse);
      expect(call.rawState, 'future-ringing');
      expect(call.state, PipeWireCallState.unknown);

      final ignoredGatewayEvents = <List<String>>[];
      final ignoredCallEvents = <List<String>>[];
      final gatewaySub = gateway.propertiesChanged.listen(
        ignoredGatewayEvents.add,
      );
      final callSub = call.propertiesChanged.listen(ignoredCallEvents.add);
      await simulator.command('irrelevant-signals');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(ignoredGatewayEvents, isEmpty);
      expect(ignoredCallEvents, isEmpty);
      expect(gateway.microphoneVolume, 0);
      await gatewaySub.cancel();
      await callSub.cancel();

      final afterMalformed = gateway.propertiesChanged.first;
      await simulator.command('malformed-then-valid');
      expect(await afterMalformed, ['MicrophoneVolume']);
      expect(gateway.microphoneVolume, 3);

      var removedCalls = 0;
      final callRemovedSub = client.callRemoved.listen((_) => removedCalls++);
      await simulator.command('remove-call-twice');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(removedCalls, 1);
      expect(call.isValid, isFalse);
      expect(client.calls, isEmpty);

      final replacementCallFuture = client.callAdded.first;
      await simulator.command('add-call');
      final replacementCall = await replacementCallFuture;
      expect(replacementCall, isNot(same(call)));
      expect(replacementCall.incarnation, greaterThan(call.incarnation));
      expect(replacementCall.lineIdentification, '');
      expect(replacementCall.state, PipeWireCallState.waiting);

      await simulator.command('orphan-call');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(client.calls, [same(replacementCall)]);
      await callRemovedSub.cancel();

      var transportGatewayChanges = 0;
      final transportGatewaySub = client.gatewayChanged.listen(
        (_) => transportGatewayChanges++,
      );
      await simulator.command('remove-transport-twice');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(transportGatewayChanges, 1);
      expect(transport.isValid, isFalse);
      expect(gateway.transport, isNull);

      final transportAdded = client.gatewayChanged.first;
      await simulator.command('add-transport');
      expect(await transportAdded, same(gateway));
      final replacementTransport = gateway.transport!;
      expect(replacementTransport, isNot(same(transport)));
      expect(
        replacementTransport.incarnation,
        greaterThan(transport.incarnation),
      );
      expect(gateway.transport, same(replacementTransport));
      expect(transportGatewayChanges, 2);
      await transportGatewaySub.cancel();

      var removedGateways = 0;
      final gatewayRemovedSub = client.gatewayRemoved.listen(
        (_) => removedGateways++,
      );
      await simulator.command('remove-gateway-twice');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(removedGateways, 1);
      expect(gateway.isValid, isFalse);
      expect(replacementCall.isValid, isFalse);
      expect(replacementTransport.isValid, isFalse);
      expect(client.gateways, isEmpty);
      expect(client.calls, isEmpty);
      await gatewayRemovedSub.cancel();
    },
    skip: integrationAvailable ? false : 'native integration is not configured',
  );
}
