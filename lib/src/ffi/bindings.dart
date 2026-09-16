import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../../pipewire_telephony_native_bindings_generated.dart';

enum PwtNativeStatus {
  ok(PWT_STATUS_OK),
  invalidArgument(PWT_STATUS_INVALID_ARGUMENT),
  invalidHandle(PWT_STATUS_INVALID_HANDLE),
  invalidState(PWT_STATUS_INVALID_STATE),
  queueFull(PWT_STATUS_QUEUE_FULL),
  protocolError(PWT_STATUS_PROTOCOL_ERROR),
  internalError(PWT_STATUS_INTERNAL_ERROR);

  const PwtNativeStatus(this.code);

  final int code;

  static PwtNativeStatus fromCode(int code) => values.firstWhere(
    (value) => value.code == code,
    orElse: () => PwtNativeStatus.internalError,
  );
}

final class PwtClientHandle {
  PwtClientHandle._(this._pointer);

  Pointer<Void> _pointer;

  bool get isDestroyed => _pointer == nullptr;
}

final class PwtNativeBindings {
  PwtNativeBindings(DynamicLibrary library)
    : _bindings = PipewireTelephonyNativeBindings(library) {
    if (abiVersion != expectedAbiVersion) {
      throw UnsupportedError(
        'unsupported native ABI $abiVersion; expected $expectedAbiVersion',
      );
    }
  }

  static const expectedAbiVersion = 1;

  final PipewireTelephonyNativeBindings _bindings;

  int get abiVersion => _bindings.pwt_abi_version();

  PwtNativeStatus initializeDartApi() => PwtNativeStatus.fromCode(
    _bindings.pwt_initialize_dart_api_dl(NativeApi.initializeApiDLData),
  );

  PwtClientHandle createClient(int eventPort) {
    final pointer = _bindings.pwt_client_create(eventPort);
    if (pointer == nullptr) {
      throw StateError('native client allocation failed');
    }
    return PwtClientHandle._(pointer);
  }

  PwtNativeStatus start(PwtClientHandle handle) =>
      PwtNativeStatus.fromCode(_bindings.pwt_client_start(handle._pointer));

  PwtNativeStatus submit(
    PwtClientHandle handle,
    Uint8List bytes,
    int resultPort,
  ) {
    if (bytes.isEmpty) return PwtNativeStatus.invalidArgument;
    final buffer = calloc<Uint8>(bytes.length);
    try {
      buffer.asTypedList(bytes.length).setAll(0, bytes);
      return PwtNativeStatus.fromCode(
        _bindings.pwt_client_submit(
          handle._pointer,
          buffer,
          bytes.length,
          resultPort,
        ),
      );
    } finally {
      calloc.free(buffer);
    }
  }

  PwtNativeStatus stop(PwtClientHandle handle) =>
      PwtNativeStatus.fromCode(_bindings.pwt_client_stop(handle._pointer));

  void destroy(PwtClientHandle handle) {
    final pointer = handle._pointer;
    if (pointer == nullptr) return;
    handle._pointer = nullptr;
    _bindings.pwt_client_destroy(pointer);
  }

  void freeNativeBuffer(Pointer<Void> buffer) => _bindings.pwt_free(buffer);
}
