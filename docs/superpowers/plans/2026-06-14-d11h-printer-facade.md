# D11H Printer Facade Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a stable D11H application facade that discovers the print characteristic, coordinates BLE lifecycle, reconnects before printing, and serializes print requests.

**Architecture:** Keep `ProbeController` as the proven low-level protocol engine and add focused files under `lib/src/printer`. A strict UUID helper identifies FFF0/FFF1, while `D11hPrinter` owns a controller and runs all lifecycle operations through a failure-tolerant FIFO future queue.

**Tech Stack:** Dart 3.11, Flutter 3.41, `flutter_reactive_ble`, `flutter_test`

---

## File Structure

- Create `lib/src/printer/d11h_print_characteristic.dart`: strict D11H UUID and property matching.
- Create `lib/src/printer/d11h_printer.dart`: stable lifecycle and label-printing facade.
- Create `test/printer/d11h_print_characteristic_test.dart`: helper behavior.
- Create `test/printer/d11h_printer_test.dart`: scan, connection, reconnect, print serialization, and disposal behavior.
- Modify `test/support/fake_ble_transport.dart`: observable connection and write controls needed by facade tests.
- Modify `lib/niimbot.dart`: stable printer and transport exports.
- Modify `test/niimbot_test.dart`: compile-time stable API coverage.
- Modify `README.md`: stable printing usage and API status.
- Modify `CHANGELOG.md`: record the new stable facade.

### Task 1: D11H Print Characteristic Helper

- [ ] Write tests that call `findD11hPrintCharacteristic()` through `niimbot.dart` and cover lowercase/uppercase 16-bit UUIDs, Bluetooth-base 128-bit UUIDs, wrong service, wrong characteristic, and missing properties.
- [ ] Run `flutter test test/printer/d11h_print_characteristic_test.dart` and confirm failure because the helper is absent.
- [ ] Implement UUID normalization local to `d11h_print_characteristic.dart` and require exact FFF0/FFF1 plus `notify` and `writeWithoutResponse`.
- [ ] Export the helper from `niimbot.dart`.
- [ ] Re-run the focused test and confirm it passes.

### Task 2: D11hPrinter Lifecycle Facade

- [ ] Extend `FakeBleTransport` with optional connection auto-completion and write blocking without changing existing test defaults.
- [ ] Write focused tests for scan snapshots, connect/disconnect state, remembered-device reconnect, missing selected device, missing characteristic, FIFO print execution, queue recovery after failure, and idempotent disposal.
- [ ] Run `flutter test test/printer/d11h_printer_test.dart` and confirm failure because `D11hPrinter` is absent.
- [ ] Implement a private FIFO operation queue that chains operations after both successful and failed predecessors.
- [ ] Implement `D11hPrinter()` with `ReactiveBleTransport`, `D11hPrinter.withTransport()`, `scan`, `connect`, `disconnect`, `isConnected`, `printLabel`, and `dispose`.
- [ ] Route printing through `TextLabelRenderer`, the characteristic helper, and `ProbeController.printRaster`.
- [ ] Export `D11hPrinter`, `BleTransport`, and `ReactiveBleTransport` from `niimbot.dart`.
- [ ] Re-run the focused facade tests and confirm they pass.

### Task 3: Stable API And Documentation

- [ ] Add a stable import test that constructs the facade and references both stable label presets without importing `niimbot_research.dart`.
- [ ] Update README usage to show scan, connect, `printLabel`, disconnect, and dispose through `niimbot.dart`.
- [ ] Update API status so the app facade is stable while probe internals remain experimental.
- [ ] Add a changelog entry for characteristic discovery, lifecycle coordination, reconnect-before-print, serialization, and stable exports.
- [ ] Run `dart format lib test`.
- [ ] Run `flutter test`.
- [ ] Run `flutter analyze`.
- [ ] Run `git diff --check`.
- [ ] Review the diff against every requirement in the design document.
