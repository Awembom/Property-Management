import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rental_app/core/supabase/supabase_providers.dart';
import 'package:rental_app/features/auth/presentation/pages/login_page.dart';
import 'package:rental_app/features/auth/presentation/pages/profile_page.dart';
import 'package:rental_app/features/auth/presentation/pages/signup_page.dart';
import 'package:rental_app/features/auth/presentation/pages/verify_email_page.dart';
import 'package:rental_app/features/properties/presentation/pages/properties_page.dart';

/// Route paths in one place, so screens never hardcode strings like '/login'.
class AppRoutes {
  AppRoutes._();

  static const String login = '/login';
  static const String signup = '/signup';
  static const String verifyEmail = '/verify-email';
  static const String properties = '/properties';
  static const String profile = '/profile';

  /// Screens anyone can see without being logged in.
  static const Set<String> loggedOutOnly = {login, signup, verifyEmail};

  /// e.g. /verify-email?email=a%40b.com (the email is safely encoded).
  static String verifyEmailFor(String email) =>
      Uri(path: verifyEmail, queryParameters: {'email': email}).toString();
}

/// The app's router, exposed as a Riverpod provider.
/// Screens navigate with `context.go(AppRoutes.properties)` (replace the
/// current screen) or `context.push(...)` (open on top, with a back button).
final appRouterProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(supabaseClientProvider).auth;

  // Re-run `redirect` below every time the user logs in or out.
  final authChanges = _StreamListenable(auth.onAuthStateChange);
  ref.onDispose(authChanges.dispose);

  return GoRouter(
    initialLocation: AppRoutes.properties,
    refreshListenable: authChanges,

    // Runs before every navigation. Returning a path sends the user there;
    // returning null lets them continue where they were going.
    // This is what makes login/logout "just work" without screens navigating.
    redirect: (context, state) {
      final loggedIn = auth.currentSession != null;
      final onLoggedOutScreen =
          AppRoutes.loggedOutOnly.contains(state.matchedLocation);

      if (!loggedIn && !onLoggedOutScreen) return AppRoutes.login;
      if (loggedIn && onLoggedOutScreen) return AppRoutes.properties;
      return null;
    },

    routes: [
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: AppRoutes.signup,
        builder: (context, state) => const SignupPage(),
      ),
      GoRoute(
        path: AppRoutes.verifyEmail,
        builder: (context, state) => VerifyEmailPage(
          email: state.uri.queryParameters['email'] ?? '',
        ),
      ),
      GoRoute(
        path: AppRoutes.properties,
        builder: (context, state) => const PropertiesPage(),
      ),
      GoRoute(
        path: AppRoutes.profile,
        builder: (context, state) => const ProfilePage(),
      ),
    ],
  );
});

/// Adapts a Stream (Supabase auth events) to a Listenable (what GoRouter's
/// refreshListenable expects): every stream event notifies the router.
class _StreamListenable extends ChangeNotifier {
  _StreamListenable(Stream<dynamic> stream) {
    _subscription = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
