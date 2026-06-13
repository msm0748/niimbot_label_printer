import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:niimbot_lib/niimbot_research.dart';
import 'package:permission_handler/permission_handler.dart';

typedef PermissionRequester = Future<bool> Function();
typedef PermissionBatchRequester =
    Future<Map<Permission, PermissionStatus>> Function(
      List<Permission> permissions,
    );

Future<bool> requestProbePermissions({
  bool? isAndroid,
  PermissionBatchRequester? requestPermissions,
}) async {
  if (!(isAndroid ?? Platform.isAndroid)) {
    return true;
  }

  final permissions = <Permission>[
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
  ];
  final statuses = await (requestPermissions ?? _requestPermissionBatch)(
    permissions,
  );
  return statuses.values.every((status) => status.isGranted);
}

Future<Map<Permission, PermissionStatus>> _requestPermissionBatch(
  List<Permission> permissions,
) => permissions.request();

class ProbePage extends StatefulWidget {
  const ProbePage({
    super.key,
    required this.controller,
    this.requestPermissions = _requestDefaultProbePermissions,
    this.scanDuration = const Duration(seconds: 10),
  });

  final ProbeController controller;
  final PermissionRequester requestPermissions;
  final Duration scanDuration;

  @override
  State<ProbePage> createState() => _ProbePageState();
}

Future<bool> _requestDefaultProbePermissions() => requestProbePermissions();

