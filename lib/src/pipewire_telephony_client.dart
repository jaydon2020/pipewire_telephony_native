// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2026 Joel Winarske <joel.winarske@gmail.com>
// SPDX-FileCopyrightText: 2026 Jian De Seak

// Client lifecycle and event-routing patterns are adapted from
// https://github.com/jwinarske/bluez_native/blob/main/lib/src/bluez_client.dart
// under Apache-2.0; see LICENSES/Apache-2.0.txt and THIRD_PARTY_NOTICES.md.

import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'enums.dart';
import 'exceptions.dart';
import 'ffi/bindings.dart';
import 'ffi/codec.dart';
import 'ffi/types.dart';
import 'internal/library_loader.dart';

part 'pipewire_audio_gateway.dart';
part 'pipewire_call.dart';
part 'pipewire_telephony_transport.dart';

/// Discovers and controls PipeWire Bluetooth telephony objects on Linux.
///
/// Call [connect] before using discovered objects and await [close] when done.
/// A client that becomes unavailable cannot reconnect; create a new client.
/// Commands complete after a D-Bus reply or throw [PipeWireTelephonyException].
final class PipeWireTelephonyClient {
  /// Creates a client and loads its native library.
  ///
  /// [startupTimeout] must be positive. [operationTimeout] must be positive and
  /// at most 30 seconds, the native command deadline. A shorter operation timeout
  /// only stops waiting; it does not cancel the remote command.
  PipeWireTelephonyClient({
    this.bus = PipeWireBus.automatic,
    this.startupTimeout = const Duration(seconds: 30),
    this.operationTimeout = const Duration(seconds: 30),
  }) {
    if (startupTimeout <= Duration.zero) {
      throw ArgumentError.value(
        startupTimeout,
        'startupTimeout',
        'must be positive',
      );
    }
    if (operationTimeout <= Duration.zero ||
        operationTimeout > const Duration(seconds: 30)) {
      throw ArgumentError.value(
        operationTimeout,
        'operationTimeout',
        'must be positive and at most 30 seconds',
      );
    }
    final (library, path) = loadPipeWireTelephonyLibrary();
    _bindings = PwtNativeBindings(library, libraryPath: path);
  }

  /// D-Bus scope searched by [connect].
  final PipeWireBus bus;

  /// Maximum time to wait for the initial discovery snapshot.
  final Duration startupTimeout;

  /// Maximum reply wait, up to the native 30-second deadline.
  ///
  /// A timeout leaves the remote outcome unknown. A mutation can keep its
  /// gateway busy until native completion or expiry. Refresh state before
  /// deciding whether to retry; retrying a dial may create another call.
  final Duration operationTimeout;
  final _stateChanges =
      StreamController<PipeWireTelephonyClientState>.broadcast(sync: true);
  final _gatewayAdded = StreamController<PipeWireAudioGateway>.broadcast(
    sync: true,
  );
  final _gatewayRemoved = StreamController<PipeWireAudioGateway>.broadcast(
    sync: true,
  );
  final _gatewayChanged = StreamController<PipeWireAudioGateway>.broadcast(
    sync: true,
  );
  final _callAdded = StreamController<PipeWireCall>.broadcast(sync: true);
  final _callRemoved = StreamController<PipeWireCall>.broadcast(sync: true);
  final _callChanged = StreamController<PipeWireCall>.broadcast(sync: true);
  final _codec = const PwtJsonCodec();
  final _gateways = <String, PipeWireAudioGateway>{};
  final _calls = <String, PipeWireCall>{};

  late final PwtNativeBindings _bindings;
  PipeWireTelephonyClientState _state = PipeWireTelephonyClientState.idle;
  PipeWireTelephonyException? _lastError;
  PwtClientHandle? _handle;
  ReceivePort? _eventPort;
  StreamSubscription<Object?>? _eventSubscription;
  Completer<void>? _connectCompleter;
  Future<void>? _closeFuture;
  Future<void>? _nativeRelease;
  Timer? _startupTimer;
  int _generation = 0;
  int _nextRequestId = 1;

  /// Current connection lifecycle state.
  PipeWireTelephonyClientState get state => _state;

  /// Most recent startup or service-loss error, if any.
  PipeWireTelephonyException? get lastError => _lastError;

  /// Lifecycle changes; read [state] for the current value.
  Stream<PipeWireTelephonyClientState> get stateChanged => _stateChanges.stream;

  /// Immutable snapshot of currently discovered gateways.
  List<PipeWireAudioGateway> get gateways =>
      List.unmodifiable(_gateways.values);

  /// Gateways discovered after initial connection.
  Stream<PipeWireAudioGateway> get gatewayAdded => _gatewayAdded.stream;

  /// Gateways removed from discovery; emitted objects are already invalid.
  Stream<PipeWireAudioGateway> get gatewayRemoved => _gatewayRemoved.stream;

