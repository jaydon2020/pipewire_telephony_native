import 'dart:ffi';
import 'dart:io';

import 'package:pipewire_telephony_native/pipewire_telephony_native.dart';

Future<void> main(List<String> arguments) async {
  for (final path in arguments) {
    DynamicLibrary.open(path);
  }
  Directory.current =
      Platform.environment['PWT_TEST_WORKING_DIRECTORY'] ??
      Directory.systemTemp.path;
  final client = PipeWireTelephonyClient(bus: PipeWireBus.session);
  await client.close();
  stdout.writeln('bundled telephony library loaded');
}