class _ProbePageState extends State<ProbePage> {
  StreamSubscription<ProbeEvent>? _events;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    _events = widget.controller.eventStream.listen((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    unawaited(_events?.cancel());
    unawaited(widget.controller.dispose());
    super.dispose();
  }

  Future<void> _scan() async {
    if (!await widget.requestPermissions()) {
      _showMessage('Bluetooth permission is required.');
      return;
    }

    setState(() => _busy = true);
    final timer = Timer(widget.scanDuration, () {
      unawaited(widget.controller.stopScan());
    });
    try {
      await widget.controller.startScan(timeout: widget.scanDuration);
    } catch (error) {
      _showMessage('Scan failed: $error');
    } finally {
      timer.cancel();
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _connect(BleDeviceId deviceId) async {
    setState(() => _busy = true);
    try {
      await widget.controller.connect(deviceId);
    } catch (error) {
      _showMessage('Connection failed: $error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _disconnect() async {
    setState(() => _busy = true);
    try {
      await widget.controller.disconnect();
    } catch (error) {
      _showMessage('Disconnect failed: $error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _printCapturedTestLabel(BleCharacteristic characteristic) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send one test label?'),
        content: const Text(
          'This replays the sanitized raster commands observed from the '
          'official app. Keep one label loaded and use only a D11H.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Print one label'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _busy = true);
    try {
      await widget.controller.printCapturedTestLabel(characteristic);
      _showMessage('Printer confirmed print completion.');
    } catch (error) {
      _showMessage('Captured test print failed: $error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final devices = widget.controller.devices.toList()
      ..sort((left, right) => right.rssi.compareTo(left.rssi));
    final connected = widget.controller.connectedDevice != null;
    final capturedPrintCharacteristic = _findCapturedPrintCharacteristic();

    return Scaffold(
      appBar: AppBar(
        title: const Text('NIIMBOT D11H Probe'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Copy sanitized log',
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: widget.controller.exportSanitizedLog()),
              );
              _showMessage('Sanitized log copied.');
            },
            icon: const Icon(Icons.copy_all_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            _StatusCard(
              readiness: widget.controller.readiness,
              mtu: widget.controller.mtu,
              connected: connected,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy || connected ? null : _scan,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.bluetooth_searching),
              label: const Text('Scan for D11H'),
            ),
            if (connected)
              OutlinedButton.icon(
                onPressed: _busy ? null : _disconnect,
                icon: const Icon(Icons.link_off),
                label: const Text('Disconnect'),
              ),
            if (connected && capturedPrintCharacteristic != null)
              FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () =>
                          _printCapturedTestLabel(capturedPrintCharacteristic),
                icon: const Icon(Icons.print_outlined),
                label: const Text('Print captured test label'),
              ),
            const SizedBox(height: 16),
            Text('Devices', style: Theme.of(context).textTheme.titleLarge),
            if (devices.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('No devices discovered'),
              )
            else
              ...devices.map(
                (device) => Card(
                  child: ListTile(
                    title: Text(
                      device.name?.trim().isNotEmpty == true
                          ? device.name!
                          : 'Unnamed BLE device',
                    ),
                    subtitle: Text(
                      '${displayDeviceId(device.deviceId)}  RSSI ${device.rssi}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    enabled: !_busy && !connected,
                    onTap: _busy || connected
                        ? null
                        : () => _connect(device.deviceId),
                  ),
                ),
              ),
            if (widget.controller.services.isNotEmpty) ...<Widget>[
              const SizedBox(height: 16),
              Text(
                'GATT services',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              ...widget.controller.services.map(_buildService),
            ],
            const SizedBox(height: 16),
            Text(
              'Sanitized event log',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Container(
              constraints: const BoxConstraints(minHeight: 120),
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(
                widget.controller.events.isEmpty
                    ? 'No events yet'
                    : widget.controller.exportSanitizedLog(),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  BleCharacteristic? _findCapturedPrintCharacteristic() {
    for (final service in widget.controller.services) {
      for (final characteristic in service.characteristics) {
        if (characteristic.canNotify &&
            characteristic.properties.contains(
              BleCharacteristicProperty.writeWithoutResponse,
            )) {
          return characteristic;
        }
      }
    }
    return null;
  }

  Widget _buildService(BleService service) {
    return Card(
      child: ExpansionTile(
        title: Text(service.serviceUuid),
        children: service.characteristics
            .map(
              (characteristic) => ListTile(
                title: Text(characteristic.characteristicUuid),
                subtitle: Text(
                  characteristic.properties
                      .map((value) => value.name)
                      .join(', '),
                ),
                trailing: Wrap(
                  spacing: 4,
                  children: <Widget>[
                    if (characteristic.canNotify)
                      IconButton(
                        tooltip: 'Subscribe',
                        onPressed: () async {
                          try {
                            await widget.controller.subscribe(characteristic);
                          } catch (error) {
                            _showMessage('Subscribe failed: $error');
                          }
                        },
                        icon: const Icon(Icons.notifications_active_outlined),
                      ),
                    if (characteristic.canWrite)
                      IconButton(
                        tooltip: 'Write hex',
                        onPressed: () => _showWriteDialog(characteristic),
                        icon: const Icon(Icons.send_outlined),
                      ),
                  ],
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }

  Future<void> _showWriteDialog(BleCharacteristic characteristic) async {
    final input = TextEditingController();
    var mode =
        characteristic.properties.contains(BleCharacteristicProperty.write)
        ? BleWriteMode.withResponse
        : BleWriteMode.withoutResponse;

    final shouldWrite = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Confirm raw BLE write'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text(
                'Only send bytes already observed from an authorized capture.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: input,
                decoration: const InputDecoration(
                  labelText: 'Hex bytes',
                  hintText: '55 01 aa',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<BleWriteMode>(
                initialValue: mode,
                decoration: const InputDecoration(
                  labelText: 'Write mode',
                  border: OutlineInputBorder(),
                ),
                items: <DropdownMenuItem<BleWriteMode>>[
                  if (characteristic.properties.contains(
                    BleCharacteristicProperty.write,
                  ))
                    const DropdownMenuItem(
                      value: BleWriteMode.withResponse,
                      child: Text('With response'),
                    ),
                  if (characteristic.properties.contains(
                    BleCharacteristicProperty.writeWithoutResponse,
                  ))
                    const DropdownMenuItem(
                      value: BleWriteMode.withoutResponse,
                      child: Text('Without response'),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() => mode = value);
                  }
                },
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Send bytes'),
            ),
          ],
        ),
      ),
    );

    if (shouldWrite != true || !mounted) {
      input.dispose();
      return;
    }
    try {
      await widget.controller.writeHex(characteristic, input.text, mode: mode);
    } catch (error) {
      _showMessage('Write failed: $error');
    } finally {
      input.dispose();
    }
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.readiness,
    required this.mtu,
    required this.connected,
  });

  final BleReadiness readiness;
  final int? mtu;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 16,
          runSpacing: 8,
          children: <Widget>[
            Chip(label: Text('Bluetooth ${readiness.name}')),
            Chip(label: Text(connected ? 'Connected' : 'Disconnected')),
            if (mtu case final value?) Chip(label: Text('MTU $value')),
          ],
        ),
      ),
    );
  }
}

String displayDeviceId(BleDeviceId id) {
  final value = id.value;
  return value.length <= 6 ? value : '...${value.substring(value.length - 6)}';
}
