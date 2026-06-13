import 'package:flutter/material.dart';
import 'package:niimbot_lib/niimbot_research.dart';

import 'probe_page.dart';

void main() => runApp(const D11hProbeApp());

class D11hProbeApp extends StatelessWidget {
  const D11hProbeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'NIIMBOT D11H Probe',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      home: ProbePage(controller: ProbeController(ReactiveBleTransport())),
    );
  }
}
