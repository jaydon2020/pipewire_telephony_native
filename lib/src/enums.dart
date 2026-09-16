enum PipeWireBus { system, session }

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
