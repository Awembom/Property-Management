import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rental_app/core/router/app_router.dart';
import 'package:rental_app/features/auth/data/account_type.dart';
import 'package:rental_app/features/auth/data/auth_repository.dart';
import 'package:rental_app/features/auth/data/username.dart';
import 'package:rental_app/features/auth/presentation/pages/account_type_page.dart';
import 'package:rental_app/features/auth/presentation/pages/change_password_page.dart';
import 'package:rental_app/features/auth/presentation/pages/login_page.dart';
import 'package:rental_app/features/auth/presentation/pages/signup_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Stands in for the real AuthRepository so tests never touch Supabase.
/// `Fake` makes any method we didn't write throw, which flags surprises.
class FakeAuthRepository extends Fake implements AuthRepository {
  final calls = <String>[];
  Object? signInError;
  Object? signUpError;

  @override
  Future<void> signIn({
    required String username,
    required String password,
  }) async {
    calls.add('signIn $username');
    if (signInError != null) throw signInError!;
  }

  @override
  Future<void> signUp({
    required String username,
    required String password,
    required String fullName,
    required AccountType accountType,
  }) async {
    calls.add('signUp $username $fullName ${accountType.value}');
    if (signUpError != null) throw signUpError!;
  }

  @override
  Future<void> changePassword(String newPassword) async =>
      calls.add('change $newPassword');

  @override
  Future<void> signOut() async => calls.add('signOut');
}

