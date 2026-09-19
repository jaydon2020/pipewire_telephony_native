// JSON codec for the versioned PipeWire telephony FFI protocol.
//
// The codec organization is adapted from
// https://github.com/jwinarske/bluez_native under Apache-2.0; see
// LICENSES/Apache-2.0.txt. The JSON wire format is specific to this package
// and is serialized by upstream Glaze on the native side.

import 'dart:convert';
import 'dart:typed_data';

import 'types.dart';

final class PwtJsonCodec {
  const PwtJsonCodec();

  Uint8List encodeRequest(PwtRequest request) {
    _validateRequest(request);
    return _encode(request.toJson());
  }

  PwtReply decodeReply(Uint8List bytes) {
    final json = _decode(bytes);
    _validateVersion(json);
    final reply = PwtReply(
      version: _integer(json, 'version'),
      clientGeneration: _positiveInteger(json, 'clientGeneration'),
      sequence: _positiveInteger(json, 'sequence'),
      kind: _string(json, 'kind'),
      requestId: _positiveInteger(json, 'requestId'),
      ok: _boolean(json, 'ok'),
      error: _optionalObject(json, 'error', _error),
    );
    if (reply.kind != 'reply') {
      throw const FormatException('invalid reply kind');
    }
    if (reply.ok == (reply.error != null)) {
      throw const FormatException('reply result and error disagree');
    }
    return reply;
  }

  PwtEvent decodeEvent(Uint8List bytes) {
    final json = _decode(bytes);
    _validateVersion(json);
    final payload = _object(json, 'payload');
    return PwtEvent(
      version: _integer(json, 'version'),
      clientGeneration: _positiveInteger(json, 'clientGeneration'),
      sequence: _positiveInteger(json, 'sequence'),
      kind: _string(json, 'kind'),
      payload: PwtEventPayload(
        startup: _optionalObject(payload, 'startup', _startup),
        lifecycle: _optionalObject(payload, 'lifecycle', _lifecycle),
        gateway: _optionalObject(payload, 'gateway', _gateway),
        call: _optionalObject(payload, 'call', _call),
        transport: _optionalObject(payload, 'transport', _transport),
        error: _optionalObject(payload, 'error', _error),
      ),
    );
  }

  Uint8List _encode(PwtJsonMap value) {
    final bytes = utf8.encode(jsonEncode(value));
    if (bytes.length > pwtMaxMessageBytes) {
      throw const FormatException('message exceeds 1 MiB');
    }
    return Uint8List.fromList(bytes);
  }

  PwtJsonMap _decode(Uint8List bytes) {
    if (bytes.length > pwtMaxMessageBytes) {
      throw const FormatException('message exceeds 1 MiB');
    }
    final Object? value = jsonDecode(utf8.decode(bytes));
    if (value is! Map<String, Object?>) {
      throw const FormatException('message must be a JSON object');
    }
    return value;
  }

  void _validateRequest(PwtRequest request) {
    if (request.version != pwtProtocolVersion) {
      throw const FormatException('unsupported protocol version');
    }
    if (request.requestId <= 0 ||
        request.target.clientGeneration <= 0 ||
        request.target.objectIncarnation <= 0) {
      throw const FormatException('request identity values must be positive');
    }
    if (!request.target.path.startsWith('/') ||
        request.target.interface.isEmpty) {
      throw const FormatException('invalid target');
    }
    if (!pwtOperations.contains(request.operation)) {
      throw const FormatException('unknown operation');
    }
    final volume = request.arguments.volume;
    if (volume != null && (volume < 0 || volume > 255)) {
      throw const FormatException('volume must fit in one byte');
    }
  }
}

void _validateVersion(PwtJsonMap json) {
  if (_integer(json, 'version') != pwtProtocolVersion) {
    throw const FormatException('unsupported protocol version');
  }
}

PwtError _error(PwtJsonMap json) => PwtError(
  category: _string(json, 'category'),
  name: _string(json, 'name'),
  message: _string(json, 'message'),
  operation: _string(json, 'operation'),
  path: _string(json, 'path'),
);

