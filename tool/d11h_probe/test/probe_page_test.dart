import 'dart:async';
import 'dart:typed_data';

import 'package:d11h_probe/probe_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_niimbot/niimbot.dart';
import 'package:flutter_niimbot/niimbot_research.dart';

void main() {
  test('uses conservative raster pacing by default', () {
    final controller = ProbeController(_ProbeTestTransport());
    final page = ProbePage(
      controller: controller,
      requestPermissions: () async => true,
    );

    expect(page.rasterInterWriteDelay, const Duration(milliseconds: 30));
  });

  testWidgets('shows scan action and empty-state guidance', (tester) async {
    final controller = ProbeController(_ProbeTestTransport());

    await tester.pumpWidget(
      MaterialApp(
        home: ProbePage(
          controller: controller,
          requestPermissions: () async => true,
        ),
      ),
    );

    expect(find.text('Scan for D11H'), findsOneWidget);
    expect(find.text('No devices discovered'), findsOneWidget);
  });

  testWidgets('discovers and connects to a selected printer', (tester) async {
    final transport = _ProbeTestTransport();
    final controller = ProbeController(transport);

    await tester.pumpWidget(
      MaterialApp(
        home: ProbePage(
          controller: controller,
          requestPermissions: () async => true,
          scanDuration: const Duration(milliseconds: 20),
          rasterInterWriteDelay: Duration.zero,
        ),
      ),
    );

    await tester.tap(find.text('Scan for D11H'));
    await tester.pump();
    transport.emitAdvertisement();
    await tester.pump();

    expect(find.text('D11_H'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 25));
    await tester.pumpAndSettle();
    await tester.tap(find.text('D11_H'));
    await tester.pumpAndSettle();

    expect(find.text('MTU 185'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('GATT services'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('fff0'), findsWidgets);
  });

  testWidgets('confirms and sends the captured test print', (tester) async {
    final transport = _ProbeTestTransport();
    final controller = ProbeController(transport);

    await tester.pumpWidget(
      MaterialApp(
        home: ProbePage(
          controller: controller,
          requestPermissions: () async => true,
          scanDuration: const Duration(milliseconds: 20),
          rasterInterWriteDelay: Duration.zero,
        ),
      ),
    );

    await tester.tap(find.text('Scan for D11H'));
    await tester.pump();
    transport.emitAdvertisement();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 25));
    await tester.pumpAndSettle();
    await tester.tap(find.text('D11_H'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Print captured test label'));
    await tester.pumpAndSettle();
    expect(find.text('Send one test label?'), findsOneWidget);

    await tester.tap(find.text('Print one label'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    expect(transport.writeCount, 15);
    expect(find.text('Printer confirmed print completion.'), findsOneWidget);
  });

  testWidgets('prints user-entered text with selected label options', (
    tester,
  ) async {
    final transport = _ProbeTestTransport();
    final controller = ProbeController(transport);
    LabelDocument? renderedDocument;

    await tester.pumpWidget(
      MaterialApp(
        home: ProbePage(
          controller: controller,
          requestPermissions: () async => true,
          scanDuration: const Duration(milliseconds: 20),
          rasterInterWriteDelay: Duration.zero,
          renderLabel: (document) async {
            renderedDocument = document;
            return MonochromeRaster(
              width: document.widthDots,
              height: document.heightDots,
              pixels: Uint8List(document.widthDots * document.heightDots),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('Scan for D11H'));
    await tester.pump();
    transport.emitAdvertisement();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 25));
    await tester.pumpAndSettle();
    await tester.tap(find.text('D11_H'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('label-text-input')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('label-text-input')),
      'Codex label',
    );
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    final sizeDropdown = tester.widget<DropdownButton<String>>(
      find.descendant(
        of: find.byKey(const Key('label-size-select')),
        matching: find.byType(DropdownButton<String>),
      ),
    );
    sizeDropdown.onChanged?.call('12x30');
    await tester.pumpAndSettle();
    final positionDropdown = tester
        .widget<DropdownButton<LabelHorizontalPosition>>(
          find.descendant(
            of: find.byKey(const Key('label-position-select')),
            matching: find.byType(DropdownButton<LabelHorizontalPosition>),
          ),
        );
    positionDropdown.onChanged?.call(LabelHorizontalPosition.right);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Print text label'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    final printButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Print text label'),
    );
    expect(printButton.onPressed, isNotNull);
    await tester.tap(find.text('Print text label'));
    for (
      var attempt = 0;
      attempt < 200 && transport.rasterDataWriteCount < 1;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    await tester.pumpAndSettle();

    expect(renderedDocument?.size.widthMm, 30);
    expect(renderedDocument?.size.heightMm, 12);
    final text = renderedDocument!.elements.single as LabelText;
    expect(text.horizontalPosition, LabelHorizontalPosition.right);
    expect(text.xMm, 0);
    expect(text.widthMm, 30);
    expect(text.yMm, 1);
    expect(text.heightMm, 10);
    expect(transport.rasterDataWriteCount, 1);
    final message = tester.widget<Text>(
      find.descendant(of: find.byType(SnackBar), matching: find.byType(Text)),
    );
    expect(message.data, 'Printer confirmed text label.');
  });

  testWidgets('detects media with profile and renders remaining percent', (
    tester,
  ) async {
    final transport = _ProbeTestTransport();
    final controller = ProbeController(transport);

    await tester.pumpWidget(
      MaterialApp(
        home: ProbePage(
          controller: controller,
          requestPermissions: () async => true,
          scanDuration: const Duration(milliseconds: 20),
          rasterInterWriteDelay: Duration.zero,
        ),
      ),
    );

    await tester.tap(find.text('Scan for D11H'));
    await tester.pump();
    transport.emitAdvertisement();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 25));
    await tester.pumpAndSettle();
    await tester.tap(find.text('D11_H'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('media-total-input')), '260');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Media probe'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('State: loaded'), findsOneWidget);
    expect(find.textContaining('Counter: 257'), findsOneWidget);
    expect(find.textContaining('Remaining: 259 / 260 (99.6%)'), findsOneWidget);
    expect(
      find.textContaining('Raw status 0xB3: 00 01 64 64 15 16 00 00'),
      findsOneWidget,
    );
  });

  testWidgets('uses default total labels when total input is empty', (
    tester,
  ) async {
    final transport = _ProbeTestTransport(mediaCounter: 456);
    final controller = ProbeController(transport);

    await tester.pumpWidget(
      MaterialApp(
        home: ProbePage(
          controller: controller,
          requestPermissions: () async => true,
          scanDuration: const Duration(milliseconds: 20),
          rasterInterWriteDelay: Duration.zero,
        ),
      ),
    );

    await tester.tap(find.text('Scan for D11H'));
    await tester.pump();
    transport.emitAdvertisement();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 25));
    await tester.pumpAndSettle();
    await tester.tap(find.text('D11_H'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Media probe'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Counter: 456'), findsOneWidget);
    expect(find.textContaining('Remaining: 60 / 260 (23.1%)'), findsOneWidget);
  });

  testWidgets('uses total labels and detected counter for used-roll percent', (
    tester,
  ) async {
    final transport = _ProbeTestTransport(mediaCounter: 456);
    final controller = ProbeController(transport);

    await tester.pumpWidget(
      MaterialApp(
        home: ProbePage(
          controller: controller,
          requestPermissions: () async => true,
          scanDuration: const Duration(milliseconds: 20),
          rasterInterWriteDelay: Duration.zero,
        ),
      ),
    );

    await tester.tap(find.text('Scan for D11H'));
    await tester.pump();
    transport.emitAdvertisement();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 25));
    await tester.pumpAndSettle();
    await tester.tap(find.text('D11_H'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('media-total-input')), '260');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Media probe'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Counter: 456'), findsOneWidget);
    expect(find.textContaining('Remaining: 60 / 260 (23.1%)'), findsOneWidget);
    expect(find.byKey(const Key('media-counter-baseline-input')), findsNothing);
    expect(
      find.byKey(const Key('media-remaining-baseline-input')),
      findsNothing,
    );
    expect(find.text('Save tracking profile'), findsNothing);
  });
}

