part of 'pipewire_telephony_client.dart';

/// A discovered `org.pipewire.Telephony.AudioGateway1` object.
final class PipeWireAudioGateway {
  PipeWireAudioGateway.internal(this.clientGeneration, this._properties);

  final int clientGeneration;
  PwtGatewayProperties _properties;
  bool _valid = true;
  final _calls = <String, PipeWireCall>{};

  String get objectPath => _properties.path;
  int get incarnation => _properties.incarnation;
  String? get address => _properties.address;
  int? get speakerVolume => _properties.speakerVolume;
  int? get microphoneVolume => _properties.microphoneVolume;
  bool get isValid => _valid;
  List<PipeWireCall> get calls => List.unmodifiable(_calls.values);

  void updateProperties(PwtGatewayProperties properties) {
    if (_valid && properties.incarnation == incarnation) {
      _properties = properties;
    }
  }

  void addCall(PipeWireCall call) => _calls[call.objectPath] = call;

  void removeCall(String path) => _calls.remove(path);

  void invalidate() {
    _valid = false;
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
