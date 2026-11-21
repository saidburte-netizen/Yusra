import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('minimal app renders the brand tagline', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
          home: Scaffold(body: Center(child: Text('Care made easy')))),
    );

    expect(find.text('Care made easy'), findsOneWidget);
  });
}
