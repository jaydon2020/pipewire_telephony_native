import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pipewire_telephony_native/pipewire_telephony_native.dart';
import 'package:flutter_telephony/main.dart';

Future<Process> _startMockService() async {
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

Future<void> _command(Process process, String command) async {
  process.stdin.writeln(command);
  await process.stdin.flush();
}

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  expect(finder, findsWidgets);
}

void main() {
  final integrationAvailable =
      Platform.environment['PWT_MOCK_SERVER'] != null &&
      Platform.environment['PWT_NATIVE_LIB'] != null;

  testWidgets('renders telephony states, failures, and reconnect', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 850));
    var service = (await tester.runAsync(_startMockService))!;
    Future<void> send(String command) async {
      await tester.runAsync(() => _command(service, command));
    }

    addTearDown(() async {
      service.kill(ProcessSignal.sigkill);
      await tester.runAsync(() => service.exitCode);
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(const TelephonyExample(bus: PipeWireBus.session));
    await _pumpUntil(tester, find.text('Ada'));
    expect(find.text('State: incoming'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await send('set-outgoing');
    await _pumpUntil(tester, find.text('State: dialing'));

    await send('set-multiparty');
    await _pumpUntil(tester, find.text('Multiparty: yes'));

    await send('fail-multicall SwapCalls');
    await tester.pump(const Duration(milliseconds: 30));
    await tester.tap(find.byKey(const Key('swap-calls')));
    await _pumpUntil(tester, find.byKey(const Key('error-banner')));
    expect(find.textContaining('NotSupported'), findsOneWidget);

    await send('remove');
    await _pumpUntil(tester, find.byKey(const Key('empty-gateways')));

    await send('quit');
    await tester.runAsync(() => service.exitCode);
    await _pumpUntil(tester, find.text('unavailable'));

    service = (await tester.runAsync(_startMockService))!;
    await tester.tap(find.byKey(const Key('reconnect')));
    await _pumpUntil(tester, find.text('Ada'));

    await tester.binding.setSurfaceSize(const Size(390, 780));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('phone-selector')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 500));
    await send('quit');
    await tester.runAsync(
      () => service.exitCode.timeout(const Duration(seconds: 2)),
    );
  }, skip: !integrationAvailable);
}
