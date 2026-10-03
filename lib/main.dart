import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rental_app/core/notifications/push_service.dart';
import 'package:rental_app/core/offline/sync_controller.dart';
import 'package:rental_app/core/realtime/live_updates.dart';
import 'package:rental_app/core/router/app_router.dart';
import 'package:rental_app/core/supabase/supabase_providers.dart';
import 'package:rental_app/features/onboarding/onboarding.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rental_app/core/theme/app_theme.dart';
import 'package:rental_app/features/auth/data/auth_repository.dart';
import 'package:rental_app/features/auth/providers/auth_providers.dart';
import 'package:rental_app/shared/widgets/offline_banner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  // Required before doing any async work (loading files, plugins) in main().
  final binding = WidgetsFlutterBinding.ensureInitialized();
  // Keep the Homedly splash screen up until the app knows who's using it
  // (see _RentalAppState._hideSplashWhenReady).
  FlutterNativeSplash.preserve(widgetsBinding: binding);

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

  // Firebase, only for push notifications. Its settings come from
  // android/app/google-services.json. The app still works without it.
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('Firebase not available, no push notifications: $e');
  }

  // Small settings kept on the phone (e.g. "onboarding seen").
  final prefs = await SharedPreferences.getInstance();

  // ProviderScope stores the state of every Riverpod provider in the app.
  runApp(ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    child: const RentalApp(),
  ));
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
    ref.read(pushServiceProvider).start();
    _hideSplashWhenReady();
    // Back in front: send what waited offline and refresh the saved data.
    _lifecycle = AppLifecycleListener(
      onResume: () {
        ref.read(syncControllerProvider).syncNow();
        // Live updates again, and one refresh for what changed while away.
        ref.read(liveUpdatesProvider).resume();
      },
      // In the background: stop listening (saves battery and data).
      onHide: () => ref.read(liveUpdatesProvider).stop(),
    );
  }

  bool _splashHidden = false;

  void _hideSplash() {
    if (_splashHidden) return;
    _splashHidden = true;
    FlutterNativeSplash.remove();
  }

  /// Logged out: hide the splash at once (onboarding or welcome comes next).
  /// Logged in: once the profile is known, so the right Home page (tenant or
  /// landlord) is the first thing seen. Never longer than 4 seconds.
  void _hideSplashWhenReady() {
    if (ref.read(supabaseClientProvider).auth.currentSession == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _hideSplash());
      return;
    }
    ref.listenManual(myProfileProvider, (previous, next) {
      if (!next.isLoading || next.hasValue) _hideSplash();
    }, fireImmediately: true);
    Future.delayed(const Duration(seconds: 4), _hideSplash);
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
      final event = next.value?.event;
      if (event == AuthChangeEvent.initialSession) {
        ref.read(authRepositoryProvider).dropLoginIfAccountGone();
      }
      // Logged in (now or from a saved login): this phone gets push notifications.
      if (next.value?.session != null &&
          (event == AuthChangeEvent.initialSession || event == AuthChangeEvent.signedIn)) {
        ref.read(pushServiceProvider).registerThisPhone();
        ref.read(liveUpdatesProvider).start();
      }
      if (event == AuthChangeEvent.signedOut) {
        ref.read(liveUpdatesProvider).stop();
      }
    });
    // Starts the offline sync (after login, when the connection returns).
    ref.watch(syncControllerProvider);

    return MaterialApp.router(
      title: 'Homedly',
      scaffoldMessengerKey: scaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      routerConfig: ref.watch(appRouterProvider),
      // A slim "Offline" strip above every screen when there's no connection.
      builder: (context, child) => OfflineBanner(child: child ?? const SizedBox()),
    );
  }
}
