part of 'pipewire_telephony_client.dart';

/// A discovered `org.pipewire.Telephony.Call1` object.
final class PipeWireCall {
  PipeWireCall.internal(this.clientGeneration, this.gateway, this._properties);

  final int clientGeneration;
  final PipeWireAudioGateway gateway;
  PwtCallProperties _properties;
  bool _valid = true;
  final _propertiesChanged = StreamController<List<String>>.broadcast(
    sync: true,
  );

  String get objectPath => _properties.path;
  int get incarnation => _properties.incarnation;
  String? get lineIdentification => _properties.lineIdentification;
  String? get incomingLine => _properties.incomingLine;
  String? get name => _properties.name;
  bool? get multiparty => _properties.multiparty;
  String? get rawState => _properties.state;
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
  bool get isValid => _valid && gateway.isValid;
  Stream<List<String>> get propertiesChanged => _propertiesChanged.stream;

  Future<void> refresh() {
    ensureValid();
    return gateway._client._command(
      operation: 'refreshCall',
      path: objectPath,
      incarnation: incarnation,
      interface: 'org.pipewire.Telephony.Call1',
    );
  }

  Future<void> answer() {
    ensureValid();
    return gateway._client._command(
      operation: 'answer',
      path: objectPath,
      incarnation: incarnation,
      interface: 'org.pipewire.Telephony.Call1',
    );
  }

  Future<void> hangup() {
    ensureValid();
    return gateway._client._command(
      operation: 'hangup',
      path: objectPath,
      incarnation: incarnation,
      interface: 'org.pipewire.Telephony.Call1',
    );
  }

  void updateProperties(PwtCallProperties properties) {
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
      throw StateError('call is no longer available');
    }
  }
}
