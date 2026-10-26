## 0.1.0

* Initial Linux release with Flutter FFI and Dart Native Assets builds.
* Resolve native code from declared assets or application bundle paths; remove
  ambient loaded-library and working-directory discovery.
* Reject cross-architecture Native Assets requests and validate native CMake
  output architecture/ABI before reporting build success.
* Support Native Assets cross-builds through an explicit, dependency-tracked
  CMake toolchain file while preserving the validated AGL prebuilt path.
* Allow the AGL Flutter LLVM runtime dependencies `libc++.so.1` and
  `libc++abi.so.1` in validated target libraries.
* Resolve the native library beside a loaded Flutter `libapp.so` for AGL
  homescreen deployments without `LD_LIBRARY_PATH`.
* Expand retained third-party copyright, license, and source provenance for
  vendored code, generated inputs, and Flutter templates.
* Discover PipeWire Bluetooth HFP gateways, calls, and optional SCO transports.
* Control calls, multi-call operations, DTMF, HFP volumes, and SCO activation.
* Expose live property and lifecycle streams, stale-object checks, and D-Bus errors.
* Support automatic session/system bus discovery and explicit bus selection.
* Include standalone Dart examples, a Flutter Linux app, and AGL build guidance.
* Require Flutter 3.38.3 / Dart 3.10.1, CMake 3.22, C++23, and libsystemd.
  Reconnection requires a new client; audio routing and Bluetooth pairing remain
  the application's integration responsibilities.
