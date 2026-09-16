import 'dart:ffi';
import 'dart:io';

(DynamicLibrary, String) loadPipeWireTelephonyLibrary() {
  if (!Platform.isLinux) {
    throw UnsupportedError('PipeWire telephony is supported only on Linux');
  }
  final path =
      Platform.environment['PWT_NATIVE_LIB'] ??
      'libpipewire_telephony_native.so';
  return (DynamicLibrary.open(path), path);
}
