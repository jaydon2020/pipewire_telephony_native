# Flutter Telephony

Run the Linux app from this directory:

```sh
flutter run -d linux
```

It looks for `org.pipewire.Telephony` on the current process's user/session bus
and then its system bus, matching both desktop `wireplumber@bluetooth.service`
and system-scoped AGL deployments. Select a discovered phone before issuing
call, volume, multi-call, or SCO commands. The reconnect action creates a fresh
native client after PipeWire telephony service loss.

The exerciser does not pair phones or configure audio routing. Establish the
Bluetooth HFP connection through the BlueZ integration and configure SCO/audio
policy through WirePlumber or the AGL image.
