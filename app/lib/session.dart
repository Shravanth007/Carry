import 'analytics/analytics.dart';
import 'auth/auth.dart';
import 'notes/notes.dart';
import 'settings/avatar_cache.dart';

/// Drops everything held for whoever was signed in.
///
/// Called wherever a session ends, not only where somebody taps Sign out: a
/// session also ends when Firebase revokes the token, when the account is
/// deleted, or when a token stops refreshing. The notes list is app-wide, so
/// if it survived one of those the next person to sign in would open Carry
/// onto somebody else's recordings.
///
/// Best effort by design - the person is already out, and a storage hiccup
/// must not strand them on a signed-out screen.
Future<void> forgetSession() async {
  Notes.clear();
  await AvatarCache.clear();
  // The backup choice stays: it's this account's own setting, kept per
  // account, and asking again on every sign-in would be tiresome.
}

/// Signs out and forgets everything that belonged to the person signing out.
///
/// Sign-out itself comes first: if it fails, the account is still signed in
/// and its data should stay put. Clearing is best effort after that, because
/// by then the person is already out and a storage hiccup must not strand
/// them on a signed-out screen.
Future<void> signOutAndForget() async {
  // Counted first, while this is still the account being counted: signing out
  // makes AuthGate drop the analytics identity, and it may get there before
  // this line does. Forgetting who someone was lives there, not here.
  Analytics.event('signed_out');
  await Auth.signOut();
  // AuthGate does this too, on the stream. Doing it here as well costs two
  // cleared lists and means a sign-out from this screen is finished when this
  // future completes, rather than whenever the stream gets around to it.
  await forgetSession();
}
