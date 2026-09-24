# Analytics

Carry sends product events to [PostHog](https://posthog.com) so it's possible
to see where people get stuck — a microphone they never allow, an import that
keeps getting refused, a recording that never becomes a note.

## The rule

**`lib/analytics/analytics.dart` is the only file that knows about PostHog.**
Nothing else imports `posthog_flutter`.

**Events are sent from the facades, never from a widget.** `Auth`,
`Recording`, `Permissions`, `audio_import` and `Api` already work out what
happened and why — they return the sentence the person is shown. An event sent
from the same place can't disagree with it. A `build` method is the wrong place
twice over: it runs again on every rebuild, and it doesn't know why anything
happened.

```dart
Analytics.event('recording_saved', {'seconds': 42, 'size': '5-15MB'});
Analytics.screen('settings');
```

## Turning it on

Nothing is sent unless the build carries a key:

```
flutter run --dart-define=POSTHOG_KEY=phc_xxx
flutter build apk --dart-define=POSTHOG_KEY=phc_xxx
```

An EU project also needs `--dart-define=POSTHOG_HOST=https://eu.i.posthog.com`.

Without the key `Analytics.isOn` is false and every call is a no-op, which is
how development runs, `flutter test` and CI all stay silent. The key is a
PostHog *project* key: it can only write events, so like the Firebase Android
key it isn't a secret — it comes from the build rather than the source so a
fork doesn't post into this project.

PostHog is started from Dart, so `AndroidManifest.xml` sets
`com.posthog.posthog.AUTO_INIT` to `false`. When `ios/` arrives, `Info.plist`
needs the same key.

What's deliberately off: **session replay** (it would film someone's notes),
feature flags (none exist, and preloading them costs a request on every
start), and push notification capture (there is no push).

## The events

**Signing in** — `auth/auth.dart`, `session.dart`

| Event | Properties |
|---|---|
| `sign_in_started` | |
| `sign_in_succeeded` | `is_new_account` |
| `sign_in_cancelled` | the account picker was closed, which is not a failure |
| `sign_in_failed` | `reason`: a code like `clientConfigurationError`, never the message |
| `signed_out` | sent before `reset()`, so it belongs to the person leaving |

**Onboarding** — `onboarding/onboarding.dart`

| Event | Properties |
|---|---|
| `welcome_continued` | |
| `onboarding_finished` | `asked_for_mic` — false when the phone had already granted it |

**Microphone** — `permissions/permissions.dart`

| Event | Properties |
|---|---|
| `mic_requested` | `where`: `onboarding` / `recording` / `settings` |
| `mic_result` | `where`, `status`: `granted` / `denied` / `blocked` |
| `mic_settings_opened` | `where` |

**Recording** — `recording/recording.dart`

| Event | Properties |
|---|---|
| `recording_started` | |
| `recording_start_failed` | `reason`: `signed_out` / `mic_denied` / `mic_blocked` / `hardware` |
| `recording_paused`, `recording_resumed` | `at_seconds` |
| `recording_pause_failed` | `was_paused` |
| `recording_saved` | `seconds`, `size`, `stopped_by`: `user` / `length_limit` / `app_backgrounded`, `notes_after` |
| `recording_too_short` | `seconds`, `stopped_by` |
| `recording_stop_failed` | `stopped_by` |
| `recording_discarded` | `seconds`, `by`: `user` / `abandoned` |
| `recording_refused` | `reason`, `seconds`, `size` — the gate turned it away and the file was deleted |

**Importing** — `notes/audio_import.dart`

| Event | Properties |
|---|---|
| `import_opened`, `import_cancelled` | |
| `import_rejected` | `reason`, `extension`, `size` |
| `import_added` | `extension`, `size`, `notes_after` |

**Settings** — `settings/`, `backup/`

| Event | Properties |
|---|---|
| `backup_toggled` | `on` — sent by `Backup.setOn`, the line that stores it, not by the switch |
| `soon_tapped` | `feature`: `mcp` / `google_drive` — a tap on something unbuilt is someone asking for it |

**The server** — `api/api.dart`

| Event | Properties |
|---|---|
| `api_failed` | `endpoint`, `kind`, `status`, `request_id` |
| `api_token_refreshed` | `endpoint` — how often the 401 retry actually fires |

