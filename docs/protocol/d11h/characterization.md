# D11H BLE Characterization

This record separates verified observations from hypotheses. Do not promote a
UUID, command, response, or printer state into production code until it is
reproduced on both Android and iOS.

## Test Inventory

Record one row for every run. Store only the final six characters of a device
identifier.

| Date | Phone | OS | D11H ID suffix | Firmware | Label media | Result |
|---|---|---|---|---|---|---|

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

## Verified Facts

Move a fact here only after it is reproduced at least three times on Android and
three times on iOS with the physical D11H.

No facts have been verified yet.

