/*
 * Copyright (c) 2026 Jian De jiande2020@gmail.com. All rights reserved.
 *
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pipewire_telephony_native/src/ffi/codec.dart';
import 'package:pipewire_telephony_native/src/ffi/types.dart';
import 'package:test/test.dart';

const codec = PwtJsonCodec();

Uint8List fixture(String name) => File('test/fixtures/$name').readAsBytesSync();

Uint8List message(Object? value) =>
    Uint8List.fromList(utf8.encode(jsonEncode(value)));

void main() {
  test('Dart request matches the Glaze request fixture', () {
    const request = PwtRequest(
      requestId: 42,
      operation: 'dial',
      target: PwtTargetIdentity(
        clientGeneration: 7,
        objectIncarnation: 3,
        path: '/org/pipewire/Telephony/ag1',
        interface: 'org.pipewire.Telephony.AudioGateway1',
      ),
      arguments: PwtRequestArguments(text: '+123#'),
    );

    expect(
      jsonDecode(utf8.decode(codec.encodeRequest(request))),
      jsonDecode(utf8.decode(fixture('request_dial.json'))),
    );
  });

  test('decodes structured error reply', () {
    final reply = codec.decodeReply(fixture('reply_error.json'));

    expect(reply.clientGeneration, 7);
    expect(reply.sequence, 8);
    expect(reply.requestId, 42);
    expect(reply.ok, isFalse);
    expect(reply.error?.category, 'dbus');
    expect(reply.error?.name, 'org.pipewire.Telephony.Error.InvalidState');
  });

  test('preserves UTF-8, empty, missing, booleans, and unknown states', () {
    final event = codec.decodeEvent(fixture('event_call.json'));
    final call = event.payload.call!;

    expect(call.name, 'Ada 李');
    expect(call.lineIdentification, '');
    expect(call.incomingLine, isNull);
    expect(call.multiparty, isFalse);
    expect(call.state, 'future-state');
  });

  test('decodes startup and lifecycle payloads with byte properties', () {
    final event = codec.decodeEvent(
      message({
        'version': 1,
        'clientGeneration': 7,
        'sequence': 10,
        'kind': 'startup',
        'payload': {
          'startup': {
            'gateways': [
              {
                'path': '/org/pipewire/Telephony/ag1',
                'incarnation': 3,
                'address': null,
                'speakerVolume': 12,
                'microphoneVolume': 10,
                'changed': <String>[],
              },
            ],
            'calls': <Object?>[],
            'transports': [
              {
                'path': '/org/pipewire/Telephony/ag1',
                'incarnation': 4,
                'state': 'active',
                'codec': 2,
                'rejectSco': false,
                'changed': ['State', 'Codec'],
              },
            ],
          },
          'lifecycle': {'state': 'ready'},
          'gateway': null,
          'call': null,
          'transport': null,
          'error': null,
        },
      }),
    );

    expect(event.payload.startup?.gateways.single.speakerVolume, 12);
    expect(event.payload.startup?.transports.single.codec, 2);
    expect(event.payload.startup?.transports.single.rejectSco, isFalse);
    expect(event.payload.lifecycle?.state, 'ready');
  });

  test('allows additive fields and missing nullable properties', () {
    final event = codec.decodeEvent(
      message({
        'version': 1,
        'clientGeneration': 1,
        'sequence': 1,
        'kind': 'gatewayChanged',
        'futureField': true,
        'payload': {
          'gateway': {
            'path': '/gateway',
            'incarnation': 1,
            'changed': <String>[],
          },
        },
      }),
    );

    expect(event.payload.gateway?.address, isNull);
  });

  test('rejects malformed and wrong-type messages', () {
    expect(
      () => codec.decodeEvent(Uint8List.fromList(utf8.encode('{'))),
      throwsFormatException,
    );
    expect(
      () => codec.decodeReply(
        message({
          'version': 1,
          'clientGeneration': 1,
          'sequence': 1,
          'kind': 'reply',
          'requestId': 'wrong',
          'ok': true,
          'error': null,
        }),
      ),
      throwsFormatException,
    );
  });

  test('rejects unsupported versions and oversized messages', () {
    expect(
      () => codec.decodeEvent(message({'version': 2})),
      throwsFormatException,
    );
    expect(
      () => codec.decodeEvent(Uint8List(pwtMaxMessageBytes + 1)),
      throwsFormatException,
    );
  });

  test('rejects unknown operations and out-of-range bytes', () {
    PwtRequest request(String operation, int volume) => PwtRequest(
      requestId: 1,
      operation: operation,
      target: const PwtTargetIdentity(
        clientGeneration: 1,
        objectIncarnation: 1,
        path: '/gateway',
        interface: 'org.pipewire.Telephony.AudioGateway1',
      ),
      arguments: PwtRequestArguments(volume: volume),
    );

    expect(
      () => codec.encodeRequest(request('arbitraryMethod', 1)),
      throwsFormatException,
    );
    expect(
      () => codec.encodeRequest(request('setSpeakerVolume', 256)),
      throwsFormatException,
    );
  });
}
