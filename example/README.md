# pipewire_telephony_native examples

The command-line Dart examples follow the focused, one-interface style used by
the sibling BlueZ packages. They require Flutter 3.38.1 or newer because the
package has a Flutter SDK dependency. Run them from the package root with
Flutter's bundled Dart SDK:

```sh
flutter pub get
dart run example/telephony_list.dart
dart run example/telephony_watch.dart --seconds 30
```

Each example checks the current process's session bus first, then its system bus.
Pass `--session` or `--system` to select one scope explicitly.

Use an object path printed by `list` for commands:

```sh
dart run example/telephony_gateway.dart /org/pipewire/Telephony/ag1 props
dart run example/telephony_gateway.dart /org/pipewire/Telephony/ag1 dial +60123456789
dart run example/telephony_gateway.dart /org/pipewire/Telephony/ag1 tones 12#
dart run example/telephony_call.dart /org/pipewire/Telephony/ag1/call1 answer
```

## Supported D-Bus API

The examples cover the complete native PipeWire telephony baseline: 11 methods,
11 readable properties, and three writable properties. All commands complete
asynchronously after the D-Bus reply. Calls created by `Dial` are discovered
through ObjectManager signals because `Dial` has no return value.

### AudioGateway1

Interface: `org.pipewire.Telephony.AudioGateway1`

| Property | D-Bus type | Access | Dart API |
| --- | --- | --- | --- |
| `Address` | `s` | Read | `gateway.address` |
| `SpeakerVolume` | `y` | Read/write, `0..15` | `gateway.speakerVolume`, `gateway.setSpeakerVolume(value)` |
| `MicrophoneVolume` | `y` | Read/write, `0..15` | `gateway.microphoneVolume`, `gateway.setMicrophoneVolume(value)` |

| Method | Signature | Dart API | Standalone command |
| --- | --- | --- | --- |
| `Dial` | `s -> ()` | `gateway.dial(number)` | `dial <number>` |
| `SendTones` | `s -> ()` | `gateway.sendTones(tones)` | `tones <tones>` |
| `HangupAll` | `() -> ()` | `gateway.hangupAll()` | `hangup-all` |
| `SwapCalls` | `() -> ()` | `gateway.swapCalls()` | `swap-calls` |
| `ReleaseAndAnswer` | `() -> ()` | `gateway.releaseAndAnswer()` | `release-and-answer` |
| `ReleaseAndSwap` | `() -> ()` | `gateway.releaseAndSwap()` | `release-and-swap` |
| `HoldAndAnswer` | `() -> ()` | `gateway.holdAndAnswer()` | `hold-and-answer` |
| `CreateMultiparty` | `() -> ()` | `gateway.createMultiparty()` | `create-multiparty` |

Use `telephony_gateway.dart <gateway_path> props` to refresh and print all
gateway and transport properties. Volume commands are `speaker <0..15>` and
`microphone <0..15>`.

### Call1

Interface: `org.pipewire.Telephony.Call1`

| Property | D-Bus type | Access | Dart API |
| --- | --- | --- | --- |
| `LineIdentification` | `s` | Read | `call.lineIdentification` |
| `IncomingLine` | `s` | Read | `call.incomingLine` |
| `Name` | `s` | Read | `call.name` |
| `Multiparty` | `b` | Read | `call.multiparty` |
| `State` | `s` | Read | `call.rawState`, `call.state` |

| Method | Signature | Dart API | Standalone command |
| --- | --- | --- | --- |
| `Answer` | `() -> ()` | `call.answer()` | `answer` |
| `Hangup` | `() -> ()` | `call.hangup()` | `hangup` |

Known call states are `active`, `held`, `dialing`, `alerting`, `incoming`,
`waiting`, and `disconnected`. A future value remains available through
`rawState` and maps to `PipeWireCallState.unknown`. Use
`telephony_call.dart <call_path> props` to refresh and print every call
property.

### AudioGatewayTransport1

Interface: `org.pipewire.Telephony.AudioGatewayTransport1`

| Property | D-Bus type | Access | Dart API |
| --- | --- | --- | --- |
| `State` | `s` | Read | `gateway.transport?.rawState`, `gateway.transport?.state` |
| `Codec` | `y` | Read | `gateway.transport?.codec` |
| `RejectSCO` | `b` | Read/write | `gateway.transport?.rejectSco`, `transport.setRejectSco(value)` |

| Method | Signature | Dart API | Standalone command |
| --- | --- | --- | --- |
| `Activate` | `() -> ()` | `transport.activate()` | `activate-sco` |

Known transport states are `error`, `idle`, `pending`, and `active`. Set
`RejectSCO` with `reject-sco <true|false>`. The transport is optional and shares
the gateway object path.

## Discovery and Events

`telephony_list.dart` prints the initial gateway, call, and transport snapshot.
`telephony_watch.dart` reports gateway and call additions, removals, and property
changes. The Dart client also exposes `stateChanged`, `gatewayAdded`,
`gatewayRemoved`, `gatewayChanged`, `callAdded`, `callRemoved`, `callChanged`,
and per-object `propertiesChanged` streams.

Method presence does not guarantee that a phone or mobile network supports a
particular multi-call operation. Unsupported operations remain visible as
`PipeWireTelephonyException` errors returned by the service.

### Standard D-Bus support

The 11-method count above covers the telephony interfaces. The client also uses
the standard D-Bus infrastructure needed to keep those objects current:

| Interface member | Purpose |
| --- | --- |
| `ObjectManager.GetManagedObjects` | Discover initial gateways and each gateway's existing calls |
| `ObjectManager.InterfacesAdded` | Discover gateways, calls, and optional transports added at runtime |
| `ObjectManager.InterfacesRemoved` | Invalidate removed objects and same-path object identities |
| `Properties.PropertiesChanged` | Apply partial property updates and invalidations |
| `Properties.GetAll` | Refresh complete gateway, call, or transport property state |
| `Properties.Set` | Write speaker volume, microphone volume, and `RejectSCO` |

These members are handled by `PipeWireTelephonyClient`; applications use the
typed objects, refresh methods, setters, and streams rather than issuing raw
D-Bus messages.

## Flutter Telephony

The dedicated `flutter_telephony` Linux app provides the full gateway, call,
multi-call, volume, and SCO interface with live state and explicit reconnect.

```sh
cd example/flutter_telephony
flutter run -d linux
```
