## 0.1.0-dev.10

* Add D11H media information parsing and remaining-label percentage estimates.
* Add default D11H media roll profiles for 12x22 (260 labels) and 12x30
  (195 labels).
* Update the internal D11H probe app to auto-detect media on connect and use the
  selected/default total label count for remaining percentage.

## 0.1.0-dev.9

* Align print characteristic discovery with d11h_probe (notify + writeWithoutResponse fallback).
* Do not require characteristic.serviceUuid to repeat FFF0 on iOS discovery results.
* Refresh GATT services when connected but the print channel is missing.

## 0.1.0-dev.8

* Add `printRenderedLabel()` for probe-style warm printing without reconnect.
* Subscribe to FFF1 notifications after connect and settle before printing.
* Remove pre-print disconnect/reconnect from `printLabel`.

## 0.1.0-dev.7

* Handle unexpected BLE link loss while connected so `isConnected` stays accurate.

## 0.1.0-dev.6

* Remove `beginPrintSession()` / `endPrintSession()` and pre-print GATT refresh.
* Print on a warm BLE connection when already connected with the D11H FFF1 characteristic.
* Reconnect only when disconnected or the print characteristic is missing.

## 0.1.0-dev.5

* Add `beginPrintSession()` / `endPrintSession()` for one reconnect per print batch.
* Refresh the GATT session before printing instead of reusing a stale connection.
* Use 30ms raster inter-write delay to match the working D11H probe app on iOS.

## 0.1.0-dev.4

* End `D11hPrinter.scan()` with `stopScan()` before the transport scan timeout.
* Wait for `BleReadiness.ready` before starting a scan.
* Expose `bluetoothReadiness` on `D11hPrinter`.

## 0.1.0-dev.3

* Connect with `connectToDevice` instead of prescan-based advertising connect to
  reduce repeated BLE churn and connection chimes.
* Restore the print session only when the D11H FFF0/FFF1 characteristic is
  missing before printing.
* Stop scan-cleanup failures from overriding a successful scan result.

## 0.1.0-dev.2

* Add strict D11H FFF0/FFF1 print characteristic discovery.
* Add the stable `D11hPrinter` facade for scanning, connection lifecycle,
  reconnect-before-print, label rendering, and serialized printing.
* Export printer and BLE transport APIs from `niimbot.dart`.
* Disconnect an active printer before starting a new scan.

## 0.1.0-dev.1

* Rename the package to `flutter_niimbot`.
* Document the public label-rendering API and current D11H-only support.
* License the package under the MIT License.
* Scaffold the Flutter package and internal D11H probe app.
