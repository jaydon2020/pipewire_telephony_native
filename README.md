# PipeWire Telephony Native

Flutter FFI access to PipeWire's Bluetooth HFP telephony D-Bus API on Linux.
The package discovers audio gateways, calls, and SCO transports and covers the
PipeWire 1.6.6 method and property surface through typed Dart objects.

## Supported features

| Area | Supported feature | Dart API / notes |
| --- | --- | --- |
| Platform | Linux Flutter and standalone Dart | Native Assets supports host builds and explicit CMake-toolchain cross-builds; AGL also has a documented prebuilt path. |
| D-Bus connection | Automatic, session, or system bus selection | `PipeWireBus.automatic`, `.session`, and `.system` |
| Gateway discovery | Initial snapshot plus add, remove, and property-change events | `gateways`, `gatewayAdded`, `gatewayRemoved`, `gatewayChanged` |
| Call discovery | Initial snapshot plus add, remove, and property-change events | `calls`, `callAdded`, `callRemoved`, `callChanged` |
| SCO transport discovery | Optional transport discovery and live replacement/removal | `gateway.transport` and `transport.propertiesChanged` |
| Lifecycle | Connection state, startup timeout, service-loss detection, and deterministic close | `connect()`, `state`, `stateChanged`, `lastError`, `close()` |
| Refresh | Reload all objects or one gateway, call, or transport | `client.refresh()` and each object's `refresh()` |
| Gateway properties | Bluetooth address and HFP speaker/microphone volumes | `address`, `speakerVolume`, `microphoneVolume` |
| Dialing | Dial numbers containing `0-9`, `+`, `*`, `#`, `,`, or `A-D` | `gateway.dial()`; accepts 1-80 characters |
| DTMF | Send `0-9`, `*`, `#`, or `A-D` tones | `gateway.sendTones()` |
| Individual calls | Answer and hang up | `call.answer()`, `call.hangup()` |
| All calls | Request termination of every call on a gateway | `gateway.hangupAll()` |
| Multi-call control | Swap, release-and-answer, release-and-swap, and hold-and-answer | `swapCalls()`, `releaseAndAnswer()`, `releaseAndSwap()`, `holdAndAnswer()` |
| Conference calls | Create a multiparty call when supported by the phone | `gateway.createMultiparty()` |
| HFP volume control | Read and set speaker and microphone gain from 0 to 15 | `setSpeakerVolume()`, `setMicrophoneVolume()` |
| Call metadata | Caller number, incoming line, name, and multiparty status | `lineIdentification`, `incomingLine`, `name`, `multiparty` |
| Call states | Active, held, dialing, alerting, incoming, waiting, disconnected, and unknown future values | `call.state` and `call.rawState` |
| SCO state | Error, idle, pending, active, and unknown future values; negotiated codec ID | `transport.state`, `rawState`, and `codec` |
| SCO control | Activate SCO and allow or reject incoming SCO connections | `transport.activate()`, `transport.setRejectSco()` |
| Error reporting | Local, connection, and remote D-Bus errors with operation, object path, and request ID | `PipeWireTelephonyException` preserves the remote error name. |
| Object safety | Removed or replaced gateways, calls, and transports are invalidated | `isValid`; commands on stale objects throw `StateError`. |
| Packaging | Native Assets, AGL/legacy Flutter Linux bundles, and explicit development override | Bundle libraries beside loaded `libapp.so` are supported; `PWT_NATIVE_LIB` is the deliberate override. |

Pairing, trust, and Bluetooth profile connection remain BlueZ responsibilities.
The package can activate and inspect SCO, but it does not route PCM audio or
manage audio focus, microphones, or speakers; those remain WirePlumber/AGL
application-policy responsibilities. Multi-call operations are exposed by the
API but can still be rejected by the phone when its current call state does not
permit them.

## Requirements

- Linux with `org.pipewire.Telephony` available on D-Bus
- Flutter 3.38.3 / Dart 3.10.1 or newer
- CMake 3.22, a C++23 compiler, Ninja or Make, and target `libsystemd`
- `sdbus-c++` submodule contents and the vendored Glaze headers

Initialize submodules in a Git checkout before building:

```sh
git submodule update --init --recursive
flutter pub get
```

## Native Assets Build

`dart run`, `dart test`, and Flutter builds invoke `hook/build.dart`. The hook
builds `libpipewire_telephony_native.so` with CMake and registers it as a bundled
`CodeAsset`, so applications do not need to copy the library manually. Git
dependencies restore the pinned sdbus-c++ submodule when repository metadata is
available; published archives must already contain its source.

When an integration such as an AGL recipe builds and installs the native library
separately, disable the hook in the application or workspace pubspec:

```yaml
hooks:
  user_defines:
    pipewire_telephony_native:
      skip_native_build: true
```

The existing Flutter Linux CMake path remains supported for those deployments.
`SKIP_NATIVE_BUILD=1` remains a compatibility fallback for hook runners that
preserve it, but standard Native Assets hooks strip undeclared environment
variables; prefer the user define above.

