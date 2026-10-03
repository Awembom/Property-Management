import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rental_app/core/offline/offline_cache.dart';
import 'package:rental_app/core/supabase/supabase_providers.dart';
import 'package:rental_app/features/auth/data/profile.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Reads and updates the logged-in user's row in `profiles`.
/// RLS only lets users update their own profile, so these queries can't
/// touch anyone else's even if the id were wrong.
class ProfileRepository {
  ProfileRepository(this._client, this._cache);

  final SupabaseClient _client;

  /// Keeps what was loaded, for offline use (see OfflineCache).
  final OfflineCache _cache;

  String get _userId {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Not logged in');
    return user.id;
  }

  Future<Profile> fetchMyProfile() async {
    final row = await _cache.row(
      'my_profile',
      () => _client
          .from('profiles')
          .select('id, full_name, phone, username, account_type')
          .eq('id', _userId)
          .single(),
    );
    return Profile.fromJson(row!);
  }

  /// Keeps an edit made offline on the phone, so the profile shows it (also
  /// after restarting the app) until it's sent.
  Future<void> saveLocally(Profile profile) => _cache.put('my_profile', profile.toJson());

  /// The profile saved on this phone (from the last time it loaded), or
  /// null. Instant: lets the app show the right Home page straight away.
  Future<Profile?> fetchSavedProfile() async {
    final row = await _cache.savedRow('my_profile');
    return row == null ? null : Profile.fromJson(row);
  }

  Future<void> updateMyProfile(Profile profile) async {
    await _client
        .from('profiles')
        .update(profile.toUpdateJson())
        .eq('id', _userId);
  }
}

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(ref.watch(supabaseClientProvider), ref.watch(offlineCacheProvider));
});
