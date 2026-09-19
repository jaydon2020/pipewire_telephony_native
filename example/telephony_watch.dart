import 'telephony_example_utils.dart';

Future<void> main(List<String> args) =>
    runTelephonyCli(args, (arguments) async {
      if (arguments.values.contains('--help')) {
        printUsage(
          'dart run example/telephony_watch.dart '
          '[--system|--session] [--seconds N]',
          const [],
        );
        return;
      }
      final seconds = secondsArgument(arguments.values);
      await withTelephonyClient(
        arguments.bus,
        (client) => watchTelephony(client, Duration(seconds: seconds)),
      );
    });
