# Notes, importing and settings

What the home screen shows, how audio gets in, and what moved to settings.

## Screens

| Screen | Shows |
|---|---|
| Home ("Notes") | The notes, a record button, and an import button. Nothing else |
| Settings | Account, permissions, backup, MCP (soon), sign out |
| Settings → Backup | Carry cloud switch, and Google Drive as upcoming |

Home's app bar has import and settings. The **Record** pill sits at the
bottom right, sized and placed for a thumb, because recording is the main
thing people open the app to do. Anything that isn't a note belongs in
settings.

**Recording isn't built yet.** The button is real, and so is its microphone
check: it asks for the microphone, says what to do when that's refused, and
then reports that recording is coming. The `ponytail:` comment in
`home_screen.dart` marks the line to replace with the recorder.

## Notes

`Notes` holds the list the home screen renders, newest first. `Notes.all` is a
`ValueNotifier`, so home rebuilds when a note arrives and nothing has to be
refreshed by hand.

A note is: an id, a title (the file name without its extension), the path to
the audio on the phone, and when it was added.

**Today they live in memory**, so they disappear when the app restarts. That's
marked in the code with a `ponytail:` comment. Drift replaces the list, and
nothing outside `notes.dart` should need to change.

## Importing audio

`importAudio()` opens the phone's file picker, checks what comes back, and
adds a note. It returns a note, or an error sentence meant to be shown as
written. Both are null when the user cancels, so cancelling says nothing.

The file comes from outside the app, so nothing about it is trusted:

| Check | Message |
|---|---|
| Extension is one we transcribe (m4a, mp3, wav, aac, ogg, opus, flac, amr, wma) | "That isn't an audio file. Pick a recording." |
| Not empty | "That file is empty. Pick another recording." |
| Under 200 MB | "That file is over 200 MB. Pick a shorter one." |

Home shows these in a snackbar. A refused file adds nothing.

**Why the size cap:** the file has to survive an upload later. 200 MB is
roughly a long meeting at ordinary quality. Raise it in `audio_import.dart`
if real recordings hit it.

**Watch out:** some pickers return a whole path where a file name is expected,
so the name is taken from the last path segment rather than trusted.

## Not built yet

- **Uploading.** An imported note sits on the phone. The sync queue and the
  server's upload endpoint come next, and the tile reads "Not transcribed yet"
  until then.
- **Opening a note.** Tiles don't tap through to anything.
- **Deleting a note**, and **recording inside Carry**.
- **Copying the file.** The note points at the file where the user picked it.
  If they delete it, the path goes stale. Copying into the app's own storage
  belongs with the upload work.

## Settings

- **Account:** the Google profile photo, name and email. No photo, or offline
  with nothing saved, falls back to the first letter on a dark circle.

  The photo is downloaded once and kept on the phone (`AvatarCache`), so it
  appears instantly on later launches and works offline. Google's URL changes
  when the picture does, so the URL is stored alongside it and a change
  re-fetches. If the new one can't be fetched, the old picture stays: a
  slightly old face beats an empty circle. Anything that isn't a small image
  (an error, an empty body, over 64 KB) is refused. Signing out forgets it.
  No caching package: this is one file over the storage we already had.
- **Permissions:** opens its own screen, so more permissions (notifications,
  later) have a home. The microphone is a switch there:
  - on → asks the system,
  - off, or already blocked → a dialog explains that the phone keeps
    permissions and offers **Open settings**. An app cannot take its own
    permission away, and a switch that silently flicks back reads as broken.
  - If settings won't open (web, or a phone that refuses), a message gives the
    manual route: Settings → Apps → Carry → Permissions.
  It re-checks when the app comes back to the foreground. See
  [onboarding.md](onboarding.md) for the three states.
- **Backup:** opens its own screen. **Off until the person turns it on**, and
  turning it on covers **new recordings only**, so the moment it was switched
  on is stored next to the flag. A recording made before that was made under
  the old answer, and uploading it later would be a surprise. Turning it off
  clears the stamp, so switching it on again doesn't sweep up the gap. Stored
  per account, and false while signed out, so nothing uploads without an
  owner. `Backup.shouldUpload(addedAt)` is the rule the upload queue will
  follow. **Nothing uploads yet**: no upload endpoint exists.

  Google Drive sits under it as a "Soon" row, for people who would rather keep
  recordings in their own Drive.
- **MCP:** a placeholder row, greyed out with a "Soon" badge and no tap. It
  will let AI tools read your notes. Nothing behind it yet.
- **Sign out:** `signOutAndForget()` in `lib/session.dart`. It signs out of
  Firebase and Google, then drops the notes and the saved profile picture, so
  the next person to sign in on this phone sees nothing of the last one.
  Sign-out comes first on purpose: if it fails, the account is still signed in
  and its data stays. See [auth.md](auth.md).

Rows are built from `SettingsRow` inside a `SettingsCard`, both in
`settings/widgets.dart`. **Don't use `ListTile` here:** it paints its own
background onto the nearest `Material`, which swallowed these rows on the cream
theme.

## Testing

`setUpTestFilePicker()` stands in for the file picker: set `pick` to a file
built with `testFile('name.m4a', bytes: …)`, or null for cancel. It's in
`test/helpers/test_files.dart`.

Covered: every check above, cancel, newest-first order, the empty state, the
snackbar, opening settings, and each settings row.
