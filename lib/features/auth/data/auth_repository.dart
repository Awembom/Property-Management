import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rental_app/core/supabase/supabase_providers.dart';
import 'package:rental_app/features/auth/data/account_type.dart';
import 'package:rental_app/features/auth/data/username.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// All login/signup calls to Supabase Auth live here, so screens never talk
/// to Supabase directly. Screens call these methods and show errors.
///
/// People log in with a username; see username.dart for how that maps to
/// the email Supabase needs.
class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  GoTrueClient get _auth => _client.auth;

  /// The logged-in user, or null when logged out.
  User? get currentUser => _auth.currentUser;

  /// True after an owner/manager gave this user a temporary password: they
  /// must choose a new one before using the app. The flag is in the user's
  /// app_metadata, which only the server can set.
  bool get mustChangePassword =>
      currentUser?.appMetadata['must_change_password'] == true;

  Future<void> signIn({required String username, required String password}) async {
    await _auth.signInWithPassword(email: usernameToEmail(username), password: password);
  }

  /// Creates the account and logs in straight away (no email confirmation).
  Future<void> signUp({
    required String username,
    required String password,
    required String fullName,
    required AccountType accountType,
  }) async {
    final response = await _auth.signUp(
      email: usernameToEmail(username),
      password: password,
      // Stored in auth.users.raw_user_meta_data; the handle_new_user()
      // database trigger copies them into the profiles table.
      data: {
        'full_name': fullName,
        'username': normalizeUsername(username),
        'account_type': accountType.value,
      },
    );

    // With "Confirm email" on, Supabase hides "already registered" behind a
    // user with no identities; turn that into a clear message.
    if (response.user?.identities?.isEmpty ?? false) {
      throw const AuthException('Username taken', code: 'user_already_exists');
    }
    // No session = Supabase still wants an email confirmation, which can't
    // work with usernames. The project setting must be switched off.
    if (response.session == null) {
      throw const AuthException(
        'Account created, but Supabase is asking for email confirmation. '
        'Switch off "Confirm email" in Supabase (Authentication -> Sign In / '
        'Providers -> Email), then log in.',
        code: 'confirmation_required',
      );
    }
  }

  /// Sets a new password for the logged-in user and clears the
  /// "must change password" flag.
  Future<void> changePassword(String newPassword) async {
    await _auth.updateUser(UserAttributes(password: newPassword));
    await _client.rpc('password_changed');
    // Get a fresh login token, so the cleared flag reaches the app (the router
    // listens for this and lets the user into the app).
    await _auth.refreshSession();
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  /// Checks with the server that the saved login still belongs to an
  /// existing account. If the account was deleted (or the login revoked),
  /// logs out on this phone only, so the login screen appears instead of an
  /// app that can't load anything. Without internet it does nothing (the
  /// saved login stays and is checked again next time).
  Future<void> dropLoginIfAccountGone() async {
    if (_auth.currentSession == null) return;
    try {
      await _auth.getUser();
    } on AuthException catch (e) {
      final status = int.tryParse('${e.statusCode}');
      const goneCodes = {'user_not_found', 'session_not_found', 'bad_jwt', 'refresh_token_not_found'};
      if (goneCodes.contains(e.code) || status == 401 || status == 403 || status == 404) {
        await _auth.signOut(scope: SignOutScope.local);
      }
    } catch (_) {
      // No internet or similar: keep the saved login for now.
    }
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(supabaseClientProvider));
});