  /// Gateways whose properties or call membership changed.
  Stream<PipeWireAudioGateway> get gatewayChanged => _gatewayChanged.stream;

  /// Immutable snapshot of calls across all gateways.
  List<PipeWireCall> get calls => List.unmodifiable(_calls.values);

  /// Calls discovered after initial connection.
  Stream<PipeWireCall> get callAdded => _callAdded.stream;

  /// Removed calls; emitted objects are already invalid.
  Stream<PipeWireCall> get callRemoved => _callRemoved.stream;

  /// Calls whose cached properties changed.
  Stream<PipeWireCall> get callChanged => _callChanged.stream;

  /// Refreshes all currently discovered objects using D-Bus property reads.
  ///
  /// Throws [StateError] unless ready. Objects may disappear during refresh.
  Future<void> refresh() async {
    _ensureReady();
    await Future.wait([
      for (final gateway in gateways) gateway.refresh(),
      for (final call in calls) call.refresh(),
      for (final gateway in gateways)
        if (gateway.transport case final transport?) transport.refresh(),
    ]);
  }

  Future<void> _command({
    required String operation,
    required String path,
    required int incarnation,
    required String interface,
    PwtRequestArguments arguments = const PwtRequestArguments(),
  }) async {
    _ensureReady();
    final handle = _handle;
    if (handle == null) throw StateError('native client is unavailable');
    final requestId = _nextRequestId++;
    final request = PwtRequest(
      requestId: requestId,
      operation: operation,
      target: PwtTargetIdentity(
        clientGeneration: _generation,
        objectIncarnation: incarnation,
        path: path,
        interface: interface,
      ),
      arguments: arguments,
    );
    final port = ReceivePort('pipewire_telephony.result.$requestId');
    try {
      final status = _bindings.submit(
        handle,
        _codec.encodeRequest(request),
        port.sendPort.nativePort,
      );
      if (status != PwtNativeStatus.ok) {
        throw PipeWireTelephonyException(
          category: 'local',
          name: 'org.pipewire.Telephony.Error.Submission',
          message: 'native command submission failed: $status',
          operation: operation,
          path: path,
          requestId: requestId,
        );
      }
      final message = await port.first.timeout(operationTimeout);
      if (message is! Uint8List) {
        throw const FormatException('invalid native reply type');
      }
      final reply = _codec.decodeReply(message);
      if (reply.requestId != requestId ||
          reply.clientGeneration != _generation) {
        throw const FormatException('reply identity mismatch');
      }
      if (!reply.ok) {
        throw _exception(reply.error!, requestId: reply.requestId);
      }
    } on TimeoutException {
      throw PipeWireTelephonyException(
        category: 'local',
        name: 'org.pipewire.Telephony.Error.Timeout',
        message: 'operation timed out; remote outcome is unknown',
        operation: operation,
        path: path,
        requestId: requestId,
      );
    } finally {
      port.close();
    }
  }

  /// Connects and waits for the initial gateway, call, and transport snapshot.
  ///
  /// Concurrent calls share startup. Calling while ready succeeds immediately;
  /// calling after service loss or closing fails with [StateError].
  Future<void> connect() {
    if (_state == PipeWireTelephonyClientState.ready) {
      return Future.value();
    }
    final active = _connectCompleter;
    if (_state == PipeWireTelephonyClientState.connecting && active != null) {
      return active.future;
    }
    if (_state != PipeWireTelephonyClientState.idle) {
      return Future.error(StateError('client cannot connect from $_state'));
    }

    final completer = Completer<void>();
    _connectCompleter = completer;
    _setState(PipeWireTelephonyClientState.connecting);
    try {
      if (_bindings.initializeDartApi() != PwtNativeStatus.ok) {
        throw StateError('failed to initialize Dart native API');
      }
      final port = ReceivePort();
      _eventPort = port;
      _eventSubscription = port.listen(_onNativeEvent);
      final handle = _bindings.createClient(
        port.sendPort.nativePort,
        bus: switch (bus) {
          PipeWireBus.automatic => PwtNativeBus.automatic,
          PipeWireBus.system => PwtNativeBus.system,
          PipeWireBus.session => PwtNativeBus.session,
        },
      );
      _handle = handle;
      final status = _bindings.start(handle);
      if (status != PwtNativeStatus.ok) {
        throw StateError('native client start failed: $status');
      }
      _startupTimer = Timer(startupTimeout, _onStartupTimeout);
    } catch (error, stackTrace) {
      _failStartup(_localException(error.toString()), stackTrace);
    }
    return completer.future;
  }

