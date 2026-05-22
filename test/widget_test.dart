import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aegis/main.dart';

void main() {
  testWidgets('AEGIS app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: AegisApp()),
    );
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
