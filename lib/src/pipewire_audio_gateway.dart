part of 'pipewire_telephony_client.dart';

/// A discovered `org.pipewire.Telephony.AudioGateway1` object.
final class PipeWireAudioGateway {
  PipeWireAudioGateway.internal(
    this._client,
    this.clientGeneration,
    this._properties,
  );

  final PipeWireTelephonyClient _client;
  final int clientGeneration;
  PwtGatewayProperties _properties;
  bool _valid = true;
  final _calls = <String, PipeWireCall>{};
  final _propertiesChanged = StreamController<List<String>>.broadcast(
    sync: true,
  );

  String get objectPath => _properties.path;
  int get incarnation => _properties.incarnation;
  String? get address => _properties.address;
  int? get speakerVolume => _properties.speakerVolume;
  int? get microphoneVolume => _properties.microphoneVolume;
  bool get isValid => _valid;
  List<PipeWireCall> get calls => List.unmodifiable(_calls.values);
  Stream<List<String>> get propertiesChanged => _propertiesChanged.stream;

  Future<void> refresh() {
    ensureValid();
    return _client._command(
      operation: 'refreshGateway',
      path: objectPath,
      incarnation: incarnation,
      interface: 'org.pipewire.Telephony.AudioGateway1',
    );
  }

  void updateProperties(PwtGatewayProperties properties) {
    if (_valid && properties.incarnation == incarnation) {
      _properties = properties;
      if (properties.changed.isNotEmpty && !_propertiesChanged.isClosed) {
        _propertiesChanged.add(List.unmodifiable(properties.changed));
      }
    }
  }

  void addCall(PipeWireCall call) => _calls[call.objectPath] = call;

  void removeCall(String path) => _calls.remove(path);

  void invalidate() {
    if (!_valid) return;
    _valid = false;
    unawaited(_propertiesChanged.close());
    for (final call in _calls.values) {
      call.invalidate();
    }
    _calls.clear();
  }

  void ensureValid() {
    if (!_valid) {
      throw StateError('audio gateway is no longer available');
    }
  }
}