  /// Stops native work, releases resources, and invalidates discovered objects.
  ///
  /// Repeated calls return the same future. Streams close without waiting for
  /// paused subscriptions to resume.
  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    if (_state == PipeWireTelephonyClientState.closed) return;
    await Future<void>.value();
    _setState(PipeWireTelephonyClientState.closing);
    _startupTimer?.cancel();
    final completer = _connectCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(StateError('client closed during startup'));
    }
    await _releaseNative();
    await _eventSubscription?.cancel();
    _eventPort?.close();
    _eventSubscription = null;
    _eventPort = null;
    _clearGateways(notify: false);
    _setState(PipeWireTelephonyClientState.closed);
    unawaited(_stateChanges.close());
    unawaited(_gatewayAdded.close());
    unawaited(_gatewayRemoved.close());
    unawaited(_gatewayChanged.close());
    unawaited(_callAdded.close());
    unawaited(_callRemoved.close());
    unawaited(_callChanged.close());
  }

  void _onNativeEvent(Object? message) {
    if (_state == PipeWireTelephonyClientState.closing ||
        _state == PipeWireTelephonyClientState.closed) {
      return;
    }
    if (message is! Uint8List) {
      _becomeUnavailable(_localException('invalid native event type'));
      return;
    }
    try {
      final event = _codec.decodeEvent(message);
      final lifecycle = event.payload.lifecycle?.state;
      if (lifecycle == 'ready') {
        final startup = event.payload.startup;
        if (startup == null) {
          throw const FormatException('ready event has no startup snapshot');
        }
        _generation = event.clientGeneration;
        _replaceGateways(event.clientGeneration, startup.gateways);
        _replaceCalls(event.clientGeneration, startup.calls);
        _replaceTransports(event.clientGeneration, startup.transports);
        _startupTimer?.cancel();
        _setState(PipeWireTelephonyClientState.ready);
        final completer = _connectCompleter;
        if (completer != null && !completer.isCompleted) completer.complete();
      } else if (lifecycle == 'unavailable') {
        final error = event.payload.error;
        _becomeUnavailable(
          error == null
              ? _localException('telephony service unavailable')
              : _exception(error),
        );
      } else {
        _applyGatewayEvent(event);
        _applyCallEvent(event);
        _applyTransportEvent(event);
      }
    } catch (error, stackTrace) {
      _failStartup(_localException(error.toString()), stackTrace);
    }
  }

  void _onStartupTimeout() {
    _becomeUnavailable(
      _localException(
        'telephony startup timed out',
        name: 'org.pipewire.Telephony.Error.Timeout',
      ),
    );
  }

  void _failStartup(
    PipeWireTelephonyException error, [
    StackTrace? stackTrace,
  ]) {
    _lastError = error;
    final completer = _connectCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(error, stackTrace);
    }
    _clearGateways();
    _setState(PipeWireTelephonyClientState.unavailable);
    unawaited(_releaseNative());
  }

  void _becomeUnavailable(PipeWireTelephonyException error) {
    if (_state == PipeWireTelephonyClientState.closing ||
        _state == PipeWireTelephonyClientState.closed) {
      return;
    }
    _startupTimer?.cancel();
    _failStartup(error);
  }

  Future<void> _releaseNative() => _nativeRelease ??= _releaseNativeOnce();

  Future<void> _releaseNativeOnce() async {
    final handle = _handle;
    _handle = null;
    if (handle == null || handle.isDestroyed) return;
    _bindings.stop(handle);
    await _bindings.destroyAsync(handle);
  }

  void _setState(PipeWireTelephonyClientState value) {
    if (_state == value) return;
    _state = value;
    if (!_stateChanges.isClosed) _stateChanges.add(value);
  }

  void _replaceGateways(
    int clientGeneration,
    List<PwtGatewayProperties> properties,
  ) {
    _clearGateways(notify: false);
    for (final value in properties) {
      _gateways[value.path] = PipeWireAudioGateway._(
        this,
        clientGeneration,
        value,
      );
    }
  }

  void _applyGatewayEvent(PwtEvent event) {
    final properties = event.payload.gateway;
    if (properties == null) return;
    switch (event.kind) {
      case 'gatewayAdded':
        _removeCallsForGateway(properties.path);
        final previous = _gateways.remove(properties.path);
        previous?._invalidate();
        final gateway = PipeWireAudioGateway._(
          this,
          event.clientGeneration,
          properties,
        );
        _gateways[properties.path] = gateway;
        if (!_gatewayAdded.isClosed) _gatewayAdded.add(gateway);
      case 'gatewayChanged':
        final gateway = _gateways[properties.path];
        if (gateway == null || gateway.incarnation != properties.incarnation) {
          return;
        }
        gateway._updateProperties(properties);
        if (!_gatewayChanged.isClosed) _gatewayChanged.add(gateway);
      case 'gatewayRemoved':
        final gateway = _gateways[properties.path];
        if (gateway == null || gateway.incarnation != properties.incarnation) {
          return;
        }
        _removeCallsForGateway(properties.path);
        _gateways.remove(properties.path);
        gateway._invalidate();
        if (!_gatewayRemoved.isClosed) _gatewayRemoved.add(gateway);
    }
  }

  void _clearGateways({bool notify = true}) {
    _clearCalls(notify: notify);
    final removed = _gateways.values.toList(growable: false);
    _gateways.clear();
    for (final gateway in removed) {
      gateway._invalidate();
      if (notify && !_gatewayRemoved.isClosed) _gatewayRemoved.add(gateway);
    }
  }

  void _replaceCalls(int clientGeneration, List<PwtCallProperties> properties) {
    _clearCalls(notify: false);
    for (final value in properties) {
      final gateway = _gateways[value.gatewayPath];
      if (gateway == null) continue;
      final call = PipeWireCall._(clientGeneration, gateway, value);
      _calls[value.path] = call;
      gateway._addCall(call);
    }
  }

  void _applyCallEvent(PwtEvent event) {
    final properties = event.payload.call;
    if (properties == null) return;
    switch (event.kind) {
      case 'callAdded':
        final gateway = _gateways[properties.gatewayPath];
        if (gateway == null) return;
        final previous = _calls.remove(properties.path);
        if (previous != null) {
          previous.gateway._removeCall(previous.objectPath);
          previous._invalidate();
        }
        final call = PipeWireCall._(
          event.clientGeneration,
          gateway,
          properties,
        );
        _calls[properties.path] = call;
        gateway._addCall(call);
        if (!_callAdded.isClosed) _callAdded.add(call);
        if (!_gatewayChanged.isClosed) _gatewayChanged.add(gateway);
      case 'callChanged':
        final call = _calls[properties.path];
        if (call == null || call.incarnation != properties.incarnation) return;
        call._updateProperties(properties);
        if (!_callChanged.isClosed) _callChanged.add(call);
      case 'callRemoved':
        final call = _calls[properties.path];
        if (call == null || call.incarnation != properties.incarnation) return;
        call._updateProperties(properties);
        _calls.remove(properties.path);
        call.gateway._removeCall(properties.path);
        call._invalidate();
        if (!_callRemoved.isClosed) _callRemoved.add(call);
        if (!_gatewayChanged.isClosed) _gatewayChanged.add(call.gateway);
    }
  }

  void _replaceTransports(
    int clientGeneration,
    List<PwtTransportProperties> properties,
  ) {
    for (final value in properties) {
      _gateways[value.path]?._replaceTransport(
        PipeWireTelephonyTransport._(
          clientGeneration,
          _gateways[value.path]!,
          value,
        ),
      );
    }
  }

  void _applyTransportEvent(PwtEvent event) {
    final properties = event.payload.transport;
    if (properties == null) return;
    final gateway = _gateways[properties.path];
    if (gateway == null) return;
    switch (event.kind) {
      case 'transportAdded':
        gateway._replaceTransport(
          PipeWireTelephonyTransport._(
            event.clientGeneration,
            gateway,
            properties,
          ),
        );
      case 'transportChanged':
        final transport = gateway.transport;
        if (transport == null ||
            transport.incarnation != properties.incarnation) {
          return;
        }
        transport._updateProperties(properties);
      case 'transportRemoved':
        final transport = gateway.transport;
        if (transport == null ||
            transport.incarnation != properties.incarnation) {
          return;
        }
        gateway._removeTransport();
    }
  }

  void _removeCallsForGateway(String gatewayPath, {bool notify = true}) {
    final removed = _calls.values
        .where((call) => call.gateway.objectPath == gatewayPath)
        .toList(growable: false);
    for (final call in removed) {
      _calls.remove(call.objectPath);
      call.gateway._removeCall(call.objectPath);
      call._invalidate();
      if (notify && !_callRemoved.isClosed) _callRemoved.add(call);
    }
  }

  void _clearCalls({bool notify = true}) {
    final removed = _calls.values.toList(growable: false);
    _calls.clear();
    for (final call in removed) {
      call.gateway._removeCall(call.objectPath);
      call._invalidate();
      if (notify && !_callRemoved.isClosed) _callRemoved.add(call);
    }
  }

  void _ensureReady() {
    if (_state != PipeWireTelephonyClientState.ready) {
      throw StateError('client is not ready');
    }
  }
}

PipeWireTelephonyException _exception(PwtError error, {int? requestId}) =>
    PipeWireTelephonyException(
      category: error.category,
      name: error.name,
      message: error.message,
      operation: error.operation,
      path: error.path,
      requestId: requestId,
    );

PipeWireTelephonyException _localException(
  String message, {
  String name = 'org.pipewire.Telephony.Error.Local',
}) => PipeWireTelephonyException(
  category: 'local',
  name: name,
  message: message,
  operation: 'connect',
  path: '/org/pipewire/Telephony',
);
