import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rental_app/core/supabase/supabase_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Length of the email confirmation code. Supabase's default is 6
/// (Dashboard -> Authentication -> Sign In / Providers -> Email -> "Email OTP Length").
/// If you change it there, change it here too.
const int kSignupCodeLength = 6;

/// All login/signup calls to Supabase Auth live here, so screens never talk
/// to Supabase directly. Screens call these methods and show errors.
class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  GoTrueClient get _auth => _client.auth;

  /// The logged-in user, or null when logged out.
  User? get currentUser => _auth.currentUser;

  Future<void> signIn({required String email, required String password}) async {
    await _auth.signInWithPassword(email: email, password: password);
  }

  /// Creates the account and emails a 6-digit confirmation code.
  ///
  /// Returns true if the user must now enter that code. Returns false if
  /// email confirmation is switched off in Supabase: the user is then
  /// logged in straight away.
  Future<bool> signUp({
    required String email,
    required String password,
    required String fullName,
  }) async {
    final response = await _auth.signUp(
      email: email,
      password: password,
      // Stored in auth.users.raw_user_meta_data; our handle_new_user()
      // database trigger copies full_name into the profiles table.
      data: {'full_name': fullName},
    );

    // For privacy, Supabase doesn't return an error when the email is already
    // registered. Instead it returns a user with no identities. We turn
    // that into a clear message.
    if (response.user?.identities?.isEmpty ?? false) {
      throw const AuthException(
        'An account with this email already exists. Please log in.',
        code: 'user_already_exists',
      );
    }

    return response.session == null;
  }

  /// Checks the code from the confirmation email. On success Supabase logs
  /// the user in, and the router moves them into the app automatically.
  Future<void> verifySignupCode({
    required String email,
    required String code,
  }) async {
    await _auth.verifyOTP(email: email, token: code, type: OtpType.signup);
  }

  /// Sends a new confirmation code (Supabase allows one per 60 seconds).
  Future<void> resendSignupCode(String email) async {
    await _auth.resend(email: email, type: OtpType.signup);
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  /// "Contact first, link later": connects any tenant contacts that staff
  /// created with this user's (confirmed) email to their account.
  /// Safe to call often; it does nothing if there is nothing to link.
  Future<void> linkTenantRecords() async {
    await _client.rpc('link_my_tenant_records');
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(supabaseClientProvider));
});
