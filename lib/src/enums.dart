/// D-Bus scope used to find `org.pipewire.Telephony`.
///
/// [automatic] checks the current process's session bus first, then its system
/// bus. It does not grant access to another user's session bus.
enum PipeWireBus { automatic, system, session }

enum PipeWireTelephonyClientState {
  idle,
  connecting,
  ready,
  unavailable,
  closing,
  closed,
}

enum PipeWireCallState {
  active,
  held,
  dialing,
  alerting,
  incoming,
  waiting,
  disconnected,
  unknown,
}

enum PipeWireTransportState { error, idle, pending, active, unknown }
