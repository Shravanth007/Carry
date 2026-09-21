import 'auth/auth.dart';
import 'notes/notes.dart';
import 'settings/avatar_cache.dart';

/// Signs out and forgets everything that belonged to the person signing out.
///
/// Sign-out itself comes first: if it fails, the account is still signed in
/// and its data should stay put. Clearing is best effort after that, because
/// by then the person is already out and a storage hiccup must not strand
/// them on a signed-out screen.
Future<void> signOutAndForget() async {
  await Auth.signOut();
  Notes.clear();
  await AvatarCache.clear();
  // The backup choice stays: it's this account's own setting, kept per
  // account, and asking again on every sign-in would be tiresome.
}
