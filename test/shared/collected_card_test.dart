import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rental_app/shared/widgets/collected_card.dart';

void main() {
  testWidgets('the month\'s total starts hidden; the eye shows and hides it', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: CollectedCard(amountText: 'XAF 450,000')),
    ));
    expect(find.text('Total collected this month'), findsOneWidget);
    expect(find.text('XAF 450,000'), findsNothing);
    expect(find.text('••••••'), findsOneWidget);

    await tester.tap(find.byTooltip('Show amount'));
    await tester.pumpAndSettle();
    expect(find.text('XAF 450,000'), findsOneWidget);

    await tester.tap(find.byTooltip('Hide amount'));
    await tester.pumpAndSettle();
    expect(find.text('XAF 450,000'), findsNothing);
  });
}
