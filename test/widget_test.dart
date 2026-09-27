import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rental_app/features/auth/presentation/pages/login_page.dart';

// Smoke test: the login page builds without errors.
// (It doesn't start Supabase, so it runs offline and needs no .env.)
void main() {
  testWidgets('Login page shows the app name and Continue button',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginPage()));

    expect(find.text('Rental App'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });
}
