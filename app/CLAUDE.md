# CLAUDE.md — Carry app

Guidance for Claude Code when working on the Carry Flutter app.

## What this is

Carry is a voice notes app. You record a thought, the server transcribes it,
and it comes back as a written note. Android comes first and iOS later.
The backend lives in `../server` and has its own CLAUDE.md.

**Stack:** Flutter, Firebase Auth, and Material 3 with our own theme.
**Planned:** Drift (SQLite), an audio recorder, and an upload sync queue.

## Docs: read the one for the area you're working on

| Working on... | Read |
|---|---|
| Sign-in, tokens, Firebase setup, calling the server | [docs/auth.md](docs/auth.md) |
| Welcome screen, new vs returning users, permissions | [docs/onboarding.md](docs/onboarding.md) |
| Home screen, notes, importing audio, settings | [docs/notes.md](docs/notes.md) |

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

CI (`.github/workflows/ci.yml`) runs the same three on every push to a PR:
`dart format --set-exit-if-changed`, `flutter analyze`, `flutter test`, plus a
debug APK build. A formatting slip fails the build, so run `dart format`
before pushing.

## Rules

### Architecture
- Each feature exposes one entry point, and the rest of the app goes through
  it. For auth that's the `Auth` class. See the doc.
- Features don't reach into each other.
- Screens take plain values, not Firebase objects, so they can be previewed
  and tested.
- Before `runApp`, only initialize Firebase and `Auth`. Everything else runs
  after the first frame.

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

- **Real services:** tests never use real Firebase, Google or the network. Use
  the shared test setup in `test/helpers/`. The feature's doc explains how.
- **Screens:** render them with `pumpScreen(tester, screen)`, which uses a phone
  size. While a spinner is showing, use `pump()`, not `pumpAndSettle()`.
- **What to cover in each flow:** success, the user cancelling, every error the
  user can see, the loading state, and retry.
- **Test names** describe behavior, e.g. "closing the picker shows no error".

## Planning

For non-trivial work:
1. List the edge cases first: empty data, cancel, offline, double taps,
   sign-out mid-flow, and the app going to the background.
2. Check the design against each one.
3. Play the plan back to the user and get an OK before coding.

## Git

- Commit format: `type(app): description`.
  - `type` is one of feat, fix, docs, refactor, test, chore.
  - Imperative mood, subject under 50 characters.
- **No Claude co-author lines and no Claude session links in commits or PRs.**

Keep this file current when you add features, docs, commands or rules.
