# D11H Text Label Printing Design

## Scope

Add a library-first text label pipeline for the NIIMBOT D11H. Applications can
choose a physical label size, orientation, text alignment, font size, wrapping,
and padding. The first version supports text only; images, barcodes, and QR
codes remain separate follow-up work.

## Public Model

`LabelDocument` owns physical width and height in millimeters, orientation, and
an immutable list of `LabelText` elements. `LabelText` describes content,
position and bounds in millimeters, point size, alignment, wrapping, and bold
weight. Presets cover 12x22 mm and 12x30 mm, while arbitrary positive sizes are
accepted.

## Rendering

`TextLabelRenderer` uses Flutter text layout and renders at the D11H's 203 DPI,
rounded to 8 dots per millimeter. It produces an immutable one-bit
`MonochromeRaster`. Normal orientation uses the document dimensions directly;
rotated orientation swaps the output dimensions and rotates the canvas.

## D11H Encoding

Each raster row is sent as command `0x85`. Its payload is:

`row index (big endian, 2 bytes) | 00 00 00 | 01 | packed row bits`

Black pixels are encoded as one bits, most significant bit first. Print setup,
page completion, status polling, and finalization retain the response-verified
flow already proven by the captured test label.

## Probe Application

The probe app provides text input, 12x22/12x30/custom size selection,
orientation, alignment, font size, wrapping, a monochrome preview, and a print
button. The UI remains a research client while the label model and renderer are
exported from the stable library entry point.

## Verification

Unit tests cover size conversion, model validation, text rendering dimensions,
non-empty black output, row packing, frame checksums, and print sequencing.
Widget tests cover user configuration and invoking text print.
