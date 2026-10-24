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
      () => hook.validateOperatingSystems(OS.linux, OS.linux),
      returnsNormally,
    );
  });

  test('unsupported host OS is rejected before starting CMake', () {
    expect(
      () => hook.validateOperatingSystems(OS.windows, OS.linux),
      throwsUnsupportedError,
    );
  });

  test('unsupported target OS is rejected before starting CMake', () {
    expect(
      () => hook.validateOperatingSystems(OS.linux, OS.windows),
      throwsUnsupportedError,
    );
  });

  test('the bundled Native Asset loads through the public client', () async {
    final client = PipeWireTelephonyClient(bus: PipeWireBus.session);
    await client.close();
    expect(client.state, PipeWireTelephonyClientState.closed);
  });
}
