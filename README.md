# PipeWire Telephony Native

Flutter FFI access to PipeWire's Bluetooth HFP telephony D-Bus API on Linux.
The package discovers audio gateways, calls, and SCO transports and covers the
PipeWire 1.6.6 method and property surface through typed Dart objects.

## Requirements

- Linux with `org.pipewire.Telephony` available on D-Bus
- Flutter/Dart 3.13 or newer
- CMake 3.22, a C++23 compiler, Ninja or Make, and target `libsystemd`
- `sdbus-c++` submodule contents and the vendored Glaze headers

Initialize submodules in a Git checkout before building:

```sh
git submodule update --init --recursive
flutter pub get
```

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
[`docs/agl_build.md`](docs/agl_build.md). The target image must expose PipeWire
telephony on the system bus and grant the application user the destination's
D-Bus policy. Do not run the application as root to bypass missing policy.

## Verification

```sh
flutter analyze
cmake -S native -B build/native -DBUILD_TESTING=ON
cmake --build build/native
ctest --test-dir build/native --output-on-failure
./scripts/verify_host_package.sh
```

Native integration tests create a private D-Bus daemon and never issue call
commands to the production bus.
