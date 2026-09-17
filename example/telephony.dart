// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';

import 'package:pipewire_telephony_native/pipewire_telephony_native.dart';

Future<void> main(List<String> args) async {
  final arguments = [...args];
  final system = arguments.remove('--system');
  final session = arguments.remove('--session');
  if (system && session) {
    stderr.writeln('--system and --session are mutually exclusive');
    exitCode = 1;
    return;
  }
  final bus = system
      ? PipeWireBus.system
      : session
      ? PipeWireBus.session
      : PipeWireBus.automatic;
  if (arguments.isEmpty || arguments.contains('--help')) {
    _printUsage();
    return;
  }

  final client = PipeWireTelephonyClient(bus: bus);
  try {
    await client.connect();
    switch (arguments.first) {
      case 'list':
        _printObjects(client);
      case 'watch':
        await _watch(client, _seconds(arguments));
      case 'gateway':
        await _gatewayCommand(client, arguments);
      case 'call':
        await _callCommand(client, arguments);
      default:
        throw FormatException('Unknown command: ${arguments.first}');
    }
  } on Object catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  } finally {
    await client.close();
  }
}

Future<void> _gatewayCommand(
  PipeWireTelephonyClient client,
  List<String> args,
) async {
  if (args.length < 3) throw const FormatException('Missing gateway command');
  final gateway = _gateway(client, args[1]);
  final command = args[2];
  switch (command) {
    case 'props':
      await gateway.refresh();
      _printGateway(gateway);
      return;
    case 'dial':
      await gateway.dial(_argument(args, 3, 'number'));
    case 'tones':
      await gateway.sendTones(_argument(args, 3, 'tones'));
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
      await gateway.setSpeakerVolume(_volume(args));
    case 'microphone':
      await gateway.setMicrophoneVolume(_volume(args));
    case 'activate-sco':
      await _transport(gateway).activate();
    case 'reject-sco':
      await _transport(gateway).setRejectSco(switch (_argument(
        args,
        3,
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
}

Future<void> _callCommand(
  PipeWireTelephonyClient client,
  List<String> args,
) async {
  if (args.length < 3) throw const FormatException('Missing call command');
  final call = _call(client, args[1]);
  switch (args[2]) {
    case 'props':
      await call.refresh();
      _printCall(call);
      return;
    case 'answer':
      await call.answer();
    case 'hangup':
      await call.hangup();
    default:
      throw FormatException('Unknown call command: ${args[2]}');
  }
  print('Completed ${args[2]} on ${call.objectPath}.');
}

Future<void> _watch(PipeWireTelephonyClient client, int seconds) async {
  _printObjects(client);
  final subscriptions = <StreamSubscription<Object?>>[
    client.stateChanged.listen((state) => print('client: ${state.name}')),
    client.gatewayAdded.listen(
      (value) => print('gateway added: ${value.objectPath}'),
    ),
    client.gatewayRemoved.listen(
      (value) => print('gateway removed: ${value.objectPath}'),
    ),
    client.gatewayChanged.listen((value) {
      print('gateway changed: ${value.objectPath}');
      _printGateway(value);
    }),
    client.callAdded.listen(
      (value) => print('call added: ${value.objectPath}'),
    ),
    client.callRemoved.listen(
      (value) => print('call removed: ${value.objectPath}'),
    ),
    client.callChanged.listen((value) {
      print('call changed: ${value.objectPath}');
      _printCall(value);
    }),
  ];
  await Future<void>.delayed(Duration(seconds: seconds));
  for (final subscription in subscriptions) {
    await subscription.cancel();
  }
}

void _printObjects(PipeWireTelephonyClient client) {
  if (client.gateways.isEmpty) {
    print('(no audio gateways)');
    return;
  }
  for (final gateway in client.gateways) {
    _printGateway(gateway);
    for (final call in gateway.calls) {
      _printCall(call, indent: '  ');
    }
  }
}

void _printGateway(PipeWireAudioGateway gateway) {
  print('Gateway: ${gateway.objectPath}');
  print('  Address:           ${gateway.address}');
  print('  Speaker volume:    ${gateway.speakerVolume}');
  print('  Microphone volume: ${gateway.microphoneVolume}');
  final transport = gateway.transport;
  if (transport == null) {
    print('  SCO transport:     unavailable');
  } else {
    print('  SCO state:         ${transport.rawState}');
    print('  SCO codec:         ${transport.codec}');
    print('  Reject SCO:        ${transport.rejectSco}');
  }
}

void _printCall(PipeWireCall call, {String indent = ''}) {
  print('${indent}Call: ${call.objectPath}');
  print('$indent  Name:                ${call.name}');
  print('$indent  Line identification: ${call.lineIdentification}');
  print('$indent  Incoming line:       ${call.incomingLine}');
  print('$indent  State:               ${call.rawState}');
  print('$indent  Multiparty:          ${call.multiparty}');
}

PipeWireAudioGateway _gateway(PipeWireTelephonyClient client, String path) {
  for (final gateway in client.gateways) {
    if (gateway.objectPath == path) return gateway;
  }
  throw FormatException('Unknown gateway path: $path');
}

PipeWireCall _call(PipeWireTelephonyClient client, String path) {
  for (final call in client.calls) {
    if (call.objectPath == path) return call;
  }
  throw FormatException('Unknown call path: $path');
}

PipeWireTelephonyTransport _transport(PipeWireAudioGateway gateway) =>
    gateway.transport ??
    (throw FormatException(
      'Gateway has no SCO transport: ${gateway.objectPath}',
    ));

String _argument(List<String> args, int index, String name) {
  if (args.length <= index) throw FormatException('Missing $name');
  return args[index];
}

int _volume(List<String> args) {
  final value = int.tryParse(_argument(args, 3, 'volume'));
  if (value == null || value < 0 || value > 15) {
    throw const FormatException('Volume must be from 0 to 15');
  }
  return value;
}

int _seconds(List<String> args) {
  final index = args.indexOf('--seconds');
  if (index == -1) return 30;
  final value = int.tryParse(_argument(args, index + 1, 'seconds'));
  if (value == null || value < 1) {
    throw const FormatException('Seconds must be a positive integer');
  }
  return value;
}

void _printUsage() {
  print(
    'Usage: dart run example/telephony.dart [--system|--session] <command>',
  );
  print('');
  print('Commands:');
  print('  list');
  print('  watch [--seconds N]');
  print('  gateway <path> props|dial|tones|hangup-all|swap-calls');
  print('    release-and-answer|release-and-swap|hold-and-answer');
  print('    create-multiparty|speaker|microphone|activate-sco|reject-sco');
  print('  call <path> props|answer|hangup');
}
