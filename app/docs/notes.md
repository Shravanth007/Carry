# Notes, importing and settings

What the home screen shows, how audio gets in, and what moved to settings.

## Screens

| Screen | Shows |
|---|---|
| Home ("Notes") | The notes, a record button, an import button, and the recording bar while one runs |
| Settings | Account, permissions, backup, MCP (soon), sign out |
| Settings → Backup | Carry cloud switch, and Google Drive as upcoming |

Home's app bar has import and settings. The **Record** pill sits at the
bottom right, sized and placed for a thumb, because recording is the main
thing people open the app to do. Anything that isn't a note belongs in
settings.

## Recording

Tapping **Record** asks for the microphone if needed, then starts recording
and puts a black bar at the bottom of the same screen. There is no separate
recording screen on purpose: you keep seeing your notes, and the bar is the
one place that says a recording is running.

The bar shows a pulsing red dot, the elapsed time, a live level meter, and
**pause**, **throw away** and **Save**.

- **Pause** stops the clock and the meter, and the dot stops pulsing.
  Paused time isn't counted: 4s recorded, 30s paused, 2s recorded is a
  6-second note.
- **Throw away** asks first, and says how much would be lost.
- **Save** writes the note. Anything under a second is treated as a mis-tap:
  nothing is saved and the file is deleted.

**Quality:** mono AAC at 32 kbps, 16 kHz. An hour is about 14 MB, which is
under the transcriber's 25 MB limit and cheap to upload. Files live in the
app's own folder, named by timestamp.

**The phone can take the microphone back** (a call arrives, the app goes to
the background). Carry saves what it has rather than losing it. Recording
while the app isn't in front needs a foreground service and
`FOREGROUND_SERVICE_MICROPHONE`, which isn't built.

**One route in and out.** Everything recording-related goes through
`Recording`: the microphone permission, starting, pausing, saving, throwing
away, and the wording shown when any of it fails. Screens only draw and report
taps; they never touch `Recorder` or `Permissions` themselves. Underneath,
`Recorder` owns the state and the file, and the hardware sits behind
`RecorderBackend` so tests run a stand-in that writes real files.

**When things go wrong:**
- The phone refuses to stop → the bar keeps its controls and says so, so it
  can be tried again. It never leaves a bar nobody can use.
- Pause fails → the recording carries on and the screen says that, rather
  than showing a pause that didn't happen.
- The bar is torn down with nowhere to go (signing out, the screen being
  replaced) → the microphone is stopped and the file dropped. A recording
  with no controls is never left running.

## Notes

`Notes` holds the list the home screen renders, newest first. `Notes.all` is a
`ValueNotifier`, so home rebuilds when a note arrives and nothing has to be
refreshed by hand.

A note is: an id, **the owner's Firebase user ID**, a title (the time it was
recorded, or an imported file's name), the path to the audio on the phone,
when it was added, and its length and size where known.

**Every note carries its owner.** It comes from the signed-in account, never
from anything typed in, and the server will do the same from the verified
token. That's what keeps two accounts on one phone apart, and it's what note
rows will be keyed on.

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
| Under `Limits.uploadBytes` (25 MB) | "That file is over 25 MB. Pick a shorter one." |

Home shows these in a snackbar. A refused file adds nothing.

**Why the size cap:** the transcriber refuses a file over 25 MB, so carrying
a bigger one across the network would only end in a failure later. The number
lives in `lib/limits.dart` with the recording cap, not here.

## Limits

`lib/limits.dart` holds both caps the app checks:

| Limit | Value | What the app does |
|---|---|---|
| One recording | 1 hour (about 14 MB at our bitrate) | The bar saves it and says "That is as long as a recording can be, so Carry saved it." |
| One file | 25 MB | Import refuses it before anything is read |

**These are courtesies, not protection.** The repo is public, so a client that
ignores them is a fifteen-minute job. The server checks the same numbers again
from the token and from the file it receives, and that is the check that
counts — see [../../server/docs/security.md](../../server/docs/security.md).
What the app's gate buys is the person hearing "no" in the moment rather than
after a long upload.

**Watch out:** some pickers return a whole path where a file name is expected,
so the name is taken from the last path segment rather than trusted.

**Two filters, one group:** Android filters by extension and MIME type, iOS by
uniform type identifier, and iOS throws on a type group that gives it none. The
group carries all three, and `public.audio` deliberately lets more through than
the extension list — the check above is what actually decides. See
[ios.md](ios.md).

## Not built yet

- **Uploading.** An imported note sits on the phone. The sync queue and the
  server's upload endpoint come next, and the tile reads "Not transcribed yet"
  until then.
- **Opening a note.** Tiles don't tap through to anything.
- **Deleting a note.**
- **Orphan recordings.** If the app is killed mid-recording, the file stays in
  the app folder with nothing pointing at it. A sweep at startup belongs with
  the database work.
- **A length warning.** Nothing stops an accidental eight-hour recording.
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

  The rule says no unless the flag and the stamp agree, and both are read for
  the one account that was signed in when it was asked, re-checked before the
  answer comes back. A half-written change and a sign-out mid-question both
  land on "don't upload", which is the only safe way to be wrong here. That's
  also why `setOn` writes the stamp before the flag in both directions.

  Google Drive sits under it as a "Soon" row, for people who would rather keep
  recordings in their own Drive.
- **MCP:** a placeholder row, greyed out with a "Soon" badge. It will let AI
  tools read your notes; nothing is behind it yet. Tapping it says so rather
  than doing nothing, and sends `soon_tapped` — so the count of taps is how we
  find out whether to build it. Google Drive under Backup works the same way.
  See [analytics.md](analytics.md).
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

`setUpTestRecorder()` stands in for the microphone, writing real files into a
temporary folder so size and deletion behave as they would on a phone. Widget
tests also lend the recorder their clock, and **must not use `pumpAndSettle`
while the bar is on screen**: its level meter ticks by design, so nothing ever
settles.

Covered: every check above, cancel, newest-first order, the empty state, the
snackbar, opening settings, and each settings row.
