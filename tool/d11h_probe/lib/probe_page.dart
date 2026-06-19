import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_niimbot/niimbot.dart';
import 'package:flutter_niimbot/niimbot_research.dart';
import 'package:permission_handler/permission_handler.dart';

typedef PermissionRequester = Future<bool> Function();
typedef LabelRasterRenderer =
    Future<MonochromeRaster> Function(LabelDocument document);
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
    this.rasterInterWriteDelay = const Duration(milliseconds: 30),
    this.renderLabel = _renderDefaultLabel,
  });

  final ProbeController controller;
  final PermissionRequester requestPermissions;
  final Duration scanDuration;
  final Duration rasterInterWriteDelay;
  final LabelRasterRenderer renderLabel;

  @override
  State<ProbePage> createState() => _ProbePageState();
}

Future<bool> _requestDefaultProbePermissions() => requestProbePermissions();

Future<MonochromeRaster> _renderDefaultLabel(LabelDocument document) =>
    const TextLabelRenderer().render(document);

class _ProbePageState extends State<ProbePage> {
  StreamSubscription<ProbeEvent>? _events;
  final _labelText = TextEditingController(text: 'Hello');
  final _customWidth = TextEditingController(text: '22');
  final _customHeight = TextEditingController(text: '12');
  final _mediaTotalLabels = TextEditingController();
  final _mediaCounterAtBaseline = TextEditingController();
  final _mediaRemainingAtBaseline = TextEditingController();
  var _busy = false;
  var _labelSizePreset = '12x22';
  var _labelOrientation = LabelOrientation.normal;
  var _labelAlignment = LabelTextAlignment.center;
  var _labelHorizontalPosition = LabelHorizontalPosition.center;
  var _labelFontSize = 18.0;
  var _labelWrap = true;
  Future<MonochromeRaster>? _previewFuture;
  D11hMediaProbeResult? _mediaProbeResult;

  @override
  void initState() {
    super.initState();
    _previewFuture = _renderTextLabel();
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
    _labelText.dispose();
    _customWidth.dispose();
    _customHeight.dispose();
    _mediaTotalLabels.dispose();
    _mediaCounterAtBaseline.dispose();
    _mediaRemainingAtBaseline.dispose();
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
      if (mounted) {
        setState(() => _busy = false);
      }
      return;
    }

