import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rental_app/core/router/app_router.dart';
import 'package:rental_app/features/onboarding/onboarding.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SharedPreferences> pumpOnboarding(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final router = GoRouter(initialLocation: AppRoutes.onboarding, routes: [
    GoRoute(path: AppRoutes.onboarding, builder: (_, _) => const OnboardingPage()),
    GoRoute(path: AppRoutes.welcome, builder: (_, _) => const Scaffold(body: Text('WELCOME'))),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return prefs;
}

void main() {
  testWidgets('Skip goes to the welcome screen, and it is not shown again', (tester) async {
    final prefs = await pumpOnboarding(tester);
    expect(find.text('Welcome to Homedly'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(find.text('WELCOME'), findsOneWidget);
    expect(prefs.getBool('onboarding_seen'), isTrue);
  });

  testWidgets('Next through the four slides, then "Get started"', (tester) async {
    final prefs = await pumpOnboarding(tester);
    for (final title in ['For landlords', 'For tenants', 'Safe and always with you']) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget);
    }
    expect(find.text('Next'), findsNothing);
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    expect(find.text('WELCOME'), findsOneWidget);
    expect(prefs.getBool('onboarding_seen'), isTrue);
  });

  test('without saved settings (tests), it counts as seen', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(onboardingSeenProvider), isTrue);
  });
}
