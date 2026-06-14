# Physical Label Position Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let callers place a rendered text block at the physical left, center, or right of a label independently from line alignment and label rotation.

**Architecture:** Extend `LabelText` with a public physical-position enum. The renderer measures the laid-out text block and chooses its paint offset along the source label's long horizontal axis, which remains the D11H label's physical left-to-right axis after raster rotation. The probe app exposes the option and passes it through its existing document builder.

**Tech Stack:** Dart, Flutter painting APIs, Flutter widget tests

---

### Task 1: Public Label Position Model

**Files:**
- Modify: `test/label/label_models_test.dart`
- Modify: `lib/src/label/label_models.dart`

- [ ] **Step 1: Write the failing model test**

Add assertions that `LabelText.horizontalPosition` defaults to
`LabelHorizontalPosition.center` and preserves an explicitly supplied
`LabelHorizontalPosition.right`.

- [ ] **Step 2: Run the model test and verify it fails**

Run: `flutter test test/label/label_models_test.dart`

Expected: compilation fails because `LabelHorizontalPosition` and
`horizontalPosition` do not exist.

- [ ] **Step 3: Add the model API**

Add:

```dart
enum LabelHorizontalPosition { left, center, right }
```

Add a `horizontalPosition` constructor argument and field to `LabelText`, with
`LabelHorizontalPosition.center` as the default.

- [ ] **Step 4: Run the model test and verify it passes**

Run: `flutter test test/label/label_models_test.dart`

Expected: PASS.

### Task 2: Direction-Aware Renderer Placement

**Files:**
- Modify: `test/label/text_label_renderer_test.dart`
- Modify: `lib/src/label/text_label_renderer.dart`

- [ ] **Step 1: Write failing normal-orientation placement tests**

Render the same short text using left, center, and right physical positions.
Compute each raster's black-pixel horizontal bounds and assert:

```dart
expect(leftBounds.left, lessThan(centerBounds.left));
expect(centerBounds.left, lessThan(rightBounds.left));
```

- [ ] **Step 2: Run the renderer tests and verify they fail**

Run: `flutter test test/label/text_label_renderer_test.dart`

Expected: compilation fails until Task 1 is implemented, then the occupied
bounds remain equal because placement is not implemented.

- [ ] **Step 3: Implement normal physical placement**

Lay text out with `TextWidthBasis.longestLine`, determine the measured block
width, and calculate the x offset inside the configured bounds:

```dart
final x = switch (text.horizontalPosition) {
  LabelHorizontalPosition.left => left,
  LabelHorizontalPosition.center => left + (width - painter.width) / 2,
  LabelHorizontalPosition.right => left + width - painter.width,
};
```

Keep `LabelTextAlignment` mapped to `TextAlign` so multiline line alignment
remains independent.

- [ ] **Step 4: Run the renderer tests and verify normal placement passes**

Run: `flutter test test/label/text_label_renderer_test.dart`

Expected: PASS for normal placement.

- [ ] **Step 5: Write failing rotated-orientation placement tests**

Render the same short text in `LabelOrientation.rotated90` with left, center,
and right positions. Assert increasing occupied vertical bounds in the final
rotated raster because the D11H maps that raster axis to the printed label's
physical left-to-right direction.

- [ ] **Step 6: Run the rotated tests and verify they fail**

Run: `flutter test test/label/text_label_renderer_test.dart`

Expected: FAIL if all rotated outputs occupy the same position on the D11H
label axis.

- [ ] **Step 7: Keep placement on the source label horizontal axis**

Use the same source-canvas x offset for normal and rotated output:

```dart
final x = switch (text.horizontalPosition) {
  LabelHorizontalPosition.left => left,
  LabelHorizontalPosition.center => left + (width - painter.width) / 2,
  LabelHorizontalPosition.right => left + width - painter.width,
};
```

Keep the source-canvas y offset centered and continue using the existing
clockwise raster rotation and clipping bounds.

- [ ] **Step 8: Run renderer tests and verify all pass**

Run: `flutter test test/label/text_label_renderer_test.dart`

Expected: PASS.

### Task 3: Probe App Position Selector

**Files:**
- Modify: `tool/d11h_probe/test/probe_page_test.dart`
- Modify: `tool/d11h_probe/lib/probe_page.dart`

- [ ] **Step 1: Extend the widget test with a failing selector assertion**

Find the dropdown keyed `label-position-select`, select
`LabelHorizontalPosition.right`, print the label, and assert:

```dart
final text = renderedDocument!.elements.single as LabelText;
expect(text.horizontalPosition, LabelHorizontalPosition.right);
```

- [ ] **Step 2: Run the widget test and verify it fails**

Run: `cd tool/d11h_probe && flutter test test/probe_page_test.dart`

Expected: FAIL because the keyed dropdown is absent.

- [ ] **Step 3: Add the selector and document wiring**

Add `_labelHorizontalPosition`, defaulting to center. Add a dropdown labeled
`Label position` with `Left`, `Center`, and `Right`, key it
`label-position-select`, refresh the preview on change, and pass the value to
`LabelText.horizontalPosition`.

- [ ] **Step 4: Run the widget test and verify it passes**

Run: `cd tool/d11h_probe && flutter test test/probe_page_test.dart`

Expected: PASS.

### Task 4: Verification

**Files:**
- Modify: `docs/superpowers/plans/2026-06-14-physical-label-position.md`

- [ ] **Step 1: Format changed Dart files**

Run:

```bash
dart format lib/src/label/label_models.dart \
  lib/src/label/text_label_renderer.dart \
  test/label/label_models_test.dart \
  test/label/text_label_renderer_test.dart \
  tool/d11h_probe/lib/probe_page.dart \
  tool/d11h_probe/test/probe_page_test.dart
```

- [ ] **Step 2: Run root analysis and tests**

Run: `flutter analyze && flutter test`

Expected: no analysis issues and all root tests pass.

- [ ] **Step 3: Run probe-app analysis and tests**

Run: `cd tool/d11h_probe && flutter analyze && flutter test`

Expected: no analysis issues and all probe tests pass.

- [ ] **Step 4: Inspect the final diff**

Run: `git diff --check && git status --short`

Expected: no whitespace errors; only the planned source, test, spec, and plan
files are changed, while `.superpowers/` remains untracked and excluded.
