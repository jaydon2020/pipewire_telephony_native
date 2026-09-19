// ignore_for_file: avoid_print

import 'telephony_example_utils.dart';

Future<void> main(List<String> args) =>
    runTelephonyCli(args, (arguments) async {
      if (arguments.values.contains('--help')) {
        printUsage(
          'dart run example/telephony_list.dart [--system|--session]',
          const [],
        );
        return;
      }
      if (arguments.values.isNotEmpty) {
        throw FormatException('Unknown argument: ${arguments.values.first}');
      }
      await withTelephonyClient(arguments.bus, printObjects);
    });
