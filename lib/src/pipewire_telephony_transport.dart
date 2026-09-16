part of 'pipewire_telephony_client.dart';

/// The optional `org.pipewire.Telephony.AudioGatewayTransport1` interface.
final class PipeWireTelephonyTransport {
  PipeWireTelephonyTransport.internal(
    this.clientGeneration,
    this.gateway,
    this._properties,
  );

  final int clientGeneration;
  final PipeWireAudioGateway gateway;
  PwtTransportProperties _properties;
  bool _valid = true;
  final _propertiesChanged = StreamController<List<String>>.broadcast(
    sync: true,
  );

  String get objectPath => _properties.path;
  int get incarnation => _properties.incarnation;
  String? get rawState => _properties.state;
  PipeWireTransportState? get state => switch (rawState) {
    null => null,
    'error' => PipeWireTransportState.error,
    'idle' => PipeWireTransportState.idle,
    'pending' => PipeWireTransportState.pending,
    'active' => PipeWireTransportState.active,
    _ => PipeWireTransportState.unknown,
  };
  int? get codec => _properties.codec;
  bool? get rejectSco => _properties.rejectSco;
  bool get isValid => _valid && gateway.isValid;
  Stream<List<String>> get propertiesChanged => _propertiesChanged.stream;

  Future<void> refresh() {
    ensureValid();
    return gateway._client._command(
      operation: 'refreshTransport',
      path: objectPath,
      incarnation: incarnation,
      interface: 'org.pipewire.Telephony.AudioGatewayTransport1',
    );
  }

  Future<void> activate() {
    ensureValid();
    return gateway._client._command(
      operation: 'activate',
      path: objectPath,
      incarnation: incarnation,
      interface: 'org.pipewire.Telephony.AudioGatewayTransport1',
    );
  }

  Future<void> setRejectSco(bool value) {
    ensureValid();
    return gateway._client._command(
      operation: 'setRejectSco',
      path: objectPath,
      incarnation: incarnation,
      interface: 'org.pipewire.Telephony.AudioGatewayTransport1',
      arguments: PwtRequestArguments(value: value),
    );
  }

  void updateProperties(PwtTransportProperties properties) {
    if (isValid && properties.incarnation == incarnation) {
      _properties = properties;
      if (properties.changed.isNotEmpty && !_propertiesChanged.isClosed) {
        _propertiesChanged.add(List.unmodifiable(properties.changed));
      }
    }
  }

  void invalidate() {
    if (!_valid) return;
    _valid = false;
    unawaited(_propertiesChanged.close());
  }

  void ensureValid() {
    if (!isValid) {
      throw StateError('telephony transport is no longer available');
    }
  }
}
