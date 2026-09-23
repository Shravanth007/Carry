# CLAUDE.md — Carry app

Guidance for Claude Code when working on the Carry Flutter app.

## What this is

Carry is a voice notes app. You record a thought, the server transcribes it,
and it comes back as a written note. Android comes first; iOS is being stood
up next to it, and [docs/ios.md](docs/ios.md) is the runbook.
The backend lives in `../server` and has its own CLAUDE.md.

**Stack:** Flutter, Firebase Auth, and Material 3 with our own theme.
**Planned:** Drift (SQLite), an audio recorder, and an upload sync queue.

## Docs: read the one for the area you're working on

| Working on... | Read |
|---|---|
| Sign-in, tokens, Firebase setup, calling the server | [docs/auth.md](docs/auth.md) |
| Welcome screen, new vs returning users, permissions | [docs/onboarding.md](docs/onboarding.md) |
| Home screen, notes, importing audio, settings | [docs/notes.md](docs/notes.md) |
| Building for iOS, signing, what differs from Android | [docs/ios.md](docs/ios.md) |
| Events, what we send to PostHog and what we never send | [docs/analytics.md](docs/analytics.md) |

Each feature gets its own doc in `docs/` explaining how it works. When you add
a doc, add a row here. When you change how a feature works, update its doc.

## Structure

- Code is organised by feature. Each feature gets its own folder under `lib/`
  (auth, home, settings, recording, ...).
- `test/` mirrors `lib/`, and shared test setup lives in `test/helpers/`.
- App-wide pieces sit at the top of `lib/`: the entry point and the theme.

## Commands

```
flutter run                      # r = hot reload, R = hot restart
flutter widget-preview start     # see screens in Chrome, no Firebase needed
flutter test
flutter analyze
dart format lib test
```

No hooks run automatically. Format, analyze and test yourself before calling
work done.

CI (`.github/workflows/ci.yml`) runs on every push to a PR, but only for the
part of the monorepo you touched:

| You changed | CI runs |
|---|---|
| Any file under `app/` | format, analyze, test (~1 min) |
| `app/android/` or `app/pubspec.*` | the above plus a debug APK build (~5 min) |
| `app/ios/` or `app/pubspec.*` | an unsigned iOS build, once `app/ios/` exists |
| `server/` only | pytest, and the Flutter jobs skip |
| anything else | everything |

`dart format --set-exit-if-changed` is part of it, so a formatting slip fails
the build. Run `dart format lib test` before pushing.

**Pinned on purpose:** `permission_handler` is held at `^12`. Version 13
compiles against SDK 37, which the Android SDK currently publishes only as
`android-37.0`, and Gradle can't match it. Don't bump it until a plain
`platforms;android-37` exists.

## Rules

### Architecture
- Each feature exposes one entry point, and the rest of the app goes through
  it: `Auth` for sign-in, `Recording` for the microphone, `Api` for the
  server. See their docs.
- **Only `lib/api/api.dart` talks to the backend.** Nothing else imports
  `http` or knows the base URL. A new endpoint is a new method on `Api`.
  The one exception is `AvatarCache`, which downloads a Google profile
  picture: another host, no Carry token.
- Features don't reach into each other.
- Numbers the server also enforces live in `lib/limits.dart`, never inline in
  a screen. The app's copy is there to answer quickly; the server's is the one
  that decides.
- **Analytics go through `lib/analytics/analytics.dart`, and events are sent
  from the feature facades, never from a widget.** A facade knows why something
  happened; a `build` method doesn't, and it runs again on every rebuild. See
  the doc for what must never be sent.
- Screens take plain values, not Firebase objects, so they can be previewed
  and tested.
- Before `runApp`, only initialize Firebase, `Auth` and `Analytics` — the
  third because the first screen someone sees should be counted, and it does
  nothing at all in a build with no key. Everything else runs after the first
  frame.

### UI
- Colors come from `CarryColors`. Screens have no hex values, except the
  Google sign-in button, which follows Google's branding rules.
- Text styles come from `Theme.of(context).textTheme` with `copyWith`.
- Every screen gets a `@Preview` that uses `wrapper: previewApp`.
- Layouts must hold up on a small phone with large text: `test/responsive_test.dart`
  pumps every screen at three phone sizes and two text sizes, and fails on
  anything that doesn't fit. Add new screens to it.
- Wrap text inside a `Row` in `Flexible`. For a full-height screen, use
  `ScrollableColumn` so it scrolls instead of overflowing.

### Copy
- Sentence case and plain verbs.
- Buttons say exactly what happens.
- Errors say what went wrong and what to do next. If the user cancels, show nothing.

### Code
- Read the whole file before changing it. Delete replaced code.
- Comments explain why, not what.
- No `!` on fields in widget code. Copy the field to a local first and null-check it.
- Don't add a package for something a few lines can do.

## Testing

Every change comes with tests, and `flutter test` must pass.

- **Real services:** tests never use real Firebase, Google, PostHog or the
  network. Use the shared test setup in `test/helpers/`. The feature's doc
  explains how. Analytics is silent unless a test calls `setUpTestAnalytics()`.
- **Screens:** render them with `pumpScreen(tester, screen)`, which uses a phone
  size. While a spinner is showing, use `pump()`, not `pumpAndSettle()`.
- **What to cover in each flow:** success, the user cancelling, every error the
  user can see, the loading state, and retry.
- **Test names** describe behavior, e.g. "closing the picker shows no error".

## Before raising a PR: review your own diff

`flutter analyze` and a green suite are not a review. Tests written alongside
the code agree with the code's own assumptions, so they cannot catch an
assumption that was wrong. **Read the whole diff before opening the PR**, as if
someone else wrote it, and look for the things a test can't see:

1. **Read `git diff main...HEAD` top to bottom.** Every hunk. If a hunk is hard
   to explain out loud, that's the one with the bug in it.
2. **Check each change against the rule it is supposed to follow** — the rules
   in this file and in the feature's doc. Breaking a rule you wrote in the same
   PR is the easiest mistake to make and the easiest to catch by re-reading.
3. **Anything in a `build` method that isn't drawing.** A build runs again on
   every rebuild: no side effects, no counting, no navigation, no writes.
4. **Anything that can fire twice**, or fire when nothing happened: a teardown
   path, a stream that re-emits, a call that was ignored further down.
5. **Follow every value that leaves the app** — to the server, to analytics, to
   a log — back to where it came from. If any of it is user text, a file name or
   an exception message, it is a leak until proven otherwise.
6. **New package?** Build the app, not just the tests. A plugin that breaks the
   Android build passes every unit test first.
7. **Then run it:** `dart format lib test`, `flutter analyze lib test`,
   `flutter test`. Zero issues, and read the failures rather than re-running.

Write the one-line reason for each finding into the PR body. If the review finds
nothing, say so in the PR: that is a claim worth making explicitly.

## Planning

For non-trivial work:
1. List the edge cases first: empty data, cancel, offline, double taps,
   sign-out mid-flow, and the app going to the background.
2. Check the design against each one.
3. Play the plan back to the user and get an OK before coding.

## Git

- `main` is protected: no direct pushes, even for admins. Work on a branch,
  open a PR, and merge once the **All checks** gate is green and review
  conversations are resolved.
- Commit format: `type(app): description`.
  - `type` is one of feat, fix, docs, refactor, test, chore.
  - Imperative mood, subject under 50 characters.
- **No Claude co-author lines and no Claude session links in commits or PRs.**

Keep this file current when you add features, docs, commands or rules.
