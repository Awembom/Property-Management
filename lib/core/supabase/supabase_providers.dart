import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The Supabase client, started once in main.dart.
///
/// Features read it through this provider (`ref.read(supabaseClientProvider)`)
/// instead of `Supabase.instance.client` directly, so that tests can replace
/// it with a fake via `ProviderScope(overrides: [...])`.
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});
