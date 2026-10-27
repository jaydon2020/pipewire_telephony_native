/*
 * Copyright (c) 2026 Jian De Seak jiande2020@gmail.com. All rights reserved.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

// ignore_for_file: avoid_print

import 'telephony_example_utils.dart';

Future<void> main(List<String> args) => runTelephonyCli(args, (
  arguments,
) async {
  if (arguments.values.length < 2 || arguments.values.contains('--help')) {
    _printUsage();
    return;
  }
  await withTelephonyClient(arguments.bus, (client) async {
    final gateway = gatewayAt(client, arguments.values[0]);
    final command = arguments.values[1];
    switch (command) {
      case 'props':
        await gateway.refresh();
        printGateway(gateway);
        return;
      case 'dial':
        await gateway.dial(argument(arguments.values, 2, 'number'));
      case 'tones':
        await gateway.sendTones(argument(arguments.values, 2, 'tones'));
      case 'hangup-all':
        await gateway.hangupAll();
      case 'swap-calls':
        await gateway.swapCalls();
      case 'release-and-answer':
        await gateway.releaseAndAnswer();
      case 'release-and-swap':
        await gateway.releaseAndSwap();
      case 'hold-and-answer':
        await gateway.holdAndAnswer();
      case 'create-multiparty':
        await gateway.createMultiparty();
      case 'speaker':
        await gateway.setSpeakerVolume(volumeArgument(arguments.values, 2));
      case 'microphone':
        await gateway.setMicrophoneVolume(volumeArgument(arguments.values, 2));
      case 'activate-sco':
        await transportOf(gateway).activate();
      case 'reject-sco':
        await transportOf(gateway).setRejectSco(switch (argument(
          arguments.values,
          2,
          'true or false',
        )) {
          'true' => true,
          'false' => false,
          _ => throw const FormatException('reject-sco expects true or false'),
        });
      default:
        throw FormatException('Unknown gateway command: $command');
    }
    print('Completed $command on ${gateway.objectPath}.');
  });
});

void _printUsage() {
  printUsage(
    'dart run example/telephony_gateway.dart '
    '[--system|--session] <gateway_path> <command>',
    const [
      'Commands:',
      '  props',
      '  dial <number>',
      '  tones <tones>',
      '  hangup-all | swap-calls | release-and-answer | release-and-swap',
      '  hold-and-answer | create-multiparty',
      '  speaker <0..15> | microphone <0..15>',
      '  activate-sco | reject-sco <true|false>',
    ],
  );
}
