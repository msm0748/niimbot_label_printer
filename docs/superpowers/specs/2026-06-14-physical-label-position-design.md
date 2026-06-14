# Physical Label Position Design

## Scope

Add a physical horizontal position option for label text. This position is
independent from text alignment and remains relative to the printed label after
orientation is applied.

## Public Model

Add `LabelHorizontalPosition` with `left`, `center`, and `right` values.
`LabelText.horizontalPosition` defaults to `center` so existing callers retain
their current placement.

`LabelTextAlignment` continues to control alignment of text lines inside the
text element. The new horizontal position controls where the rendered text
block is placed inside that element.

## Rendering

The renderer first lays out text using the existing bounds, wrapping, and line
alignment behavior. It then positions the resulting text block along the
physical label's horizontal axis.

Left, center, and right refer to the visible horizontal axis of the final label
preview and print. Normal labels apply the position on the source x-axis.
Rotated labels apply it on the source y-axis so the clockwise rotation maps it
to the final raster's x-axis.

Vertical centering and clipping remain unchanged. The configured text bounds
and one-millimeter probe-app padding remain the placement limits.

## Probe Application

Add a `Label position` dropdown with `Left`, `Center`, and `Right`. The selected
position updates the preview immediately and is passed to `LabelText` when
printing.

## Verification

Renderer tests compare the occupied pixel bounds for left, center, and right
positions in both normal and rotated orientations. Widget tests verify that the
new dropdown is present and that selecting a position updates the document
used for rendering.
