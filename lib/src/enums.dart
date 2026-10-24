/// D-Bus scope used to find `org.pipewire.Telephony`.
///
/// [automatic] checks the current process's session bus first, then its system
/// bus. It does not grant access to another user's session bus.
enum PipeWireBus {
  /// Try the session bus, then the system bus if no service is found.
  automatic,

  /// Use only the system bus.
  system,

  /// Use only the current process's session bus.
  session,
}

/// Lifecycle of a client; unavailable and closed clients cannot reconnect.
enum PipeWireTelephonyClientState {
  /// No connection has been started.
  idle,

  /// Connecting and collecting the initial snapshot.
  connecting,

  /// Discovery is complete and commands can be submitted.
  ready,

  /// Startup failed or the service disappeared; create a new client to retry.
  unavailable,

  /// Native work is stopping and resources are being released.
  closing,

  /// Resources and streams have been closed.
  closed,
}

/// Known HFP call states reported by PipeWire.
enum PipeWireCallState {
  /// The call is active.
  active,

  /// The call is on hold.
  held,

  /// An outgoing call is being dialed.
  dialing,

  /// The remote party is being alerted.
  alerting,

  /// An incoming call is ringing.
  incoming,

  /// An incoming call is waiting while another call exists.
  waiting,

  /// The call has disconnected and may soon be removed.
  disconnected,

  /// The service returned a state not known by this package.
  unknown,
}

/// Known SCO transport states reported by PipeWire.
enum PipeWireTransportState {
  /// The transport reported an error.
  error,

  /// No SCO connection is active.
  idle,

  /// A SCO connection is being established.
  pending,

  /// The SCO connection is active.
  active,

  /// The service returned a state not known by this package.
  unknown,
}
