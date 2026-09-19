# pipewire_telephony_native examples

The standalone Dart examples follow the focused, one-interface style used by
the sibling BlueZ packages. Run them from the package root after building the
native library:

```sh
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

## Flutter Telephony

The dedicated `flutter_telephony` Linux app provides the full gateway, call,
multi-call, volume, and SCO interface with live state and explicit reconnect.

```sh
cd example/flutter_telephony
flutter run -d linux
```