final class _ProbeTestTransport implements BleTransport {
  _ProbeTestTransport({this.mediaCounter = 257});

  final _scan = StreamController<BleAdvertisement>.broadcast();
  final _connections = StreamController<BleConnectionUpdate>.broadcast(
    sync: true,
  );
  final _notifications = StreamController<Uint8List>.broadcast(sync: true);
  final int mediaCounter;
  int writeCount = 0;
  int rasterDataWriteCount = 0;

  @override
  BleReadiness get currentReadiness => BleReadiness.ready;

  @override
  Stream<BleReadiness> get readiness => const Stream<BleReadiness>.empty();

  void emitAdvertisement() {
    _scan.add(
      BleAdvertisement(
        deviceId: const BleDeviceId('test-device'),
        name: 'D11_H',
        rssi: -42,
        manufacturerData: Uint8List(0),
        serviceUuids: const <String>['fff0'],
      ),
    );
  }

  @override
  Stream<BleAdvertisement> scan({
    Duration timeout = const Duration(seconds: 10),
  }) => _scan.stream;

  @override
  Future<void> stopScan() async {}

  @override
  Stream<BleConnectionUpdate> connect(
    BleDeviceId deviceId, {
    Duration timeout = const Duration(seconds: 10),
  }) {
    scheduleMicrotask(() {
      _connections.add(
        BleConnectionUpdate(
          deviceId: deviceId,
          status: BleConnectionStatus.connected,
        ),
      );
    });
    return _connections.stream;
  }

