/*
 * Copyright (c) 2026 Jian De jiande2020@gmail.com. All rights reserved.
 *
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pipewire_telephony_native/pipewire_telephony_native.dart';

void main() => runApp(const TelephonyExample());

class TelephonyExample extends StatelessWidget {
  const TelephonyExample({super.key, this.bus = PipeWireBus.automatic});

  final PipeWireBus bus;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'PipeWire Telephony',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff006c67),
        surface: const Color(0xfffafafa),
      ),
      scaffoldBackgroundColor: const Color(0xfff5f6f7),
      cardTheme: const CardThemeData(
        margin: EdgeInsets.zero,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(6)),
          side: BorderSide(color: Color(0xffd9dddf)),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        isDense: true,
      ),
      useMaterial3: true,
    ),
    home: TelephonyScreen(bus: bus),
  );
}

class TelephonyScreen extends StatefulWidget {
  const TelephonyScreen({super.key, required this.bus});

  final PipeWireBus bus;

  @override
  State<TelephonyScreen> createState() => _TelephonyScreenState();
}

class _TelephonyScreenState extends State<TelephonyScreen> {
  final _dialController = TextEditingController();
  final _tonesController = TextEditingController();
  final _subscriptions = <StreamSubscription<Object?>>[];
  late PipeWireTelephonyClient _client;
  String? _selectedPath;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _replaceClient();
  }

  void _replaceClient() {
    _client = PipeWireTelephonyClient(bus: widget.bus);
    _subscriptions.addAll([
      _client.stateChanged.listen((_) => _redraw()),
      _client.gatewayAdded.listen((_) => _redraw()),
      _client.gatewayRemoved.listen((_) => _redraw()),
      _client.gatewayChanged.listen((_) => _redraw()),
      _client.callAdded.listen((_) => _redraw()),
      _client.callRemoved.listen((_) => _redraw()),
      _client.callChanged.listen((_) => _redraw()),
    ]);
    unawaited(_connect());
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _client.connect();
    } catch (error) {
      _error = error.toString();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reconnect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    await _client.close();
    _selectedPath = null;
    if (!mounted) return;
    _replaceClient();
  }

  void _redraw() {
    if (!mounted) return;
    final paths = _client.gateways.map((gateway) => gateway.objectPath);
    if (_selectedPath == null || !paths.contains(_selectedPath)) {
      _selectedPath = _client.gateways.firstOrNull?.objectPath;
    }
    if (_client.state == PipeWireTelephonyClientState.unavailable) {
      _error = _client.lastError?.toString();
    }
    setState(() {});
  }

  PipeWireAudioGateway? get _selectedGateway {
    for (final gateway in _client.gateways) {
      if (gateway.objectPath == _selectedPath) return gateway;
    }
    return null;
  }

  Future<void> _run(Future<void> Function() command) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await command();
    } catch (error) {
      _error = error.toString();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_client.close());
    _dialController.dispose();
    _tonesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gateway = _selectedGateway;
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          compact ? 'Telephony: ${_client.state.name}' : 'PipeWire Telephony',
        ),
        actions: [
          if (!compact) _StateBadge(state: _client.state),
          IconButton(
            key: const Key('refresh'),
            tooltip: 'Refresh',
            onPressed:
                _busy || _client.state != PipeWireTelephonyClientState.ready
                ? null
                : () => _run(_client.refresh),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            key: const Key('reconnect'),
            tooltip: 'Reconnect',
            onPressed: _busy ? null : _reconnect,
            icon: const Icon(Icons.sync),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          if (_error case final error?)
            MaterialBanner(
              key: const Key('error-banner'),
              content: Text(error),
              leading: const Icon(Icons.error_outline),
              actions: [
                TextButton(
                  onPressed: _busy ? null : _reconnect,
                  child: const Text('Reconnect'),
                ),
              ],
            ),
          Expanded(
            child: _client.state == PipeWireTelephonyClientState.ready
                ? _buildReady(gateway)
                : const Center(child: CircularProgressIndicator()),
          ),
        ],
      ),
    );
  }

  Widget _buildReady(PipeWireAudioGateway? gateway) {
    if (_client.gateways.isEmpty) {
      return const Center(
        key: Key('empty-gateways'),
        child: Text('No connected phones'),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 900) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 260,
                child: _PhoneList(
                  gateways: _client.gateways,
                  selectedPath: _selectedPath,
                  onSelected: _selectGateway,
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: _GatewayView(
                  gateway: gateway!,
                  busy: _busy,
                  dialController: _dialController,
                  tonesController: _tonesController,
                  run: _run,
                ),
              ),
            ],
          );
        }
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: DropdownButtonFormField<String>(
                key: const Key('phone-selector'),
                initialValue: _selectedPath,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Phone',
                  prefixIcon: Icon(Icons.phone_android),
                ),
                items: [
                  for (final item in _client.gateways)
                    DropdownMenuItem(
                      value: item.objectPath,
                      child: Text(item.address ?? item.objectPath),
                    ),
                ],
                onChanged: _busy ? null : (value) => _selectGateway(value!),
              ),
            ),
            Expanded(
              child: _GatewayView(
                gateway: gateway!,
                busy: _busy,
                dialController: _dialController,
                tonesController: _tonesController,
                run: _run,
              ),
            ),
          ],
        );
      },
    );
  }

  void _selectGateway(String path) => setState(() => _selectedPath = path);
}

class _StateBadge extends StatelessWidget {
  const _StateBadge({required this.state});

  final PipeWireTelephonyClientState state;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: state.name,
          child: Icon(
            state == PipeWireTelephonyClientState.ready
                ? Icons.check_circle_outline
                : Icons.circle_outlined,
            size: 18,
          ),
        ),
        const SizedBox(width: 6),
        Text(state.name),
      ],
    ),
  );
}

class _PhoneList extends StatelessWidget {
  const _PhoneList({
    required this.gateways,
    required this.selectedPath,
    required this.onSelected,
  });

  final List<PipeWireAudioGateway> gateways;
  final String? selectedPath;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.symmetric(vertical: 8),
    children: [
      for (final gateway in gateways)
        ListTile(
          selected: gateway.objectPath == selectedPath,
          leading: const Icon(Icons.phone_android),
          title: Text(gateway.address ?? 'Unknown phone'),
          subtitle: Text('${gateway.calls.length} calls'),
          onTap: () => onSelected(gateway.objectPath),
        ),
    ],
  );
}

class _GatewayView extends StatelessWidget {
  const _GatewayView({
    required this.gateway,
    required this.busy,
    required this.dialController,
    required this.tonesController,
    required this.run,
  });

  final PipeWireAudioGateway gateway;
  final bool busy;
  final TextEditingController dialController;
  final TextEditingController tonesController;
  final Future<void> Function(Future<void> Function()) run;

  @override
  Widget build(BuildContext context) => ListView(
    key: ValueKey(gateway.objectPath),
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        gateway.address ?? 'Unknown phone',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 4),
      Text(gateway.objectPath, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 20),
      _DialControls(
        gateway: gateway,
        busy: busy,
        dialController: dialController,
        tonesController: tonesController,
        run: run,
      ),
      const SizedBox(height: 24),
      _SectionTitle(title: 'Calls', trailing: '${gateway.calls.length}'),
      const SizedBox(height: 10),
      if (gateway.calls.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Text('No active calls'),
        )
      else
        for (final call in gateway.calls) ...[
          _CallCard(call: call, busy: busy, run: run),
          const SizedBox(height: 10),
        ],
      const SizedBox(height: 14),
      _MultiCallControls(gateway: gateway, busy: busy, run: run),
      const Divider(height: 40),
      _VolumeControls(gateway: gateway, busy: busy, run: run),
      const Divider(height: 40),
      _TransportControls(gateway: gateway, busy: busy, run: run),
    ],
  );
}

class _DialControls extends StatelessWidget {
  const _DialControls({
    required this.gateway,
    required this.busy,
    required this.dialController,
    required this.tonesController,
    required this.run,
  });

  final PipeWireAudioGateway gateway;
  final bool busy;
  final TextEditingController dialController;
  final TextEditingController tonesController;
  final Future<void> Function(Future<void> Function()) run;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 12,
    runSpacing: 12,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      SizedBox(
        width: 280,
        child: TextField(
          key: const Key('dial-input'),
          controller: dialController,
          decoration: const InputDecoration(
            labelText: 'Number',
            prefixIcon: Icon(Icons.dialpad),
          ),
        ),
      ),
      IconButton.filled(
        key: const Key('dial'),
        tooltip: 'Dial',
        onPressed: busy
            ? null
            : () => run(() => gateway.dial(dialController.text)),
        icon: const Icon(Icons.call),
      ),
      SizedBox(
        width: 200,
        child: TextField(
          key: const Key('tones-input'),
          controller: tonesController,
          decoration: const InputDecoration(
            labelText: 'DTMF',
            prefixIcon: Icon(Icons.tag),
          ),
        ),
      ),
      IconButton.outlined(
        key: const Key('send-tones'),
        tooltip: 'Send tones',
        onPressed: busy
            ? null
            : () => run(() => gateway.sendTones(tonesController.text)),
        icon: const Icon(Icons.send),
      ),
      IconButton.outlined(
        key: const Key('hangup-all'),
        tooltip: 'Hang up all',
        onPressed: busy ? null : () => run(gateway.hangupAll),
        icon: const Icon(Icons.call_end),
      ),
    ],
  );
}

class _CallCard extends StatelessWidget {
  const _CallCard({required this.call, required this.busy, required this.run});

  final PipeWireCall call;
  final bool busy;
  final Future<void> Function(Future<void> Function()) run;

  @override
  Widget build(BuildContext context) {
    final state = call.state?.name ?? call.rawState ?? 'unknown';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              child: Icon(
                call.multiparty == true ? Icons.groups : Icons.person,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    call.name?.isNotEmpty == true
                        ? call.name!
                        : 'Unknown caller',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(call.lineIdentification ?? 'Number unavailable'),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 16,
                    children: [
                      Text('State: $state', key: const Key('call-state')),
                      Text('Line: ${call.incomingLine ?? '-'}'),
                      Text(
                        'Multiparty: ${call.multiparty == true ? 'yes' : 'no'}',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton.filledTonal(
              key: const Key('answer-call'),
              tooltip: 'Answer',
              onPressed: busy ? null : () => run(call.answer),
              icon: const Icon(Icons.call),
            ),
            const SizedBox(width: 8),
            IconButton.outlined(
              key: const Key('hangup-call'),
              tooltip: 'Hang up',
              onPressed: busy ? null : () => run(call.hangup),
              icon: const Icon(Icons.call_end),
            ),
          ],
        ),
      ),
    );
  }
}

class _MultiCallControls extends StatelessWidget {
  const _MultiCallControls({
    required this.gateway,
    required this.busy,
    required this.run,
  });

  final PipeWireAudioGateway gateway;
  final bool busy;
  final Future<void> Function(Future<void> Function()) run;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      OutlinedButton.icon(
        key: const Key('swap-calls'),
        onPressed: busy ? null : () => run(gateway.swapCalls),
        icon: const Icon(Icons.swap_calls),
        label: const Text('Swap'),
      ),
      OutlinedButton.icon(
        onPressed: busy ? null : () => run(gateway.releaseAndAnswer),
        icon: const Icon(Icons.phone_callback),
        label: const Text('Release + answer'),
      ),
      OutlinedButton.icon(
        onPressed: busy ? null : () => run(gateway.releaseAndSwap),
        icon: const Icon(Icons.swap_horiz),
        label: const Text('Release + swap'),
      ),
      OutlinedButton.icon(
        onPressed: busy ? null : () => run(gateway.holdAndAnswer),
        icon: const Icon(Icons.pause_circle_outline),
        label: const Text('Hold + answer'),
      ),
      OutlinedButton.icon(
        onPressed: busy ? null : () => run(gateway.createMultiparty),
        icon: const Icon(Icons.group_add),
        label: const Text('Conference'),
      ),
    ],
  );
}

class _VolumeControls extends StatelessWidget {
  const _VolumeControls({
    required this.gateway,
    required this.busy,
    required this.run,
  });

  final PipeWireAudioGateway gateway;
  final bool busy;
  final Future<void> Function(Future<void> Function()) run;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _SectionTitle(title: 'HFP volume'),
      _VolumeSlider(
        icon: Icons.volume_up,
        label: 'Speaker',
        value: gateway.speakerVolume,
        busy: busy,
        onChanged: (value) => run(() => gateway.setSpeakerVolume(value)),
      ),
      _VolumeSlider(
        icon: Icons.mic,
        label: 'Microphone',
        value: gateway.microphoneVolume,
        busy: busy,
        onChanged: (value) => run(() => gateway.setMicrophoneVolume(value)),
      ),
    ],
  );
}

class _VolumeSlider extends StatelessWidget {
  const _VolumeSlider({
    required this.icon,
    required this.label,
    required this.value,
    required this.busy,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final int? value;
  final bool busy;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon),
      const SizedBox(width: 10),
      SizedBox(width: 92, child: Text(label)),
      Expanded(
        child: Slider(
          value: (value ?? 0).toDouble(),
          max: 15,
          divisions: 15,
          label: value?.toString() ?? '-',
          onChanged: busy || value == null ? null : (_) {},
          onChangeEnd: busy || value == null
              ? null
              : (next) => onChanged(next.round()),
        ),
      ),
      SizedBox(width: 24, child: Text(value?.toString() ?? '-')),
    ],
  );
}

class _TransportControls extends StatelessWidget {
  const _TransportControls({
    required this.gateway,
    required this.busy,
    required this.run,
  });

  final PipeWireAudioGateway gateway;
  final bool busy;
  final Future<void> Function(Future<void> Function()) run;

  @override
  Widget build(BuildContext context) {
    final transport = gateway.transport;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(title: 'SCO transport'),
        const SizedBox(height: 8),
        if (transport == null)
          const Text('Transport unavailable')
        else ...[
          Wrap(
            spacing: 24,
            runSpacing: 8,
            children: [
              Text(
                'State: ${transport.state?.name ?? transport.rawState ?? '-'}',
              ),
              Text('Codec: ${transport.codec?.toString() ?? '-'}'),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: busy ? null : () => run(transport.activate),
                icon: const Icon(Icons.headset),
                label: const Text('Activate SCO'),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Reject SCO'),
                  Switch(
                    value: transport.rejectSco ?? false,
                    onChanged: busy || transport.rejectSco == null
                        ? null
                        : (value) => run(() => transport.setRejectSco(value)),
                  ),
                ],
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(title, style: Theme.of(context).textTheme.titleMedium),
      if (trailing case final value?) ...[
        const SizedBox(width: 8),
        Text(value, style: Theme.of(context).textTheme.bodySmall),
      ],
    ],
  );
}
