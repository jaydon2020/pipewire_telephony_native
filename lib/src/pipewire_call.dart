/*
 * Copyright (c) 2026 Jian De Seak jiande2020@gmail.com. All rights reserved.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

part of 'pipewire_telephony_client.dart';

/// A discovered `org.pipewire.Telephony.Call1` object.
final class PipeWireCall {
  PipeWireCall._(this.clientGeneration, this.gateway, this._properties);

  /// Connection identity that distinguishes objects from different clients.
  final int clientGeneration;

  /// Gateway that owns this call.
  final PipeWireAudioGateway gateway;
  PwtCallProperties _properties;
  bool _valid = true;
  final _propertiesChanged = StreamController<List<String>>.broadcast(
    sync: true,
  );

  /// D-Bus object path of this call.
  String get objectPath => _properties.path;

  /// Discovery identity, changed when an object path is removed and reused.
  int get incarnation => _properties.incarnation;

  /// Remote line identification, or null if unavailable.
  String? get lineIdentification => _properties.lineIdentification;

  /// Incoming line label, or null if unavailable.
  String? get incomingLine => _properties.incomingLine;

  /// Caller name, or null if unavailable.
  String? get name => _properties.name;

  /// Whether this call is multiparty, or null if unavailable.
  bool? get multiparty => _properties.multiparty;

  /// Unmodified service state, preserving future values.
  String? get rawState => _properties.state;

  /// Typed state; unrecognized service values map to [PipeWireCallState.unknown].
  PipeWireCallState? get state => switch (rawState) {
    null => null,
    'active' => PipeWireCallState.active,
    'held' => PipeWireCallState.held,
    'dialing' => PipeWireCallState.dialing,
    'alerting' => PipeWireCallState.alerting,
    'incoming' => PipeWireCallState.incoming,
    'waiting' => PipeWireCallState.waiting,
    'disconnected' => PipeWireCallState.disconnected,
    _ => PipeWireCallState.unknown,
  };

  /// Whether this call and its parent gateway are still available.
  bool get isValid => _valid && gateway.isValid;

  /// Changed D-Bus property names, emitted after cached values are updated.
  Stream<List<String>> get propertiesChanged => _propertiesChanged.stream;

  /// Reloads this call's properties; throws [StateError] if invalid.
  Future<void> refresh() {
    _ensureValid();
    return gateway._client._command(
      operation: 'refreshCall',
      path: objectPath,
      incarnation: incarnation,
      interface: 'org.pipewire.Telephony.Call1',
    );
  }

  /// Requests answering this call; throws [StateError] if invalid.
  Future<void> answer() {
    _ensureValid();
    return gateway._client._command(
      operation: 'answer',
      path: objectPath,
      incarnation: incarnation,
      interface: 'org.pipewire.Telephony.Call1',
    );
  }

  /// Requests ending this call; throws [StateError] if invalid.
  Future<void> hangup() {
    _ensureValid();
    return gateway._client._command(
      operation: 'hangup',
      path: objectPath,
      incarnation: incarnation,
      interface: 'org.pipewire.Telephony.Call1',
    );
  }

  void _updateProperties(PwtCallProperties properties) {
    if (isValid && properties.incarnation == incarnation) {
      _properties = properties;
      if (properties.changed.isNotEmpty && !_propertiesChanged.isClosed) {
        _propertiesChanged.add(List.unmodifiable(properties.changed));
      }
    }
  }

  void _invalidate() {
    if (!_valid) return;
    _valid = false;
    unawaited(_propertiesChanged.close());
  }

  void _ensureValid() {
    if (!isValid) {
      throw StateError('call is no longer available');
    }
  }
}
