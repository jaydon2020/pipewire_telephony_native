// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';

import 'package:pipewire_telephony_native/pipewire_telephony_native.dart';

final class TelephonyExampleArguments {
  const TelephonyExampleArguments(this.bus, this.values);

  final PipeWireBus bus;
  final List<String> values;
}

TelephonyExampleArguments parseExampleArguments(List<String> args) {
  final values = [...args];
  final system = values.remove('--system');
  final session = values.remove('--session');
  if (system && session) {
    throw const FormatException(
      '--system and --session are mutually exclusive',
    );
  }
  return TelephonyExampleArguments(
    system
        ? PipeWireBus.system
        : session
        ? PipeWireBus.session
        : PipeWireBus.automatic,
    values,
  );
}

Future<void> runTelephonyCli(
  List<String> args,
  Future<void> Function(TelephonyExampleArguments arguments) action,
) async {
  try {
    await action(parseExampleArguments(args));
  } on Object catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  }
}

Future<void> withTelephonyClient(
  PipeWireBus bus,
  FutureOr<void> Function(PipeWireTelephonyClient client) action,
) async {
  final client = PipeWireTelephonyClient(bus: bus);
  try {
    await client.connect();
    await action(client);
  } finally {
    await client.close();
  }
}

void printUsage(String usage, List<String> details) {
  print('Usage: $usage');
  if (details.isEmpty) return;
  print('');
  for (final detail in details) {
    print(detail);
  }
}

void printObjects(PipeWireTelephonyClient client) {
  if (client.gateways.isEmpty) {
    print('(no audio gateways)');
    return;
  }
  for (final gateway in client.gateways) {
    printGateway(gateway);
    for (final call in gateway.calls) {
      printCall(call, indent: '  ');
    }
  }
}

void printGateway(PipeWireAudioGateway gateway) {
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

void printCall(PipeWireCall call, {String indent = ''}) {
  print('${indent}Call: ${call.objectPath}');
  print('$indent  Name:                ${call.name}');
  print('$indent  Line identification: ${call.lineIdentification}');
  print('$indent  Incoming line:       ${call.incomingLine}');
  print('$indent  State:               ${call.rawState}');
  print('$indent  Multiparty:          ${call.multiparty}');
}

PipeWireAudioGateway gatewayAt(PipeWireTelephonyClient client, String path) {
  for (final gateway in client.gateways) {
    if (gateway.objectPath == path) return gateway;
  }
  throw FormatException('Unknown gateway path: $path');
}

PipeWireCall callAt(PipeWireTelephonyClient client, String path) {
  for (final call in client.calls) {
    if (call.objectPath == path) return call;
  }
  throw FormatException('Unknown call path: $path');
}

PipeWireTelephonyTransport transportOf(PipeWireAudioGateway gateway) =>
    gateway.transport ??
    (throw FormatException(
      'Gateway has no SCO transport: ${gateway.objectPath}',
    ));

String argument(List<String> args, int index, String name) {
  if (args.length <= index) throw FormatException('Missing $name');
  return args[index];
}

int volumeArgument(List<String> args, int index) {
  final value = int.tryParse(argument(args, index, 'volume'));
  if (value == null || value < 0 || value > 15) {
    throw const FormatException('Volume must be from 0 to 15');
  }
  return value;
}

int secondsArgument(List<String> args) {
  if (args.isEmpty) return 30;
  if (args.length != 2 || args.first != '--seconds') {
    throw FormatException('Unknown watch argument: ${args.first}');
  }
  final value = int.tryParse(argument(args, 1, 'seconds'));
  if (value == null || value < 1) {
    throw const FormatException('Seconds must be a positive integer');
  }
  return value;
}

Future<void> watchTelephony(
  PipeWireTelephonyClient client,
  Duration duration,
) async {
  printObjects(client);
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
      printGateway(value);
    }),
    client.callAdded.listen(
      (value) => print('call added: ${value.objectPath}'),
    ),
    client.callRemoved.listen(
      (value) => print('call removed: ${value.objectPath}'),
    ),
    client.callChanged.listen((value) {
      print('call changed: ${value.objectPath}');
      printCall(value);
    }),
  ];
  await Future<void>.delayed(duration);
  for (final subscription in subscriptions) {
    await subscription.cancel();
  }
}
