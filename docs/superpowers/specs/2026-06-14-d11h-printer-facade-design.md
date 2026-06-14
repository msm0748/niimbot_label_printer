# D11H Printer Facade Design

## Scope

Promote the proven D11H printing path from the research API into a stable,
application-oriented facade. The package will own BLE lifecycle coordination,
printer characteristic discovery, label rendering, reconnect-before-print,
and print serialization. Applications remain responsible for permissions,
device-name filtering, label layout, preferences, and server workflows.

## Public API

The stable `niimbot.dart` entry point exports:

- `src/printer/d11h_print_characteristic.dart`
- `src/printer/d11h_printer.dart`

`D11hPrinter` provides:

```dart
D11hPrinter();

D11hPrinter.withTransport(BleTransport transport);

Future<List<BleAdvertisement>> scan({
  Duration timeout = const Duration(seconds: 10),
});

Future<void> connect(BleDeviceId id);
Future<void> disconnect();
bool get isConnected;
Future<void> printLabel(LabelDocument document);
Future<void> dispose();
```

The default constructor owns a `ReactiveBleTransport`. The transport-injecting
constructor exists for tests and custom integrations. In both cases,
`D11hPrinter` owns the supplied transport after construction and disposes it.

The stable entry point also exports the BLE transport interface and reactive
transport implementation needed by `withTransport`. Existing research exports
remain available for probe tooling, but applications do not need to import
`niimbot_research.dart`.

## Characteristic Discovery

`findD11hPrintCharacteristic(List<BleService> services)` searches only the
D11H service UUID `FFF0` and characteristic UUID `FFF1`. UUID comparison is
case-insensitive and accepts normalized 16-bit values or Bluetooth-base
128-bit values.

The helper returns the matching characteristic only when it supports both
`notify` and `writeWithoutResponse`. It returns `null` for the wrong service,
wrong characteristic, or missing required properties. It does not select an
arbitrary characteristic based only on properties.

## Lifecycle And Serialization

`D11hPrinter` wraps a private `ProbeController`. All public operations are
serialized through one FIFO asynchronous operation queue. This prevents scan,
connect, disconnect, print, and dispose operations from overlapping in ways
that violate the controller lifecycle.

Repeated callers receive independent futures completed in submission order.
Failure of one operation does not poison later queued operations. Calls made
after disposal fail with `StateError`.

`scan()` starts the controller scan, waits for its timeout-driven completion,
and returns the controller's de-duplicated advertisement snapshot. It does not
filter by printer name.

`connect(id)` stores `id` as the last selected device and connects through the
controller. When another device is already connected, it disconnects first.
Connecting the already-connected device is a no-op.

`disconnect()` disconnects the active connection but preserves the last
selected device so a later print can reconnect. It is safe when already
disconnected.

`isConnected` reflects whether the controller currently has a connected
device.

## Print Pipeline

Each `printLabel(document)` operation runs the following steps inside the same
FIFO queue:

1. Require a previously selected device. If no successful or attempted
   `connect(id)` has supplied one, throw `StateError`.
2. If disconnected, reconnect to the last selected device.
3. Render the document with `const TextLabelRenderer().render(document)`.
4. Find FFF0/FFF1 with `findD11hPrintCharacteristic(controller.services)`.
5. If the characteristic is unavailable or lacks required properties, throw
   `StateError` without attempting a write.
6. Call `controller.printRaster(characteristic, raster)`.

Rendering occurs after connection validation so an unavailable printer fails
before spending work on rasterization. A connection loss reported before a
queued print starts triggers reconnect. A connection loss during the protocol
exchange is surfaced to the caller; the next queued print attempts reconnect.

## Disposal

`dispose()` is idempotent. Once requested, new operations are rejected.
Previously queued operations complete before the queued disposal operation
runs, after which the wrapped controller and transport are disposed. This
avoids tearing down resources underneath an active print.

## Label Sizes

The stable presets remain exactly:

- `LabelSize.d11h12x22`
- `LabelSize.d11h12x30`

No 12x40 preset or application mapping is introduced.

## Error Handling

The facade preserves `BleFailure`, `TimeoutException`, rendering errors, and
protocol errors from lower layers. It adds clear `StateError` failures for:

- use after disposal;
- printing before a device has been selected;
- missing or incompatible D11H FFF0/FFF1 characteristic.

The facade does not add heartbeat, hidden retries beyond reconnect-before-
print, permission handling, or name filtering.

## Verification

Unit tests cover:

- exact UUID matching for 16-bit and Bluetooth-base 128-bit forms;
- required `notify` plus `writeWithoutResponse` properties;
- scan result de-duplication through the facade;
- connect, disconnect, and `isConnected`;
- reconnect-before-print using the remembered device;
- rendering and forwarding the raster to the established print protocol;
- FIFO print serialization and recovery after a queued failure;
- rejection when no device or print characteristic is available;
- idempotent disposal and rejection of later operations;
- stable imports from `package:flutter_niimbot/niimbot.dart`;
- continued presence of only the 12x22 and 12x30 presets.

The full Flutter test suite and static analysis must pass.