  @override
  Future<void> disconnect(BleDeviceId deviceId) async {
    _connections.add(
      BleConnectionUpdate(
        deviceId: deviceId,
        status: BleConnectionStatus.disconnected,
      ),
    );
  }

  @override
  Future<List<BleService>> discoverServices(BleDeviceId deviceId) async {
    return <BleService>[
      BleService(
        serviceUuid: 'fff0',
        characteristics: <BleCharacteristic>[
          BleCharacteristic(
            serviceUuid: 'fff0',
            characteristicUuid: 'fff1',
            properties: const <BleCharacteristicProperty>{
              BleCharacteristicProperty.notify,
              BleCharacteristicProperty.writeWithoutResponse,
            },
          ),
        ],
      ),
    ];
  }

  @override
  Stream<Uint8List> subscribe(
    BleDeviceId deviceId,
    BleCharacteristic characteristic,
  ) => _notifications.stream;

  @override
  Future<void> write(
    BleDeviceId deviceId,
    BleCharacteristic characteristic,
    Uint8List bytes, {
    required BleWriteMode mode,
  }) async {
    writeCount++;
    final command = splitD11hFrames(bytes).first[2];
    final response = switch (command) {
      0x2C => '55 55 00 01 01 00 AA AA',
      0x23 => '55 55 33 01 01 33 AA AA',
      0x21 => '55 55 31 01 01 31 AA AA',
      0x01 => '55 55 02 01 01 02 AA AA',
      0x03 => '55 55 04 01 01 04 AA AA',
      0x13 => '55 55 14 02 01 00 17 AA AA',
      0x15 => '55 55 16 01 01 16 AA AA',
      0x84 => '55 55 D3 03 01 02 01 D2 AA AA',
      0x1A => formatHexBytes(
        buildD11hCommand(0x1B, <int>[
          0x88,
          0x1d,
          0x35,
          0xd3,
          0x07,
          0x97,
          0x00,
          0x00,
          0x0d,
          0x36,
          0x39,
          0x37,
          0x32,
          0x38,
          0x34,
          0x32,
          0x37,
          0x34,
          0x37,
          0x35,
          0x34,
          0x39,
          0x10,
          0x50,
          0x43,
          0x30,
          0x47,
          0x34,
          0x32,
          0x38,
          0x33,
          0x33,
          0x30,
          0x30,
          0x30,
          0x35,
          0x34,
          0x36,
          0x34,
          0x01,
          0x38,
          0x00,
          mediaCounter & 0xFF,
          mediaCounter >> 8,
        ]),
      ),
      0xA3 => '55 55 B3 08 00 01 64 64 15 16 00 00 B9 AA AA',
      0xE3 => '55 55 E4 01 01 E4 AA AA',
      0xF3 => '55 55 F4 01 01 F4 AA AA',
      0x19 => '55 55 00 01 01 00 AA AA',
      0x85 => null,
      _ => throw StateError('Unexpected command $command'),
    };
    if (command == 0x84 || command == 0x85) {
      rasterDataWriteCount++;
    }
    if (response != null) {
      scheduleMicrotask(() => _notifications.add(parseHexBytes(response)));
    }
  }

  @override
  Future<int> requestMtu(BleDeviceId deviceId, int requestedMtu) async => 185;

  @override
  Future<void> dispose() async {
    await _scan.close();
    await _connections.close();
    await _notifications.close();
  }
}
