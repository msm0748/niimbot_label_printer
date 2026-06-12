import 'package:flutter/material.dart';
import 'package:niimbot_lib/niimbot.dart';

void main() {
  runApp(const D11hProbeApp());
}

class D11hProbeApp extends StatelessWidget {
  const D11hProbeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NIIMBOT D11H Probe',
      home: Scaffold(
        appBar: AppBar(title: const Text('NIIMBOT D11H Probe')),
        body: Center(child: Text('BLE readiness: ${BleReadiness.ready.name}')),
      ),
    );
  }
}
