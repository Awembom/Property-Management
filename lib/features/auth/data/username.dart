/// Usernames instead of emails.
///
/// Supabase Auth needs an email for every account, so behind the scenes a
/// username becomes `<username>@users.rentalapp.invalid`. ".invalid" is a
/// domain that can never exist (it's reserved for exactly this), so no email
/// is ever sent to anyone. Users only ever see and type their username.
///
/// If Supabase ever refuses this domain, change it here (one place); but
/// existing accounts keep the old one, so do it before real users sign up.
const String kUsernameEmailDomain = 'users.rentalapp.invalid';

/// What people type, tidied up: no spaces around it, lower-case
/// ("  Tina " -> "tina"). Usernames are not case-sensitive.
String normalizeUsername(String username) => username.trim().toLowerCase();

/// 'tina' -> 'tina@users.rentalapp.invalid'
String usernameToEmail(String username) =>
    '${normalizeUsername(username)}@$kUsernameEmailDomain';

/// Same rule as the database (profiles.username check): 3-30 characters,
/// lower-case letters, digits, dots and underscores, starting with a letter
/// or digit.
final RegExp kUsernamePattern = RegExp(r'^[a-z0-9][a-z0-9._]{2,29}$');
