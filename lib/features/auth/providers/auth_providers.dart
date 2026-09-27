import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rental_app/core/supabase/supabase_providers.dart';
import 'package:rental_app/features/auth/data/profile.dart';
import 'package:rental_app/features/auth/data/profile_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Emits every login, logout and token refresh.
/// The first event (`initialSession`) tells us whether a saved login was
/// restored when the app started.
final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(supabaseClientProvider).auth.onAuthStateChange;
});

/// The logged-in user's profile.
///
/// `autoDispose` = forgotten when no screen is using it, so it is re-fetched
/// the next time the profile screen opens (and never shows a previous
/// user's data after logging out and in as someone else).
final myProfileProvider =
    AsyncNotifierProvider.autoDispose<MyProfileNotifier, Profile>(
      MyProfileNotifier.new,
    );

class MyProfileNotifier extends AsyncNotifier<Profile> {
  @override
  Future<Profile> build() {
    return ref.read(profileRepositoryProvider).fetchMyProfile();
  }

  /// Saves changes, then reloads the profile from the database.
  /// Throws on failure so the screen can show an error message.
  Future<void> save({required String fullName, required String phone}) async {
    final repository = ref.read(profileRepositoryProvider);
    final current = await future;
    await repository.updateMyProfile(
      Profile(
        id: current.id,
        fullName: fullName.trim().isEmpty ? null : fullName.trim(),
        phone: phone.trim().isEmpty ? null : phone.trim(),
      ),
    );
    state = AsyncData(await repository.fetchMyProfile());
  }
}
