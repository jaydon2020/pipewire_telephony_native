# PipeWire Telephony Exerciser

Run the Linux app from this directory:

```sh
flutter run -d linux
```

It connects to `org.pipewire.Telephony` on the system bus. Select a discovered
phone before issuing call, volume, multi-call, or SCO commands. The reconnect
action creates a fresh native client after PipeWire telephony service loss.

The exerciser does not pair phones or configure audio routing. Establish the
Bluetooth HFP connection through the BlueZ integration and configure SCO/audio
policy through WirePlumber or the AGL image.
