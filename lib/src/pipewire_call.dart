part of 'pipewire_telephony_client.dart';

/// A discovered `org.pipewire.Telephony.Call1` object.
final class PipeWireCall {
  PipeWireCall.internal(this.clientGeneration, this.gateway, this._properties);

  final int clientGeneration;
  final PipeWireAudioGateway gateway;
  PwtCallProperties _properties;
  bool _valid = true;

  String get objectPath => _properties.path;
  int get incarnation => _properties.incarnation;
  String? get lineIdentification => _properties.lineIdentification;
  String? get incomingLine => _properties.incomingLine;
  String? get name => _properties.name;
  bool? get multiparty => _properties.multiparty;
  String? get state => _properties.state;
  bool get isValid => _valid && gateway.isValid;

  void updateProperties(PwtCallProperties properties) {
    if (isValid && properties.incarnation == incarnation) {
      _properties = properties;
    }
  }

  void invalidate() => _valid = false;

  void ensureValid() {
    if (!isValid) {
      throw StateError('call is no longer available');
    }
  }
}