The hook supports a Linux target matching the host architecture. It also accepts
an explicit `cmake_toolchain_file` user define for AGL cross-builds; see the
target toolchain and prebuilt instructions below. Every native CMake build
checks the output ELF machine/class and public ABI using
`readelf` and `nm` (binutils); a foreign architecture cannot be supplied by a
host compiler.

Runtime loading uses the system loader, then the directory containing a loaded
Flutter `libapp.so`, then the declared native asset and known
executable-relative bundle locations for legacy deployments. This supports AGL
homescreen bundles whose launcher is outside the application and does not set
`LD_LIBRARY_PATH`. It never searches the working directory or directories
belonging to unrelated loaded libraries.
For a deliberate local development override, set `PWT_NATIVE_LIB` to an absolute
shared-library path.

## Dart API

The default is `PipeWireBus.automatic`: it checks the current process's session
bus first and falls back to the system bus when the service is absent or that
bus is unavailable. Construct a new client to reconnect after service loss; an
unavailable client is terminal by design.

```dart
final client = PipeWireTelephonyClient();
await client.connect();

final phone = client.gateways.first;
await phone.dial('+60123456789');

final call = phone.calls.first;
await call.answer();
await phone.sendTones('12#');
await call.hangup();

await client.close();
```

Use `gatewayAdded`, `gatewayRemoved`, `gatewayChanged`, `callAdded`,
`callRemoved`, `callChanged`, and `stateChanged` to update application state.
Objects become invalid when their D-Bus interface, parent gateway, or service
owner disappears. Methods complete from remote D-Bus replies and preserve
remote error names in `PipeWireTelephonyException`.

`startupTimeout` must be positive. `operationTimeout` must be positive and at
most 30 seconds, matching the native command deadline. A shorter timeout only
stops Dart from waiting: the remote command can still succeed, and its gateway
can stay busy until native completion or expiry. A timeout means the outcome is
unknown. Refresh state before deciding whether to retry, especially for `dial`,
which could otherwise create a second call.

## Examples

The standalone Dart examples separate discovery, watching, gateway commands and
call commands:

```sh
dart run example/telephony_list.dart
dart run example/telephony_watch.dart --seconds 30
dart run example/telephony_gateway.dart /org/pipewire/Telephony/ag1 props
dart run example/telephony_call.dart /org/pipewire/Telephony/ag1/call1 answer
```

The dedicated Flutter Linux app provides phone selection, call state and
controls, dialing, DTMF, all multi-call operations, HFP volumes, SCO state,
error reporting, and explicit reconnect.

```sh
cd example/flutter_telephony
flutter run -d linux
```

All examples use automatic discovery. Pass `--session` or `--system` to a
standalone example to force one scope. AGL applications should construct the client
with the bus used by their image, normally `PipeWireBus.system`, so deployment
and policy failures remain deterministic. Pairing/trust/profile
connection remains the BlueZ integration's responsibility. Audio routing,
focus, and microphone/speaker links remain WirePlumber/AGL policy
responsibilities.

Automatic discovery only checks buses reachable by the current process. A
desktop application and its user service normally share the session bus. A
process started with `sudo` runs under a different user identity and normally
cannot use the original user's session bus, so it can only discover a
system-bus service. Administrator privileges do not automatically grant access
to another user's private session bus.

## AGL

Cross-build and prebuilt packaging are documented in
[`doc/agl_build.md`](doc/agl_build.md). The target image must expose PipeWire
telephony on the system bus and grant the application user the destination's
D-Bus policy. Do not run the application as root to bypass missing policy.

The initial 0.1.0 package is verified on desktop Linux with private D-Bus mock
services. Real-phone call flows, two-way audio and target-prebuilt equivalence
still require validation on your AGL image; passing host tests does not establish
those deployment results.

## Verification

```sh
flutter analyze
cmake -S native -B build/native -DBUILD_TESTING=ON
cmake --build build/native
ctest --test-dir build/native --output-on-failure
./scripts/verify_host_package.sh
```

The packaging check requires a clean, publication-ready checkout and Flutter
Linux desktop build prerequisites. It checks regenerated FFI bindings, compiles
the checked-in sdbus-c++ proxy headers, exercises a relocated Flutter bundle,
and rebuilds a CLI from pub's selected publication files. CI runs this check
plus native loading and architecture regression tests; Python signal fixtures
use system Python with `python3-dbus` and `python3-gi` installed.

Native integration tests create a private D-Bus daemon and never issue call
commands to the production bus.

## Acknowledgements

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for bundled dependency
licenses and instructions for distributing applications with the native library.

- [bluez_native](https://github.com/jwinarske/bluez_native) (Apache-2.0): the
  Native Assets build hook, FFI handle lifetime, client lifecycle, Dart
  codec/type organization, library loader, native CMake configuration, and
  development-script patterns are derived from this project. Adapted files
  carry an `SPDX-License-Identifier: Apache-2.0` header.
- [appstream_dart](https://github.com/meta-flutter/appstream_dart)
  (Apache-2.0): the original pattern for dynamic-library resolution used by
  `bluez_native` and this package.
- [sdbus-c++](https://github.com/Kistler-Group/sdbus-cpp) (LGPL-2.1): the
  D-Bus C++ binding used by the native library. Its source and license are
  retained under `native/third_party/sdbus-cpp/`.
