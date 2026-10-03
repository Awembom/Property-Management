import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rental_app/core/offline/outbox.dart';
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
  Future<Profile> build() async {
    final repository = ref.read(profileRepositoryProvider);
    // Known from last time: show it at once (the right Home page and tabs,
    // no flash of the landlord's screens for a tenant), then update it.
    final saved = await repository.fetchSavedProfile();
    if (saved != null) {
      Future.microtask(() async {
        try {
          final fresh = await repository.fetchMyProfile();
          if (ref.mounted) state = AsyncData(fresh);
        } catch (_) {
          // Offline: the saved one stays.
        }
      });
      return saved;
    }
    return repository.fetchMyProfile();
  }

  /// Saves my name and phone. Online: straight to the database, then
  /// reloads. Offline: kept on the phone (the profile shows it right away)
  /// and sent automatically when the connection is back.
  /// Returns true if it was sent now, false if it's waiting.
  /// Throws if the server refuses, so the screen can show a message.
  Future<bool> save({required String fullName, required String phone}) async {
    final repository = ref.read(profileRepositoryProvider);
    final current = await future;
    final updated = Profile(
      id: current.id,
      username: current.username,
      accountType: current.accountType,
      fullName: fullName.trim().isEmpty ? null : fullName.trim(),
      phone: phone.trim().isEmpty ? null : phone.trim(),
    );
    final sent = await ref
        .read(outboxProvider.notifier)
        .sendOrQueue(OutboxItem.updateProfile(fullName: updated.fullName, phone: updated.phone));
    if (sent) {
      state = AsyncData(await repository.fetchMyProfile());
    } else {
      await repository.saveLocally(updated);
      state = AsyncData(updated);
    }
    return sent;
  }
}