    try {
      final characteristic = findD11hPrintCharacteristic(
        widget.controller.services,
      );
      if (characteristic != null) {
        await _readMediaProbe(characteristic);
      }
    } catch (error) {
      _showMessage('Auto media probe failed: $error');
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

  Future<void> _detectMedia(BleCharacteristic characteristic) async {
    setState(() => _busy = true);
    try {
      await _readMediaProbe(characteristic);
      _showMessage('Media probe completed.');
    } catch (error) {
      _showMessage('Media probe failed: $error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _readMediaProbe(BleCharacteristic characteristic) async {
    final result = await widget.controller.queryMediaProbe(characteristic);
    if (mounted) {
      setState(() => _mediaProbeResult = result);
    }
  }

  D11hMediaRollProfile? _mediaProfile() {
    final totalText = _mediaTotalLabels.text.trim();
    final counterText = _mediaCounterAtBaseline.text.trim();
    final remainingText = _mediaRemainingAtBaseline.text.trim();
    if (totalText.isEmpty || counterText.isEmpty || remainingText.isEmpty) {
      return null;
    }
    final total = int.tryParse(totalText);
    final counter = int.tryParse(counterText);
    final remaining = int.tryParse(remainingText);
    if (total == null ||
        total <= 0 ||
        counter == null ||
        counter < 0 ||
        remaining == null ||
        remaining < 0 ||
        remaining > total) {
      return null;
    }
    return D11hMediaRollProfile(
      totalLabels: total,
      counterAtBaseline: counter,
      remainingLabelsAtBaseline: remaining,
    );
  }

  void _useCurrentAsBaseline() {
    final result = _mediaProbeResult;
    if (result == null) {
      _showMessage('Run Detect media first.');
      return;
    }
    final info = D11hMediaInfo.fromProbeResult(result);
    final counter = info.usageCounter;
    if (counter == null) {
      _showMessage('No media counter available.');
      return;
    }
    setState(() {
      _mediaCounterAtBaseline.text = '$counter';
      final totalText = _mediaTotalLabels.text.trim();
      if (_mediaRemainingAtBaseline.text.trim().isEmpty &&
          totalText.isNotEmpty) {
        _mediaRemainingAtBaseline.text = totalText;
      }
    });
  }

  Future<void> _printTextLabel(BleCharacteristic characteristic) async {
    if (_labelText.text.trim().isEmpty) {
      _showMessage('Enter text to print.');
      return;
    }

    setState(() => _busy = true);
    try {
      final raster = await _renderTextLabel();
      await widget.controller.printRaster(
        characteristic,
        raster,
        interWriteDelay: widget.rasterInterWriteDelay,
      );
      _showMessage('Printer confirmed text label.');
    } catch (error) {
      _showMessage('Text label print failed: $error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  LabelSize _selectedLabelSize() {
    return switch (_labelSizePreset) {
      '12x22' => LabelSize.d11h12x22,
      '12x30' => LabelSize.d11h12x30,
      'custom' => LabelSize(
        widthMm: double.parse(_customWidth.text),
        heightMm: double.parse(_customHeight.text),
      ),
      _ => throw StateError('Unknown label size preset.'),
    };
  }

  LabelDocument _buildTextDocument() {
    final size = _selectedLabelSize();
    const verticalPaddingMm = 1.0;
    return LabelDocument(
      size: size,
      orientation: _labelOrientation,
      elements: <LabelElement>[
        LabelText(
          text: _labelText.text,
          xMm: 0,
          yMm: verticalPaddingMm,
          widthMm: size.widthMm,
          heightMm: size.heightMm - verticalPaddingMm * 2,
          fontSizePt: _labelFontSize,
          alignment: _labelAlignment,
          horizontalPosition: _labelHorizontalPosition,
          wrap: _labelWrap,
          bold: true,
        ),
      ],
    );
  }

  Future<MonochromeRaster> _renderTextLabel() =>
      Future<LabelDocument>.sync(_buildTextDocument).then(widget.renderLabel);

  void _refreshPreview() {
    final preview = _renderTextLabel();
    setState(() {
      _previewFuture = preview;
    });
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
            if (connected && capturedPrintCharacteristic != null) ...<Widget>[
              const SizedBox(height: 8),
              TextField(
                key: const Key('media-total-input'),
                controller: _mediaTotalLabels,
                onChanged: (_) => setState(() {}),
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Total labels',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('media-counter-baseline-input'),
                controller: _mediaCounterAtBaseline,
                onChanged: (_) => setState(() {}),
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Counter at baseline',
                  helperText: 'Use the current RFID counter at this moment.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('media-remaining-baseline-input'),
                controller: _mediaRemainingAtBaseline,
                onChanged: (_) => setState(() {}),
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Remaining labels at baseline',
                  helperText: 'For a new roll, enter the total label count.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _mediaProbeResult == null
                    ? null
                    : _useCurrentAsBaseline,
                child: const Text('Use current as baseline'),
              ),
            ],
            if (connected && capturedPrintCharacteristic != null)
              FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () => _detectMedia(capturedPrintCharacteristic),
                icon: const Icon(Icons.sensors_outlined),
                label: const Text('Detect media'),
              ),
            if (_mediaProbeResult case final result?) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                'Media probe',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              SelectableText(
                _formatMediaProbeResult(result, profile: _mediaProfile()),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ],
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
            const SizedBox(height: 16),
            _buildLabelEditor(connected ? capturedPrintCharacteristic : null),
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

  Widget _buildLabelEditor(BleCharacteristic? printCharacteristic) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('Text label', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              key: const Key('label-text-input'),
              controller: _labelText,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Text',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => _refreshPreview(),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    key: const Key('label-size-select'),
                    initialValue: _labelSizePreset,
                    decoration: const InputDecoration(
                      labelText: 'Label size',
                      border: OutlineInputBorder(),
                    ),
                    items: const <DropdownMenuItem<String>>[
                      DropdownMenuItem(
                        value: '12x22',
                        child: Text('12 x 22 mm'),
                      ),
                      DropdownMenuItem(
                        value: '12x30',
                        child: Text('12 x 30 mm'),
                      ),
                      DropdownMenuItem(value: 'custom', child: Text('Custom')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        _labelSizePreset = value;
                        _refreshPreview();
                      }
                    },
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<LabelOrientation>(
                    initialValue: _labelOrientation,
                    decoration: const InputDecoration(
                      labelText: 'Orientation',
                      border: OutlineInputBorder(),
                    ),
                    items: const <DropdownMenuItem<LabelOrientation>>[
                      DropdownMenuItem(
                        value: LabelOrientation.normal,
                        child: Text('Horizontal'),
                      ),
                      DropdownMenuItem(
                        value: LabelOrientation.rotated90,
                        child: Text('Vertical'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        _labelOrientation = value;
                        _refreshPreview();
                      }
                    },
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<LabelTextAlignment>(
                    initialValue: _labelAlignment,
                    decoration: const InputDecoration(
                      labelText: 'Alignment',
                      border: OutlineInputBorder(),
                    ),
                    items: const <DropdownMenuItem<LabelTextAlignment>>[
                      DropdownMenuItem(
                        value: LabelTextAlignment.start,
                        child: Text('Start'),
                      ),
                      DropdownMenuItem(
                        value: LabelTextAlignment.center,
                        child: Text('Center'),
                      ),
                      DropdownMenuItem(
                        value: LabelTextAlignment.end,
                        child: Text('End'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        _labelAlignment = value;
                        _refreshPreview();
                      }
                    },
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<LabelHorizontalPosition>(
                    key: const Key('label-position-select'),
                    initialValue: _labelHorizontalPosition,
                    decoration: const InputDecoration(
                      labelText: 'Label position',
                      border: OutlineInputBorder(),
                    ),
                    items: const <DropdownMenuItem<LabelHorizontalPosition>>[
                      DropdownMenuItem(
                        value: LabelHorizontalPosition.left,
                        child: Text('Left'),
                      ),
                      DropdownMenuItem(
                        value: LabelHorizontalPosition.center,
                        child: Text('Center'),
                      ),
                      DropdownMenuItem(
                        value: LabelHorizontalPosition.right,
                        child: Text('Right'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        _labelHorizontalPosition = value;
                        _refreshPreview();
                      }
                    },
                  ),
                ),
              ],
            ),
            if (_labelSizePreset == 'custom') ...<Widget>[
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _customWidth,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Width (mm)',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => _refreshPreview(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _customHeight,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Height (mm)',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => _refreshPreview(),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Text('Font size ${_labelFontSize.round()} pt'),
            Slider(
              value: _labelFontSize,
              min: 6,
              max: 32,
              divisions: 26,
              label: '${_labelFontSize.round()} pt',
              onChanged: (value) {
                _labelFontSize = value;
                _refreshPreview();
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Wrap text'),
              value: _labelWrap,
              onChanged: (value) {
                _labelWrap = value;
                _refreshPreview();
              },
            ),
            const SizedBox(height: 8),
            FutureBuilder<MonochromeRaster>(
              future: _previewFuture,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text(
                    'Preview error: ${snapshot.error}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  );
                }
                final raster = snapshot.data;
                if (raster == null) {
                  return const Center(child: Text('Rendering preview...'));
                }
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: AspectRatio(
                      aspectRatio: raster.width / raster.height,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                        child: CustomPaint(
                          key: const Key('label-preview'),
                          painter: _RasterPreviewPainter(raster),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy || printCharacteristic == null
                  ? null
                  : () => _printTextLabel(printCharacteristic),
              icon: const Icon(Icons.text_fields),
              label: const Text('Print text label'),
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

String _formatMediaProbeResult(
  D11hMediaProbeResult result, {
  D11hMediaRollProfile? profile,
}) {
  final info = D11hMediaInfo.fromProbeResult(result, profile: profile);
  final status = result.statusResponse;
  final lines = <String>[
    'State: ${info.state.name}',
    if (info.candidateSerial != null)
      'Serial candidate: ${info.candidateSerial}',
    if (info.candidateCode != null) 'Code candidate: ${info.candidateCode}',
    if (info.usageCounter != null) 'Counter: ${info.usageCounter}',
    if (info.remainingEstimate case final estimate?)
      'Remaining: ${estimate.remainingLabels} / ${estimate.totalLabels} '
          '(${estimate.remainingPercent.toStringAsFixed(1)}%)'
    else
      'Remaining: unknown',
    'Raw information 0x${_formatCommand(result.informationResponse.command)}: '
        '${result.informationResponse.payloadHex}',
  ];
  if (status != null) {
    lines.add(
      'Raw status 0x${_formatCommand(status.command)}: ${status.payloadHex}',
    );
  }
  return lines.join('\n');
}

String _formatCommand(int command) =>
    command.toRadixString(16).toUpperCase().padLeft(2, '0');

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

final class _RasterPreviewPainter extends CustomPainter {
  const _RasterPreviewPainter(this.raster);

  final MonochromeRaster raster;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final pixelWidth = size.width / raster.width;
    final pixelHeight = size.height / raster.height;
    final black = Paint()..color = Colors.black;
    for (var y = 0; y < raster.height; y++) {
      for (var x = 0; x < raster.width; x++) {
        if (raster.isBlack(x, y)) {
          canvas.drawRect(
            Rect.fromLTWH(
              x * pixelWidth,
              y * pixelHeight,
              pixelWidth,
              pixelHeight,
            ),
            black,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_RasterPreviewPainter oldDelegate) =>
      oldDelegate.raster != raster;
}
