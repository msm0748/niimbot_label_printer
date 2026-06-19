# D11H BLE Characterization

This record separates verified observations from hypotheses. Do not promote a
UUID, command, response, or printer state into production code until it is
reproduced on both Android and iOS.

## Test Inventory

Record one row for every run. Store only the final six characters of a device
identifier.

| Date | Phone | OS | D11H ID suffix | Firmware | Label media | Result |
|---|---|---|---|---|---|---|
| 2026-06-13 | iPhone (model redacted) | iOS (version not captured) | redacted | unknown | small label | official-app print trace captured |

## Advertising

Record:

- observed device-name patterns;
- advertised service UUIDs;
- manufacturer-data length, not its full contents;
- whether the identifier remains stable after printer and phone restarts.

Do not record full persistent device identifiers or unrelated nearby devices.

## GATT Layout

| Platform | Service UUID | Characteristic UUID | Read | Write | Write without response | Notify | Indicate | Verified runs |
|---|---|---|---:|---:|---:|---:|---:|---:|

A row is verified only after three matching runs on Android and three matching
runs on iOS.

## MTU

| Platform | Requested | Negotiated | Stable payload size | Verified runs |
|---|---:|---:|---:|---:|

## Official-App Trace

For each operation, record ordered writes and notifications with relative
timestamps:

1. Connect and idle initialization.
2. Printer or status query.
3. One minimal all-white label.
4. One minimal label containing a single black horizontal line.
5. Disconnect.

Use sanitized trace files from `captures/`. Keep raw captures outside Git.

## Hypotheses

A hypothesis is not a verified command. For each hypothesis, record:

- observed bytes and direction;
- the suspected field or command meaning;
- an experiment that can confirm or reject it;
- the result of that experiment.

### iOS official-app print, run 01

Sanitized trace:
`captures/2026-06-13-ios-official-app-print-run01.sanitized.txt`

Observed transport facts for this run:

- ATT writes use Write Command (without response) on attribute handle `0x000A`.
- responses arrive as Handle Value Notifications on attribute handle `0x000A`;
- the protocol frame is `55 55`, command, payload length, payload, XOR
  checksum, `AA AA`;
- the checksum covers command, payload length, and payload;
- multiple complete protocol frames can be concatenated into one ATT write.

The capture started after service discovery, so it does not establish the
service UUID, characteristic UUID, or characteristic properties beyond the
observed write-without-response and notification behavior.

| Observed bytes | Suspected meaning | Confirmation experiment | Result |
|---|---|---|---|
| SEND `1A`, RECV `1B` with identifiers and trailing numeric fields | device/printer information query | repeat without printing and compare stable versus media-dependent fields | open |
| SEND `01`, RECV `02` | print-job initialization | vary copies and label dimensions one field at a time | open |
| SEND `13`, RECV `14` | session or print-job configuration | compare fresh app sessions and offline operation | open |
| SEND `83`, followed by `85` bitmap-like payloads | page/bitmap metadata and raster rows | print white, black-line, and single-dot fixtures | open |
| SEND `84` around `83`/`85` data, RECV `D3` | raster range boundary or data commit | vary image height and inspect indexes and response timing | open |
| repeated SEND `A3`, RECV `B3` with changing payload | print status/progress query | poll while idle, printing, out of paper, and cover open | open |
| SEND `E3`, RECV `E4` after raster transfer | end/commit print data | omit only in a controlled probe run and observe behavior | open |
| SEND `F3`, RECV `F4` after terminal status | finalize completed print job | compare successful, cancelled, and failed jobs | open |
| SEND `19 02 01 01`, RECV generic `00 01 01` | leave print mode or session cleanup | compare app disconnect and consecutive-print traces | open |

### Media detection probe

The research app includes a D11H media probe that sends `1A` and optionally
one idle `A3` query on the print characteristic. This is not verified as RFID
or media-SKU detection.

Initial iOS procedure:

1. Run the probe three times with the current label roll loaded.
2. Open or remove the label path if physically safe, then run it three times.
3. Reinsert the same label roll and run it three times.
4. Compare sanitized `1B` and `B3` payloads across states.

Do not promote any byte to a named media field until repeated runs confirm it.
Do not claim media SKU detection until at least two different media rolls are
tested.

Observed iOS D11H media-counter behavior:

- The final two information payload bytes are little-endian.
- They increase by one per printed label.
- A 12x22 roll with a 260-label user-provided total was observed at baseline
  `00 01` (256).
- A 12x30 roll with a 195-label user-provided total was observed with a
  first-seen baseline of `03 01` (259).

Remaining estimates require application-provided total labels and baseline
counter values. The payload has not shown a direct total-label field.

## Verified Facts

Move a fact here only after it is reproduced at least three times on Android and
three times on iOS with the physical D11H.

No facts have been verified yet.