/// Shows [start] inside a small router (so context.go works) with the fake repo.
Future<void> pumpAuthScreen(
  WidgetTester tester,
  FakeAuthRepository fake,
  String start,
) async {
  final router = GoRouter(
    initialLocation: start,
    routes: [
      GoRoute(path: AppRoutes.login, builder: (_, _) => const LoginPage()),
      GoRoute(
        path: AppRoutes.signup,
        builder: (_, _) => const AccountTypePage(),
        routes: [
          GoRoute(
            path: 'details',
            builder: (_, state) => SignupPage(
              accountType: AccountType.fromJson(
                state.uri.queryParameters['type'],
              )!,
            ),
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.changePassword,
        builder: (_, _) => const ChangePasswordPage(forced: true),
      ),
    ],
  );
  // A tall phone screen (400 x 1400), so the whole sign-up form fits.
  tester.view.physicalSize = const Size(1200, 4200);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(fake)],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('usernames map to a hidden address, ignoring case and spaces', () {
    expect(usernameToEmail('  Tina.K '), 'tina.k@$kUsernameEmailDomain');
  });

  group('Login', () {
    testWidgets('empty form shows errors and does not call the server', (
      tester,
    ) async {
      final fake = FakeAuthRepository();
      await pumpAuthScreen(tester, fake, AppRoutes.login);

      await tester.tap(find.text('Log in'));
      await tester.pump();

      expect(find.text('Enter your username'), findsOneWidget);
      expect(find.text('Enter your password'), findsOneWidget);
      expect(fake.calls, isEmpty);
    });

    testWidgets('valid form logs in with the username', (tester) async {
      final fake = FakeAuthRepository();
      await pumpAuthScreen(tester, fake, AppRoutes.login);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Username'),
        'Tina',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'secret123',
      );
      await tester.tap(find.text('Log in'));
      await tester.pumpAndSettle();

      expect(fake.calls, ['signIn Tina']);
    });

    testWidgets('wrong password shows a friendly message', (tester) async {
      final fake = FakeAuthRepository()
        ..signInError = const AuthException(
          'Invalid login credentials',
          code: 'invalid_credentials',
        );
      await pumpAuthScreen(tester, fake, AppRoutes.login);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Username'),
        'tina',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'wrong',
      );
      await tester.tap(find.text('Log in'));
      await tester.pumpAndSettle();

      expect(find.text('Wrong username or password.'), findsOneWidget);
    });
  });

  group('Signup', () {
    // Step 2 for a tenant, opened from step 1 (so "Change" can go back).
    Future<void> fillSignup(
      WidgetTester tester, {
      String username = 'tina',
      String password = 'secret123',
    }) async {
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Full name'),
        'Tina Tenant',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Username'),
        username,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        password,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pumpAndSettle();
    }

    Future<void> chooseTenant(WidgetTester tester) async {
      await tester.tap(find.text('Tenant'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'step 1: choose the account type first; Continue waits for a choice',
      (tester) async {
        final fake = FakeAuthRepository();
        await pumpAuthScreen(tester, fake, AppRoutes.signup);
        expect(find.text('How will you use the app?'), findsOneWidget);
        expect(find.text('Landlord'), findsOneWidget);
        expect(find.text('Team member'), findsOneWidget);
        // No username or password on this screen.
        expect(find.widgetWithText(TextFormField, 'Username'), findsNothing);

        final continueButton = find.widgetWithText(FilledButton, 'Continue');
        expect(tester.widget<FilledButton>(continueButton).onPressed, isNull);
        await chooseTenant(tester);
        expect(find.text('Your details'), findsOneWidget);
      },
    );

    testWidgets(
      'step 2: signs up with username, name, password and the chosen type',
      (tester) async {
        final fake = FakeAuthRepository();
        await pumpAuthScreen(tester, fake, AppRoutes.signup);
        await chooseTenant(tester);
        await fillSignup(tester);
        expect(fake.calls, ['signUp tina Tina Tenant tenant']);
      },
    );

    testWidgets('"Change" goes back to choosing the type', (tester) async {
      final fake = FakeAuthRepository();
      await pumpAuthScreen(tester, fake, AppRoutes.signup);
      await chooseTenant(tester);
      await tester.tap(find.text('Change'));
      await tester.pumpAndSettle();
      expect(find.text('How will you use the app?'), findsOneWidget);
    });

    testWidgets(
      'bad username or short password is rejected before calling the server',
      (tester) async {
        final fake = FakeAuthRepository();
        await pumpAuthScreen(
          tester,
          fake,
          AppRoutes.signupDetailsFor(AccountType.tenant),
        );
        await fillSignup(tester, username: 'ti na!', password: 'short');

        expect(
          find.textContaining('Use only letters, numbers'),
          findsOneWidget,
        );
        expect(find.text('Use at least 8 characters'), findsOneWidget);
        expect(fake.calls, isEmpty);
      },
    );

    testWidgets('taken username shows a clear message', (tester) async {
      final fake = FakeAuthRepository()
        ..signUpError = const AuthException(
          'User already registered',
          code: 'user_already_exists',
        );
      await pumpAuthScreen(
        tester,
        fake,
        AppRoutes.signupDetailsFor(AccountType.tenant),
      );
      await fillSignup(tester);

      expect(
        find.text('That username is taken. Choose another one.'),
        findsOneWidget,
      );
    });
  });

  group('Change password (after a reset)', () {
    testWidgets('both passwords must match; then it is changed', (
      tester,
    ) async {
      final fake = FakeAuthRepository();
      await pumpAuthScreen(tester, fake, AppRoutes.changePassword);
      expect(
        find.text('You logged in with a temporary password'),
        findsOneWidget,
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, 'New password'),
        'newsecret1',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Repeat new password'),
        'different',
      );
      await tester.tap(find.text('Save new password'));
      await tester.pump();
      expect(find.text('The passwords don\'t match'), findsOneWidget);
      expect(fake.calls, isEmpty);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Repeat new password'),
        'newsecret1',
      );
      await tester.tap(find.text('Save new password'));
      await tester.pumpAndSettle();
      expect(fake.calls, ['change newsecret1']);
    });

    testWidgets('forced screen offers Log out instead of Back', (tester) async {
      final fake = FakeAuthRepository();
      await pumpAuthScreen(tester, fake, AppRoutes.changePassword);
      expect(find.byType(BackButton), findsNothing);
      await tester.tap(find.text('Log out'));
      await tester.pumpAndSettle();
      expect(fake.calls, ['signOut']);
    });
  });
}
