# D11H Text Label Printing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Print user-configured text labels on 12x22 mm, 12x30 mm, and custom D11H media.

**Architecture:** Immutable public label models feed a Flutter text renderer
that produces a one-bit raster. The research D11H driver converts each raster
row into a verified `0x85` packet and uses the existing response-correlated
print lifecycle. The probe app edits and previews the same document it prints.

**Tech Stack:** Flutter, Dart, `dart:ui`, `TextPainter`, existing BLE transport

---

### Task 1: Label Domain Model

**Files:**
- Create: `lib/src/label/label_models.dart`
- Create: `lib/src/label/monochrome_raster.dart`
- Modify: `lib/niimbot.dart`
- Test: `test/label/label_models_test.dart`

- [ ] Write failing tests for presets, orientation, validation, and immutable
  raster pixels.
- [ ] Implement the smallest immutable model API that passes the tests.
- [ ] Export the models from the stable package entry point.

### Task 2: Text Renderer

**Files:**
- Create: `lib/src/label/text_label_renderer.dart`
- Test: `test/label/text_label_renderer_test.dart`

- [ ] Write failing tests for 96x176 and 96x240 output dimensions.
- [ ] Verify rendered text produces black pixels and respects rotation.
- [ ] Implement Flutter text layout, canvas rendering, and monochrome
  thresholding.

### Task 3: Dynamic D11H Raster Encoding

**Files:**
- Create: `lib/src/research/d11h_raster_encoder.dart`
- Modify: `lib/src/research/probe_controller.dart`
- Modify: `lib/niimbot_research.dart`
- Test: `test/research/d11h_raster_encoder_test.dart`
- Test: `test/research/probe_controller_test.dart`

- [ ] Write failing row-packing and checksum tests.
- [ ] Implement `0x85` row frames and response-verified dynamic print flow.
- [ ] Verify print setup dimensions match the rendered raster.

### Task 4: Probe Editor and Preview

**Files:**
- Modify: `tool/d11h_probe/lib/probe_page.dart`
- Modify: `tool/d11h_probe/test/probe_page_test.dart`

- [ ] Write a failing widget test for text, size, orientation, alignment, and
  print controls.
- [ ] Add an adaptive editor and preview card.
- [ ] Render and print the configured `LabelDocument`.

### Task 5: Verification

- [ ] Run root `flutter test` and `flutter analyze`.
- [ ] Run probe `flutter test` and `flutter analyze`.
- [ ] Install the updated probe on the connected iPhone for physical output.
