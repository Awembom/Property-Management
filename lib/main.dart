import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rental_app/core/offline/sync_controller.dart';
import 'package:rental_app/core/router/app_router.dart';
import 'package:rental_app/core/theme/app_theme.dart';
import 'package:rental_app/features/auth/data/auth_repository.dart';
import 'package:rental_app/features/auth/providers/auth_providers.dart';
import 'package:rental_app/shared/widgets/offline_banner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  // Required before doing any async work (loading files, plugins) in main().
  WidgetsFlutterBinding.ensureInitialized();

  // Read SUPABASE_URL and SUPABASE_ANON_KEY from the `.env` file.
  // The file is listed under `assets` in pubspec.yaml so it ships with the app.
  await dotenv.load(fileName: '.env');

  // Connect to Supabase once, at startup. Anywhere in the app can then use
  // `Supabase.instance.client` to query the database or check auth.
  // Either the new "publishable" key (sb_publishable_...) or the legacy
  // "anon" key works here. Both are safe in the app because RLS protects data.
  await Supabase.initialize(
    url: _requireEnv('SUPABASE_URL'),
    publishableKey: _requireEnv('SUPABASE_ANON_KEY'),
  );

  // ProviderScope stores the state of every Riverpod provider in the app.
  runApp(const ProviderScope(child: RentalApp()));
}

/// Reads a value from `.env`, failing fast with a clear message if it is
/// missing, instead of a confusing network error later.
String _requireEnv(String key) {
  final value = dotenv.env[key];
  if (value == null || value.isEmpty) {
    throw StateError('Missing $key in .env (see .env.example).');
  }
  return value;
}

/// The root widget. A Consumer widget can read Riverpod providers via `ref`;
/// it's stateful so it can notice the app coming back to the front.
class RentalApp extends ConsumerStatefulWidget {
  const RentalApp({super.key});

  @override
  ConsumerState<RentalApp> createState() => _RentalAppState();
}

class _RentalAppState extends ConsumerState<RentalApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Back in front: send what waited offline and refresh the saved data.
    _lifecycle = AppLifecycleListener(onResume: () => ref.read(syncControllerProvider).syncNow());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // When the app starts with a saved login, make sure that account still
    // exists (e.g. it was deleted in Supabase); if not, show the login screen.
    ref.listen(authStateProvider, (previous, next) {
      if (next.value?.event == AuthChangeEvent.initialSession) {
        ref.read(authRepositoryProvider).dropLoginIfAccountGone();
      }
    });
    // Starts the offline sync (after login, when the connection returns).
    ref.watch(syncControllerProvider);

    return MaterialApp.router(
      title: 'Rental App',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      routerConfig: ref.watch(appRouterProvider),
      // A slim "Offline" strip above every screen when there's no connection.
      builder: (context, child) => OfflineBanner(child: child ?? const SizedBox()),
    );
  }
}
