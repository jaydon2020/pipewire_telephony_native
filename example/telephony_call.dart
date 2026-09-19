// ignore_for_file: avoid_print

import 'telephony_example_utils.dart';

Future<void> main(List<String> args) =>
    runTelephonyCli(args, (arguments) async {
      if (arguments.values.length < 2 || arguments.values.contains('--help')) {
        _printUsage();
        return;
      }
      await withTelephonyClient(arguments.bus, (client) async {
        final call = callAt(client, arguments.values[0]);
        final command = arguments.values[1];
        switch (command) {
          case 'props':
            await call.refresh();
            printCall(call);
            return;
          case 'answer':
            await call.answer();
          case 'hangup':
            await call.hangup();
          default:
            throw FormatException('Unknown call command: $command');
        }
        print('Completed $command on ${call.objectPath}.');
      });
    });

void _printUsage() {
  printUsage(
    'dart run example/telephony_call.dart '
    '[--system|--session] <call_path> <command>',
    const ['Commands: props | answer | hangup'],
  );
}
