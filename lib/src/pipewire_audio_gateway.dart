part of 'pipewire_telephony_client.dart';

/// A discovered `org.pipewire.Telephony.AudioGateway1` object.
final class PipeWireAudioGateway {
  PipeWireAudioGateway._(this._client, this.clientGeneration, this._properties);

  final PipeWireTelephonyClient _client;

  /// Connection identity that distinguishes objects from different clients.
  final int clientGeneration;
  PwtGatewayProperties _properties;
  bool _valid = true;
  PipeWireTelephonyTransport? _transport;
  final _calls = <String, PipeWireCall>{};
  final _propertiesChanged = StreamController<List<String>>.broadcast(
    sync: true,
  );

  /// D-Bus object path of this gateway.
  String get objectPath => _properties.path;

  /// Discovery identity, changed when an object path is removed and reused.
  int get incarnation => _properties.incarnation;

  /// Remote Bluetooth device address, or null if unavailable.
  String? get address => _properties.address;

  /// Cached HFP speaker volume in 0..15, or null if unavailable.
  int? get speakerVolume => _properties.speakerVolume;

  /// Cached HFP microphone volume in 0..15, or null if unavailable.
  int? get microphoneVolume => _properties.microphoneVolume;

  /// Whether this object still belongs to the current discovery snapshot.
  bool get isValid => _valid;

  /// Immutable snapshot of this gateway's discovered calls.
  List<PipeWireCall> get calls => List.unmodifiable(_calls.values);

  /// Optional SCO transport; it can be added or removed independently.
  PipeWireTelephonyTransport? get transport => _transport;

  /// Changed D-Bus property names, emitted after cached values are updated.
  Stream<List<String>> get propertiesChanged => _propertiesChanged.stream;

  /// Reloads this gateway's properties; throws [StateError] if invalid.
  Future<void> refresh() {
    _ensureValid();
    return _client._command(
      operation: 'refreshGateway',
      path: objectPath,
      incarnation: incarnation,
      interface: 'org.pipewire.Telephony.AudioGateway1',
    );
  }

  /// Dials 1..80 characters from `0123456789+*#,ABCD`.
  ///
  /// Throws [ArgumentError] for invalid input and [StateError] if invalid.
  /// The new call arrives through discovery; the reply does not return a call.
  Future<void> dial(String number) {
    _ensureValid();
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

  /// Sends DTMF characters from `0123456789*#ABCD`; empty text is allowed.
  ///
  /// Throws [ArgumentError] for invalid input and [StateError] if invalid.
  Future<void> sendTones(String tones) {
    _ensureValid();
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

  /// Requests termination of all calls on this gateway.
  Future<void> hangupAll() {
    _ensureValid();
    return _client._command(
      operation: 'hangupAll',
      path: objectPath,
      incarnation: incarnation,
      interface: 'org.pipewire.Telephony.AudioGateway1',
    );
  }

  /// Requests swapping the active and held calls.
  Future<void> swapCalls() => _gatewayCommand('swapCalls');

  /// Requests releasing active calls and answering a waiting call.
  Future<void> releaseAndAnswer() => _gatewayCommand('releaseAndAnswer');

  /// Requests releasing active calls and activating held calls.
  Future<void> releaseAndSwap() => _gatewayCommand('releaseAndSwap');

  /// Requests holding active calls and answering a waiting call.
  Future<void> holdAndAnswer() => _gatewayCommand('holdAndAnswer');

  /// Requests combining calls into a multiparty call, if supported by the phone.
  Future<void> createMultiparty() => _gatewayCommand('createMultiparty');

  Future<void> _gatewayCommand(String operation) {
    _ensureValid();
    return _client._command(
      operation: operation,
      path: objectPath,
      incarnation: incarnation,
      interface: 'org.pipewire.Telephony.AudioGateway1',
    );
  }

  /// Sets speaker volume in 0..15; throws [RangeError] outside that range.
  Future<void> setSpeakerVolume(int volume) => _setVolume(
    operation: 'setSpeakerVolume',
    argumentName: 'volume',
    volume: volume,
  );

  /// Sets microphone volume in 0..15; throws [RangeError] outside that range.
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
    _ensureValid();
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

  void _updateProperties(PwtGatewayProperties properties) {
    if (_valid && properties.incarnation == incarnation) {
      _properties = properties;
      if (properties.changed.isNotEmpty && !_propertiesChanged.isClosed) {
        _propertiesChanged.add(List.unmodifiable(properties.changed));
      }
    }
  }

  void _addCall(PipeWireCall call) => _calls[call.objectPath] = call;

  void _removeCall(String path) => _calls.remove(path);

  void _replaceTransport(PipeWireTelephonyTransport transport) {
    _transport?._invalidate();
    _transport = transport;
  }

  void _removeTransport() {
    _transport?._invalidate();
    _transport = null;
  }

  void _invalidate() {
    if (!_valid) return;
    _valid = false;
    _removeTransport();
    unawaited(_propertiesChanged.close());
    for (final call in _calls.values) {
      call._invalidate();
    }
    _calls.clear();
  }

  void _ensureValid() {
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