`kind` is one of `signed_out`, `offline`, `timeout`, `unreachable`,
`unauthorized`, `forbidden`, `missing`, `too_large`, `rate_limited`,
`server_error`, `refused`, `bad_body`, `wrong_shape`.

**Refusal reasons are shared.** `Notes.addAudio` is the one gate audio passes
through, and it returns a code: `no_owner`, `empty`, `too_large`, `too_short`,
`account_changed`. Both `recording_refused` and `import_rejected` carry it, so
the two paths read the same way in a funnel. `import_rejected` also has reasons
of its own from before the gate: `signed_out`, `wrong_type`, `could_not_copy`.

**`request_id` is the useful one.** Every request carries an `X-Request-ID`
header, the server logs it and sends it back, so an event in PostHog points at
one line in the server's log. "It didn't work" becomes one search.

## Counted once, not once per rebuild

An event must fire when something happens, not while something is being drawn.
Two places this bites:

- Screen views for `sign_in` come from `AuthGate`'s auth subscription when the
  state **changes** to signed out — a rebuild of the gate doesn't add an
  arrival. That transition is also where `Analytics.reset()` lives, so a
  session Firebase ends by itself (a revoked token, a deleted account) drops
  the identity too. `signOutAndForget` only sends `signed_out`, before the
  sign-out, while that is still the account being counted.
- `recording_discarded` is only sent when a recording was actually running, and
  `recording_paused` only when the pause took effect, because the recorder
  ignores an answer that arrives after the recording has moved on.

`TestAnalytics.only(name)` fails when an event was sent twice, which is the
cheapest guard against this.

## Screens

There is no router — screens are pushed directly and onboarding is a `switch` —
so screen views are sent from the place that decides to show a screen, not from
the screen itself: `AuthGate` (`sign_in`), `OnboardingGate` (`welcome`,
`microphone`, `home`), and the buttons that push `settings`, `permissions` and
`backup`.

## Never send

| Don't | Why |
|---|---|
| A note title | An imported note is titled after the file: "Chat with Dr Rao" |
| A file name or path | Same, plus a path carries the device's user name |
| Email, display name, photo URL | Firebase has them. PostHog doesn't need them |
| The text of an exception | It can carry a path or a URL. Send a code |
| A token, a key, a URL from the server | Obvious, and error logging is how these leak |
| An exact byte count or note count | Use `Analytics.sizeBucket` and `countBucket`. An exact size next to a timestamp identifies a recording |

**The `extension` property comes from a fixed list.** The text after the last
dot is only an extension by convention: in `appointment.Rao` it is part of
someone's name, and `Rao` is short enough to pass any length check. So
`audio_import.dart` reports a type only when it is one of `audioExtensions` or
one of a fixed list of other known types (`mp4`, `pdf`, `jpg`, …), and `other`
for everything else. Nothing read from a file name can leave the phone.

The person is identified by their Firebase uid — the same key the server uses —
and nothing else. `created_at` and `is_new_account` are set once.

## Testing

Tests never send anything. The sink is silent unless a test asks:

```dart
final events = setUpTestAnalytics();
await Recording.begin();
expect(events.only('recording_start_failed').properties, {'reason': 'signed_out'});
```

`setUpTestAnalytics()` (in `test/helpers/test_analytics.dart`) collects events
and puts the silent sink back afterwards. `only(name)` fails unless exactly one
event of that name was sent, which catches an event fired twice.

Analytics must never break the app: `Analytics.init` swallows a failed start,
every send is fire-and-forget, and reading the account for `sign_in_succeeded`
is wrapped in a try/catch. A missing event is a bad day; a sign-in that fails
because of an event is a bug.

## Not done yet

- **Nothing on the server.** Every backend outcome today (`401`, `403`, `429`)
  is already in its access log with the same request ID. It's worth adding
  PostHog there when transcription lands, because whether Groq failed or took
  40 seconds is the one thing the app can't see.
- **No consent toggle.** A "Share usage data" row in settings would fit the
  existing pattern.
- **Flutter error capture** (`captureFlutterErrors`) is off: stack traces can
  carry paths, and crash reporting is a separate decision.
