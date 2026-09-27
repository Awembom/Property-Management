import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rental_app/core/router/app_router.dart';
import 'package:rental_app/core/theme/app_theme.dart';
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

/// The root widget. A ConsumerWidget (instead of StatelessWidget) can read
/// Riverpod providers via `ref`; here it reads the router.
class RentalApp extends ConsumerWidget {
  const RentalApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Rental App',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      routerConfig: ref.watch(appRouterProvider),
    );
  }
}
