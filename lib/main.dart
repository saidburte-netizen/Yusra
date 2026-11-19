import 'package:flutter/material.dart';

void main() {
  runApp(const YusraApp());
}

/// Minimal bootstrap used to prove the CI pipeline is green.
/// The full application is wired in lib/app.dart in milestone A0.
class YusraApp extends StatelessWidget {
  const YusraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Yusra Pharmacy',
      home: Scaffold(
        body: Center(child: Text('Care made easy')),
      ),
    );
  }
}
