import 'package:flutter/material.dart';

void main() => runApp(const TelephonyExample());

class TelephonyExample extends StatelessWidget {
  const TelephonyExample({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
    home: Scaffold(body: Center(child: Text('PipeWire Telephony'))),
  );
}
