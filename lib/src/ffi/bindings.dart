// FFI allocation and handle-lifetime patterns are adapted from
// https://github.com/jwinarske/bluez_native/blob/main/lib/src/ffi/bindings.dart.
// Derived portions are Copyright 2026 Joel Winarske under Apache-2.0; see
// LICENSES/Apache-2.0.txt. Subsequent modifications are Copyright 2026
// Jian De under the package's BSD-3-Clause license.

import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'bindings_generated.dart';

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

enum PwtNativeBus {
  automatic(PWT_BUS_AUTO),
  system(PWT_BUS_SYSTEM),
  session(PWT_BUS_SESSION);

  const PwtNativeBus(this.code);

  final int code;
}

final class PwtClientHandle {
  PwtClientHandle._(this._pointer);

  Pointer<Void> _pointer;

  bool get isDestroyed => _pointer == nullptr;

  int takeAddress() {
    final address = _pointer.address;
    _pointer = nullptr;
    return address;
  }
}

final class PwtNativeBindings {
  PwtNativeBindings(DynamicLibrary library, {String? libraryPath})
    : this._(library, libraryPath);

  PwtNativeBindings._(DynamicLibrary library, this._libraryPath)
    : _bindings = PipewireTelephonyNativeBindings(library) {
    if (abiVersion != expectedAbiVersion) {
      throw UnsupportedError(
        'unsupported native ABI $abiVersion; expected $expectedAbiVersion',
      );
    }
  }

  static const expectedAbiVersion = 1;

  final PipewireTelephonyNativeBindings _bindings;
  final String? _libraryPath;

  int get abiVersion => _bindings.pwt_abi_version();

  PwtNativeStatus initializeDartApi() => PwtNativeStatus.fromCode(
    _bindings.pwt_initialize_dart_api_dl(NativeApi.initializeApiDLData),
  );

  PwtClientHandle createClient(
    int eventPort, {
    required PwtNativeBus bus,
    String? testBusAddress,
  }) {
    final addressBytes = testBusAddress == null
        ? const <int>[]
        : utf8.encode(testBusAddress);
    final address = addressBytes.isEmpty
        ? nullptr.cast<Uint8>()
        : calloc<Uint8>(addressBytes.length);
    if (addressBytes.isNotEmpty) {
      address.asTypedList(addressBytes.length).setAll(0, addressBytes);
    }
    final Pointer<Void> pointer;
    try {
      pointer = _bindings.pwt_client_create(
        bus.code,
        address,
        addressBytes.length,
        eventPort,
      );
    } finally {
      if (address != nullptr) calloc.free(address);
    }
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

  Future<void> destroyAsync(PwtClientHandle handle) async {
    final address = handle.takeAddress();
    if (address == 0) return;
    final path = _libraryPath;
    if (path == null) {
      _bindings.pwt_client_destroy(Pointer<Void>.fromAddress(address));
      return;
    }
    await Isolate.run(() => _destroyClient((path, address)));
  }

  void freeNativeBuffer(Pointer<Void> buffer) => _bindings.pwt_free(buffer);
}

void _destroyClient((String, int) request) {
  final bindings = PipewireTelephonyNativeBindings(
    DynamicLibrary.open(request.$1),
  );
  bindings.pwt_client_destroy(Pointer<Void>.fromAddress(request.$2));
}
