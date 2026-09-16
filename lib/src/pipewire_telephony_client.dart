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

final class PipeWireTelephonyClient {
  PipeWireTelephonyClient({
    this.bus = PipeWireBus.system,
    this.startupTimeout = const Duration(seconds: 30),
  }) {
    final (library, path) = loadPipeWireTelephonyLibrary();
    _bindings = PwtNativeBindings(library, libraryPath: path);
  }

  final PipeWireBus bus;
  final Duration startupTimeout;
  final _stateChanges =
      StreamController<PipeWireTelephonyClientState>.broadcast(sync: true);
  final _codec = const PwtJsonCodec();

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

  PipeWireTelephonyClientState get state => _state;
  PipeWireTelephonyException? get lastError => _lastError;
  Stream<PipeWireTelephonyClientState> get stateChanged => _stateChanges.stream;

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
        bus: bus == PipeWireBus.system
            ? PwtNativeBus.system
            : PwtNativeBus.session,
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

  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    if (_state == PipeWireTelephonyClientState.closed) return;
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
    _setState(PipeWireTelephonyClientState.closed);
    unawaited(_stateChanges.close());
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
}

PipeWireTelephonyException _exception(PwtError error) =>
    PipeWireTelephonyException(
      category: error.category,
      name: error.name,
      message: error.message,
      operation: error.operation,
      path: error.path,
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