PwtGatewayProperties _gateway(PwtJsonMap json) => PwtGatewayProperties(
  path: _string(json, 'path'),
  incarnation: _positiveInteger(json, 'incarnation'),
  address: _nullableString(json, 'address'),
  speakerVolume: _nullableByte(json, 'speakerVolume'),
  microphoneVolume: _nullableByte(json, 'microphoneVolume'),
  changed: _strings(json, 'changed'),
);

PwtCallProperties _call(PwtJsonMap json) => PwtCallProperties(
  path: _string(json, 'path'),
  gatewayPath: _string(json, 'gatewayPath'),
  incarnation: _positiveInteger(json, 'incarnation'),
  lineIdentification: _nullableString(json, 'lineIdentification'),
  incomingLine: _nullableString(json, 'incomingLine'),
  name: _nullableString(json, 'name'),
  multiparty: _nullableBoolean(json, 'multiparty'),
  state: _nullableString(json, 'state'),
  changed: _strings(json, 'changed'),
);

PwtTransportProperties _transport(PwtJsonMap json) => PwtTransportProperties(
  path: _string(json, 'path'),
  incarnation: _positiveInteger(json, 'incarnation'),
  state: _nullableString(json, 'state'),
  codec: _nullableByte(json, 'codec'),
  rejectSco: _nullableBoolean(json, 'rejectSco'),
  changed: _strings(json, 'changed'),
);

PwtStartupSnapshot _startup(PwtJsonMap json) => PwtStartupSnapshot(
  gateways: _objects(json, 'gateways', _gateway),
  calls: _objects(json, 'calls', _call),
  transports: _objects(json, 'transports', _transport),
);

PwtLifecycle _lifecycle(PwtJsonMap json) =>
    PwtLifecycle(state: _string(json, 'state'));

T? _optionalObject<T>(
  PwtJsonMap json,
  String key,
  T Function(PwtJsonMap) convert,
) {
  final value = json[key];
  if (value == null) return null;
  if (value is! Map<String, Object?>) {
    throw FormatException('$key must be an object or null');
  }
  return convert(value);
}

PwtJsonMap _object(PwtJsonMap json, String key) {
  final value = json[key];
  if (value is! Map<String, Object?>) {
    throw FormatException('$key must be an object');
  }
  return value;
}

List<T> _objects<T>(
  PwtJsonMap json,
  String key,
  T Function(PwtJsonMap) convert,
) {
  final value = json[key];
  if (value is! List<Object?>) {
    throw FormatException('$key must be an array');
  }
  return List.unmodifiable(
    value.map((item) {
      if (item is! Map<String, Object?>) {
        throw FormatException('$key entries must be objects');
      }
      return convert(item);
    }),
  );
}

String _string(PwtJsonMap json, String key) {
  final value = json[key];
  if (value is! String) throw FormatException('$key must be a string');
  return value;
}

String? _nullableString(PwtJsonMap json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) throw FormatException('$key must be a string or null');
  return value;
}

int _integer(PwtJsonMap json, String key) {
  final value = json[key];
  if (value is! int) throw FormatException('$key must be an integer');
  return value;
}

int _positiveInteger(PwtJsonMap json, String key) {
  final value = _integer(json, key);
  if (value <= 0) throw FormatException('$key must be positive');
  return value;
}

int? _nullableByte(PwtJsonMap json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! int || value < 0 || value > 255) {
    throw FormatException('$key must be a byte or null');
  }
  return value;
}

bool _boolean(PwtJsonMap json, String key) {
  final value = json[key];
  if (value is! bool) throw FormatException('$key must be a boolean');
  return value;
}

bool? _nullableBoolean(PwtJsonMap json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! bool) throw FormatException('$key must be a boolean or null');
  return value;
}

List<String> _strings(PwtJsonMap json, String key) {
  final value = json[key];
  if (value is! List<Object?> || value.any((item) => item is! String)) {
    throw FormatException('$key must be a string array');
  }
  return List.unmodifiable(value.cast<String>());
}
