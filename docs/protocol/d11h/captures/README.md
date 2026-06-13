# D11H Capture Handling

Use filenames in this form:

`YYYY-MM-DD-platform-operation-runNN.sanitized.txt`

Committed files may contain:

- relative timestamps;
- service and characteristic UUIDs;
- packet bytes;
- RSSI and negotiated MTU;
- phone model and OS version;
- D11H firmware version when observable.

Remove:

- full Android MAC addresses;
- iOS peripheral identifiers;
- personal label content or account data;
- unrelated nearby BLE devices;
- raw logs that have not been reviewed.

Raw packet captures remain outside Git. Commit only the minimum sanitized trace
needed to reproduce codec and parser tests.

