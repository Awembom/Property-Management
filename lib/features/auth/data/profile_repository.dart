import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rental_app/core/supabase/supabase_providers.dart';
import 'package:rental_app/features/auth/data/profile.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Reads and updates the logged-in user's row in `profiles`.
/// RLS only lets users update their own profile, so these queries can't
/// touch anyone else's even if the id were wrong.
class ProfileRepository {
  ProfileRepository(this._client);

  final SupabaseClient _client;

  String get _userId {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Not logged in');
    return user.id;
  }

  Future<Profile> fetchMyProfile() async {
    final row = await _client
        .from('profiles')
        .select('id, full_name, phone')
        .eq('id', _userId)
        .single();
    return Profile.fromJson(row);
  }

  Future<void> updateMyProfile(Profile profile) async {
    await _client
        .from('profiles')
        .update(profile.toUpdateJson())
        .eq('id', _userId);
  }
}

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(ref.watch(supabaseClientProvider));
});
