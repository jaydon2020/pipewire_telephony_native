# pipewire_telephony_native examples

The standalone Dart example follows the CLI style used by the sibling BlueZ
packages. Run it from the package root after building the native library:

```sh
dart run example/telephony.dart list
dart run example/telephony.dart watch --seconds 30
```

Desktop WirePlumber normally publishes `org.pipewire.Telephony` on the user bus.
Pass `--system` when the target image publishes it on the system bus.

Use an object path printed by `list` for commands:

```sh
dart run example/telephony.dart gateway /org/pipewire/Telephony/ag1 props
dart run example/telephony.dart gateway /org/pipewire/Telephony/ag1 dial +60123456789
dart run example/telephony.dart gateway /org/pipewire/Telephony/ag1 tones 12#
dart run example/telephony.dart call /org/pipewire/Telephony/ag1/call1 answer
```

## Flutter Telephony

The dedicated `flutter_telephony` Linux app provides the full gateway, call,
multi-call, volume, and SCO interface with live state and explicit reconnect.

```sh
cd example/flutter_telephony
flutter run -d linux
```
