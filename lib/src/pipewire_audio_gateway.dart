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
  PipeWireTelephonyTransport? _transport;
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
  PipeWireTelephonyTransport? get transport => _transport;
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

  Future<void> dial(String number) {
    ensureValid();
    if (number.isEmpty || number.length > 80 || !_validDialText(number)) {
      throw ArgumentError.value(number, 'number', 'invalid dial string');
    }
    return _client._command(
      operation: 'dial',
      path: objectPath,
      incarnation: incarnation,
      interface: 'org.pipewire.Telephony.AudioGateway1',
      arguments: PwtRequestArguments(text: number),
    );
  }

  Future<void> sendTones(String tones) {
    ensureValid();
    if (!_validToneText(tones)) {
      throw ArgumentError.value(tones, 'tones', 'invalid DTMF string');
    }
    return _client._command(
      operation: 'sendTones',
      path: objectPath,
      incarnation: incarnation,
      interface: 'org.pipewire.Telephony.AudioGateway1',
      arguments: PwtRequestArguments(text: tones),
    );
  }

  Future<void> hangupAll() {
    ensureValid();
    return _client._command(
      operation: 'hangupAll',
      path: objectPath,
      incarnation: incarnation,
      interface: 'org.pipewire.Telephony.AudioGateway1',
    );
  }

  Future<void> swapCalls() => _gatewayCommand('swapCalls');

  Future<void> releaseAndAnswer() => _gatewayCommand('releaseAndAnswer');

  Future<void> releaseAndSwap() => _gatewayCommand('releaseAndSwap');

  Future<void> holdAndAnswer() => _gatewayCommand('holdAndAnswer');

  Future<void> createMultiparty() => _gatewayCommand('createMultiparty');

  Future<void> _gatewayCommand(String operation) {
    ensureValid();
    return _client._command(
      operation: operation,
      path: objectPath,
      incarnation: incarnation,
      interface: 'org.pipewire.Telephony.AudioGateway1',
    );
  }

  Future<void> setSpeakerVolume(int volume) => _setVolume(
    operation: 'setSpeakerVolume',
    argumentName: 'volume',
    volume: volume,
  );

  Future<void> setMicrophoneVolume(int volume) => _setVolume(
    operation: 'setMicrophoneVolume',
    argumentName: 'volume',
    volume: volume,
  );

  Future<void> _setVolume({
    required String operation,
    required String argumentName,
    required int volume,
  }) {
    ensureValid();
    if (volume < 0 || volume > 15) {
      throw RangeError.range(volume, 0, 15, argumentName);
    }
    return _client._command(
      operation: operation,
      path: objectPath,
      incarnation: incarnation,
      interface: 'org.pipewire.Telephony.AudioGateway1',
      arguments: PwtRequestArguments(volume: volume),
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

  void replaceTransport(PipeWireTelephonyTransport transport) {
    _transport?.invalidate();
    _transport = transport;
  }

  void removeTransport() {
    _transport?.invalidate();
    _transport = null;
  }

  void invalidate() {
    if (!_valid) return;
    _valid = false;
    removeTransport();
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

bool _validDialText(String value) => value.codeUnits.every(
  (character) => switch (character) {
    >= 0x30 && <= 0x39 ||
    0x2b ||
    0x2a ||
    0x23 ||
    0x2c ||
    >= 0x41 && <= 0x44 => true,
    _ => false,
  },
);

bool _validToneText(String value) => value.codeUnits.every(
  (character) => switch (character) {
    >= 0x30 && <= 0x39 || 0x2a || 0x23 || >= 0x41 && <= 0x44 => true,
    _ => false,
  },
);
