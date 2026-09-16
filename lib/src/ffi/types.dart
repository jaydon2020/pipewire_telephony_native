const pwtProtocolVersion = 1;
const pwtMaxMessageBytes = 1024 * 1024;

const pwtOperations = <String>{
  'refreshGateway',
  'refreshCall',
  'refreshTransport',
  'dial',
  'sendTones',
  'answer',
  'hangup',
  'hangupAll',
  'setSpeakerVolume',
  'setMicrophoneVolume',
  'activate',
  'setRejectSco',
  'swapCalls',
  'releaseAndAnswer',
  'releaseAndSwap',
  'holdAndAnswer',
  'createMultiparty',
};

typedef PwtJsonMap = Map<String, Object?>;

final class PwtTargetIdentity {
  const PwtTargetIdentity({
    required this.clientGeneration,
    required this.objectIncarnation,
    required this.path,
    required this.interface,
  });

  final int clientGeneration;
  final int objectIncarnation;
  final String path;
  final String interface;

  PwtJsonMap toJson() => {
    'clientGeneration': clientGeneration,
    'objectIncarnation': objectIncarnation,
    'path': path,
    'interface': interface,
  };
}

final class PwtRequestArguments {
  const PwtRequestArguments({this.text, this.volume, this.value});

  final String? text;
  final int? volume;
  final bool? value;

  PwtJsonMap toJson() => {'text': text, 'volume': volume, 'value': value};
}

final class PwtRequest {
  const PwtRequest({
    this.version = pwtProtocolVersion,
    required this.requestId,
    required this.operation,
    required this.target,
    this.arguments = const PwtRequestArguments(),
  });

  final int version;
  final int requestId;
  final String operation;
  final PwtTargetIdentity target;
  final PwtRequestArguments arguments;

  PwtJsonMap toJson() => {
    'version': version,
    'requestId': requestId,
    'operation': operation,
    'target': target.toJson(),
    'arguments': arguments.toJson(),
  };
}

final class PwtError {
  const PwtError({
    required this.category,
    required this.name,
    required this.message,
    required this.operation,
    required this.path,
  });

  final String category;
  final String name;
  final String message;
  final String operation;
  final String path;

  PwtJsonMap toJson() => {
    'category': category,
    'name': name,
    'message': message,
    'operation': operation,
    'path': path,
  };
}

final class PwtReply {
  const PwtReply({
    required this.version,
    required this.clientGeneration,
    required this.sequence,
    required this.kind,
    required this.requestId,
    required this.ok,
    required this.error,
  });

  final int version;
  final int clientGeneration;
  final int sequence;
  final String kind;
  final int requestId;
  final bool ok;
  final PwtError? error;
}

final class PwtGatewayProperties {
  const PwtGatewayProperties({
    required this.path,
    required this.incarnation,
    required this.address,
    required this.speakerVolume,
    required this.microphoneVolume,
    required this.changed,
  });

  final String path;
  final int incarnation;
  final String? address;
  final int? speakerVolume;
  final int? microphoneVolume;
  final List<String> changed;

  PwtJsonMap toJson() => {
    'path': path,
    'incarnation': incarnation,
    'address': address,
    'speakerVolume': speakerVolume,
    'microphoneVolume': microphoneVolume,
    'changed': changed,
  };
}

final class PwtCallProperties {
  const PwtCallProperties({
    required this.path,
    required this.gatewayPath,
    required this.incarnation,
    required this.lineIdentification,
    required this.incomingLine,
    required this.name,
    required this.multiparty,
    required this.state,
    required this.changed,
  });

  final String path;
  final String gatewayPath;
  final int incarnation;
  final String? lineIdentification;
  final String? incomingLine;
  final String? name;
  final bool? multiparty;
  final String? state;
  final List<String> changed;

  PwtJsonMap toJson() => {
    'path': path,
    'gatewayPath': gatewayPath,
    'incarnation': incarnation,
    'lineIdentification': lineIdentification,
    'incomingLine': incomingLine,
    'name': name,
    'multiparty': multiparty,
    'state': state,
    'changed': changed,
  };
}

final class PwtTransportProperties {
  const PwtTransportProperties({
    required this.path,
    required this.incarnation,
    required this.state,
    required this.codec,
    required this.rejectSco,
    required this.changed,
  });

  final String path;
  final int incarnation;
  final String? state;
  final int? codec;
  final bool? rejectSco;
  final List<String> changed;

  PwtJsonMap toJson() => {
    'path': path,
    'incarnation': incarnation,
    'state': state,
    'codec': codec,
    'rejectSco': rejectSco,
    'changed': changed,
  };
}

final class PwtStartupSnapshot {
  const PwtStartupSnapshot({
    required this.gateways,
    required this.calls,
    required this.transports,
  });

  final List<PwtGatewayProperties> gateways;
  final List<PwtCallProperties> calls;
  final List<PwtTransportProperties> transports;

  PwtJsonMap toJson() => {
    'gateways': gateways.map((value) => value.toJson()).toList(),
    'calls': calls.map((value) => value.toJson()).toList(),
    'transports': transports.map((value) => value.toJson()).toList(),
  };
}

final class PwtLifecycle {
  const PwtLifecycle({required this.state});

  final String state;

  PwtJsonMap toJson() => {'state': state};
}

final class PwtEventPayload {
  const PwtEventPayload({
    required this.startup,
    required this.lifecycle,
    required this.gateway,
    required this.call,
    required this.transport,
    required this.error,
  });

  final PwtStartupSnapshot? startup;
  final PwtLifecycle? lifecycle;
  final PwtGatewayProperties? gateway;
  final PwtCallProperties? call;
  final PwtTransportProperties? transport;
  final PwtError? error;

  PwtJsonMap toJson() => {
    'startup': startup?.toJson(),
    'lifecycle': lifecycle?.toJson(),
    'gateway': gateway?.toJson(),
    'call': call?.toJson(),
    'transport': transport?.toJson(),
    'error': error?.toJson(),
  };
}

final class PwtEvent {
  const PwtEvent({
    required this.version,
    required this.clientGeneration,
    required this.sequence,
    required this.kind,
    required this.payload,
  });

  final int version;
  final int clientGeneration;
  final int sequence;
  final String kind;
  final PwtEventPayload payload;
}
