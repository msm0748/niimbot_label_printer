import 'package:d11h_probe/probe_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  test('non-Android platforms rely on CoreBluetooth readiness', () async {
    var called = false;

    final granted = await requestProbePermissions(
      isAndroid: false,
      requestPermissions: (permissions) async {
        called = true;
        return <Permission, PermissionStatus>{};
      },
    );

    expect(granted, isTrue);
    expect(called, isFalse);
  });

  test('Android requires scan and connect permissions', () async {
    List<Permission>? requested;

    final granted = await requestProbePermissions(
      isAndroid: true,
      requestPermissions: (permissions) async {
        requested = permissions;
        return <Permission, PermissionStatus>{
          Permission.bluetoothScan: PermissionStatus.granted,
          Permission.bluetoothConnect: PermissionStatus.denied,
        };
      },
    );

    expect(requested, <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ]);
    expect(granted, isFalse);
  });
}
