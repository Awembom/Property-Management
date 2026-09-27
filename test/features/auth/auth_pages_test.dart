import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rental_app/core/router/app_router.dart';
import 'package:rental_app/features/auth/data/auth_repository.dart';
import 'package:rental_app/features/auth/presentation/pages/login_page.dart';
import 'package:rental_app/features/auth/presentation/pages/signup_page.dart';
import 'package:rental_app/features/auth/presentation/pages/verify_email_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Stands in for the real AuthRepository so tests never touch Supabase.
/// `Fake` makes any method we didn't write throw, which flags surprises.
class FakeAuthRepository extends Fake implements AuthRepository {
  final calls = <String>[];
  Object? signInError;
  Object? signUpError;

  @override
  Future<void> signIn({required String email, required String password}) async {
    calls.add('signIn $email');
    if (signInError != null) throw signInError!;
  }

  @override
  Future<bool> signUp({
    required String email,
    required String password,
    required String fullName,
  }) async {
    calls.add('signUp $email $fullName');
    if (signUpError != null) throw signUpError!;
    return true;
  }

  @override
  Future<void> resendSignupCode(String email) async => calls.add('resend $email');

  @override
  Future<void> verifySignupCode({required String email, required String code}) async =>
      calls.add('verify $email $code');
}

/// Shows [start] inside a small router (so context.go works) with the fake repo.
Future<void> pumpAuthScreen(WidgetTester tester, FakeAuthRepository fake, String start) async {
  final router = GoRouter(
    initialLocation: start,
    routes: [
      GoRoute(path: AppRoutes.login, builder: (_, _) => const LoginPage()),
      GoRoute(path: AppRoutes.signup, builder: (_, _) => const SignupPage()),
      GoRoute(
        path: AppRoutes.verifyEmail,
        builder: (_, state) =>
            VerifyEmailPage(email: state.uri.queryParameters['email'] ?? ''),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(fake)],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('Login', () {
    testWidgets('empty form shows errors and does not call the server', (tester) async {
      final fake = FakeAuthRepository();
      await pumpAuthScreen(tester, fake, AppRoutes.login);

      await tester.tap(find.text('Log in'));
      await tester.pump();

      expect(find.text('Enter your email'), findsOneWidget);
      expect(find.text('Enter your password'), findsOneWidget);
      expect(fake.calls, isEmpty);
    });

    testWidgets('valid form logs in with the trimmed email', (tester) async {
      final fake = FakeAuthRepository();
      await pumpAuthScreen(tester, fake, AppRoutes.login);

      await tester.enterText(find.widgetWithText(TextFormField, 'Email'), '  jane@example.com ');
      await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'secret123');
      await tester.tap(find.text('Log in'));
      await tester.pumpAndSettle();

      expect(fake.calls, ['signIn jane@example.com']);
    });

    testWidgets('wrong password shows a friendly message', (tester) async {
      final fake = FakeAuthRepository()
        ..signInError = const AuthException('Invalid login credentials', code: 'invalid_credentials');
      await pumpAuthScreen(tester, fake, AppRoutes.login);

      await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'jane@example.com');
      await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'wrong');
      await tester.tap(find.text('Log in'));
      await tester.pumpAndSettle();

      expect(find.text('Wrong email or password.'), findsOneWidget);
    });

    testWidgets('unconfirmed email sends a new code and opens the code screen', (tester) async {
      final fake = FakeAuthRepository()
        ..signInError = const AuthException('Email not confirmed', code: 'email_not_confirmed');
      await pumpAuthScreen(tester, fake, AppRoutes.login);

      await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'jane@example.com');
      await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'secret123');
      await tester.tap(find.text('Log in'));
      await tester.pumpAndSettle();

      expect(fake.calls, ['signIn jane@example.com', 'resend jane@example.com']);
      expect(find.text('Confirm your email'), findsOneWidget);
      expect(find.text('jane@example.com'), findsOneWidget);
    });
  });

  group('Signup', () {
    testWidgets('success opens the code screen for that email', (tester) async {
      final fake = FakeAuthRepository();
      await pumpAuthScreen(tester, fake, AppRoutes.signup);

      await tester.enterText(find.widgetWithText(TextFormField, 'Full name'), 'Jane Doe');
      await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'jane@example.com');
      await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'secret123');
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pumpAndSettle();

      expect(fake.calls, ['signUp jane@example.com Jane Doe']);
      expect(find.text('Confirm your email'), findsOneWidget);
    });

    testWidgets('short password is rejected before calling the server', (tester) async {
      final fake = FakeAuthRepository();
      await pumpAuthScreen(tester, fake, AppRoutes.signup);

      await tester.enterText(find.widgetWithText(TextFormField, 'Full name'), 'Jane Doe');
      await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'jane@example.com');
      await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'short');
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pump();

      expect(find.text('Use at least 8 characters'), findsOneWidget);
      expect(fake.calls, isEmpty);
    });

    testWidgets('existing account shows a clear message', (tester) async {
      final fake = FakeAuthRepository()
        ..signUpError = const AuthException(
          'An account with this email already exists. Please log in.',
          code: 'user_already_exists',
        );
      await pumpAuthScreen(tester, fake, AppRoutes.signup);

      await tester.enterText(find.widgetWithText(TextFormField, 'Full name'), 'Jane Doe');
      await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'jane@example.com');
      await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'secret123');
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pumpAndSettle();

      expect(find.text('An account with this email already exists. Please log in.'), findsOneWidget);
    });
  });

  group('Verify email', () {
    testWidgets('code field accepts digits only, max 6, then verifies', (tester) async {
      final fake = FakeAuthRepository();
      await pumpAuthScreen(tester, fake, AppRoutes.verifyEmailFor('jane@example.com'));

      await tester.enterText(find.byType(TextFormField), '12ab34');
      await tester.tap(find.text('Confirm'));
      await tester.pump();
      expect(find.text('Enter the 6-digit code from the email'), findsOneWidget);
      expect(fake.calls, isEmpty);

      await tester.enterText(find.byType(TextFormField), '12345678');
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(fake.calls, ['verify jane@example.com 123456']);
    });

    testWidgets('resend asks for a new code', (tester) async {
      final fake = FakeAuthRepository();
      await pumpAuthScreen(tester, fake, AppRoutes.verifyEmailFor('jane@example.com'));

      await tester.tap(find.textContaining('Send a new code'));
      await tester.pumpAndSettle();

      expect(fake.calls, ['resend jane@example.com']);
      expect(find.text('New code sent. Check your email.'), findsOneWidget);
    });
  });
}
