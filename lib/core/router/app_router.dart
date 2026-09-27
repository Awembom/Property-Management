import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rental_app/features/auth/presentation/pages/login_page.dart';
import 'package:rental_app/features/properties/presentation/pages/properties_page.dart';

/// Route paths in one place, so screens never hardcode strings like '/login'.
class AppRoutes {
  AppRoutes._();

  static const String login = '/login';
  static const String properties = '/properties';
}

/// The app's router, exposed as a Riverpod provider.
///
/// Why a provider? In Phase 2 the router will need to watch the auth state
/// (logged in / logged out) to redirect users, and providers can watch other
/// providers. Screens navigate with `context.go(AppRoutes.properties)`.
final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.login,
    routes: [
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: AppRoutes.properties,
        builder: (context, state) => const PropertiesPage(),
      ),
    ],
  );
});
