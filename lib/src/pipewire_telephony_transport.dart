part of 'pipewire_telephony_client.dart';

/// The optional `org.pipewire.Telephony.AudioGatewayTransport1` interface.
final class PipeWireTelephonyTransport {
  PipeWireTelephonyTransport._(
    this.clientGeneration,
    this.gateway,
    this._properties,
  );

  /// Connection identity that distinguishes objects from different clients.
  final int clientGeneration;

  /// Gateway that owns this transport.
  final PipeWireAudioGateway gateway;
  PwtTransportProperties _properties;
  bool _valid = true;
  final _propertiesChanged = StreamController<List<String>>.broadcast(
    sync: true,
  );

  /// D-Bus object path, shared with the owning gateway.
  String get objectPath => _properties.path;

  /// Discovery identity, changed when the interface is removed and re-added.
  int get incarnation => _properties.incarnation;

  /// Unmodified service state, preserving future values.
  String? get rawState => _properties.state;

  /// Typed state; unrecognized values map to [PipeWireTransportState.unknown].
  PipeWireTransportState? get state => switch (rawState) {
    null => null,
    'error' => PipeWireTransportState.error,
    'idle' => PipeWireTransportState.idle,
    'pending' => PipeWireTransportState.pending,
    'active' => PipeWireTransportState.active,
    _ => PipeWireTransportState.unknown,
  };

  /// Negotiated HFP codec identifier, or null if unavailable.
  int? get codec => _properties.codec;

  /// Whether incoming SCO connections are rejected, or null if unavailable.
  bool? get rejectSco => _properties.rejectSco;

  /// Whether this interface and its gateway are still available.
  bool get isValid => _valid && gateway.isValid;

  /// Changed D-Bus property names, emitted after cached values are updated.
  Stream<List<String>> get propertiesChanged => _propertiesChanged.stream;

  /// Reloads transport properties; throws [StateError] if invalid.
  Future<void> refresh() {
    _ensureValid();
    return gateway._client._command(
      operation: 'refreshTransport',
      path: objectPath,
      incarnation: incarnation,
      interface: 'org.pipewire.Telephony.AudioGatewayTransport1',
    );
  }

  /// Requests SCO activation; throws [StateError] if invalid.
  ///
  /// Audio routing and microphone/speaker links remain application policy.
  Future<void> activate() {
    _ensureValid();
    return gateway._client._command(
      operation: 'activate',
      path: objectPath,
      incarnation: incarnation,
      interface: 'org.pipewire.Telephony.AudioGatewayTransport1',
    );
  }

  /// Sets whether incoming SCO connections are rejected.
  Future<void> setRejectSco(bool value) {
    _ensureValid();
    return gateway._client._command(
      operation: 'setRejectSco',
      path: objectPath,
      incarnation: incarnation,
      interface: 'org.pipewire.Telephony.AudioGatewayTransport1',
      arguments: PwtRequestArguments(value: value),
    );
  }

  void _updateProperties(PwtTransportProperties properties) {
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
      throw StateError('telephony transport is no longer available');
    }
  }
}
