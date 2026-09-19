# Welcome and permissions

What happens between signing in and the home screen: new users get a welcome
screen, returning users don't, and the microphone is asked for once, with a
reason.

## The route after sign-in

```
AuthGate         signed out → sign-in screen
   │ signed in
OnboardingGate   brand-new account → welcome (greeting)
   │                                     │
   │                  microphone already allowed? → skip
   │                                     ↓ otherwise
   │                                microphone screen
   │ account already exists               │
   ↓                                      ↓
home screen      shows a banner if the microphone is off
```

The two steps are gated on different things, because they're about different
things:

| Step | Asked about | Gate |
|---|---|---|
| Welcome | The person | Is this account **signing in for the first time ever**? |
| Microphone | The phone | Does **this phone** already allow the microphone? |

Consequences, all of them deliberate:
- An account that already exists goes straight to home, **even on a fresh
  install or a new phone**. Someone coming back doesn't get greeted like a
  stranger. If that phone needs the microphone, home's banner asks for it.
- A second account on a phone that already allows the microphone gets the
  greeting and nothing else. Nobody is asked for a permission the phone has
  already given.

**How "brand-new" is known:** Firebase stamps an account with a creation time
and a last-sign-in time. They match only until that account signs in a second
time, so matching times mean this is the first sign-in ever — a fact about the
account, so it survives reinstalls and new phones. Unknown times count as an
existing account, so nobody is welcomed twice.

The saved flag is a second guard, for the gap between the greeting and the end
of the flow: it stops a finished account from being onboarded again in the same
session.

`main.dart` wires the three together. Neither gate knows about the screens
past it: `AuthGate` is handed what to show when signed in, and `OnboardingGate`
is handed the home screen.

## New user or returning user?

`Onboarding` stores one flag per account on the device:

| Call | What it does |
|---|---|
| `Onboarding.isNewAccount(user)` | Is this the account's first sign-in ever? |
| `Onboarding.isDone(uid)` | Has this account finished onboarding on this phone? |
| `Onboarding.markDone(uid)` | Remember that it has. |

It's stored in the phone's own small key-value storage (shared preferences),
keyed by the Firebase user ID.

**Why the flag is per account and kept on the phone:**
- Per account, so a new second account on the same phone still gets greeted.
- On the phone, because the answer is needed at launch, before any network
  call, and it must work offline.
- It is only a guard for the current flow. Whether someone is new is decided
  by the account's own timestamps, so a reinstall doesn't re-welcome anyone.

**Where the user itself lives:** in Firebase Auth. That's the record of the
account (ID, email, name, photo), and the SDK keeps the session on the device
so people stay signed in between launches. Carry stores no copy of it. When the
server starts keeping notes, it will store rows keyed by the same Firebase user
ID, taken from the verified token, never from the request body.
See [auth.md](auth.md).

## The welcome screen

Greets a new account by first name ("Welcome, Ada"), or says "Welcome to Carry"
when Google gave no name, says in one line what Carry does, and offers
**Get started**. It deliberately says nothing about permissions, since it also
shows to people whose phone is already set up.

## The microphone screen

Only shows when the phone hasn't granted the microphone. It explains why before
the system prompt appears, and offers **Allow microphone** and **Not now**.
Either choice moves on to home. Saying no is not a dead end: home shows a
reminder banner.

The welcome is marked done only at the very end. An app closed part-way
through starts the flow again, rather than skipping an explanation the
person never saw.

## Microphone permission

All permission calls go through `Permissions`. It reduces the platform's
several states to three:

| State | Meaning | What the UI does |
|---|---|---|
| `granted` | Recording is allowed | Nothing |
| `denied` | Not allowed, but the system will still prompt | Offer **Turn on**, which prompts |
| `blocked` | The system won't prompt again ("never ask again", or a restricted phone) | Offer **Open settings** |

| Call | What it does |
|---|---|
| `Permissions.micStatus()` | Reads the state. Never prompts. |
| `Permissions.requestMic()` | Prompts if it can, and returns the state after. |
| `Permissions.openSettings()` | Opens the app's page in system Settings. |

**Android quirk that shapes the UI:** Android cannot report "never ask again"
from a status check. `micStatus()` returns `denied` for it, and only
`requestMic()` comes back `blocked` — resolved instantly by the system, with no
dialog shown. So after a "never ask again", the banner still says **Turn on**,
and the tap would otherwise do nothing visible. Home therefore opens Settings
itself as soon as a request comes back `blocked`. Don't "simplify" that away.

**On home:** the state is read when the screen opens, and again whenever the
app comes back to the foreground, so turning the permission on in Settings
clears the banner when the user returns.

**Android:** `RECORD_AUDIO` is already declared in the manifest. Declaring it
isn't permission. The prompt above is what grants it.

## Edge cases and what happens

| Case | Behavior |
|---|---|
| App is closed mid-flow | Nothing is saved until the end, so the flow starts again next launch |
| Existing account signs in | Straight home. No greeting, no permission screen |
| Signing out, then back in with the same account | Straight home |
| Existing account on a fresh install or new phone | Straight home. The banner asks for the microphone if that phone needs it |
| New second account, phone already allows the microphone | Greeting only. No permission screen, no prompt |
| New second account, microphone not allowed | Greeting, then the microphone screen |
| Returning account with the microphone turned off | Straight to home. The banner handles it, rather than onboarding again |
| User denies the microphone | Welcome finishes, home shows the banner, **Turn on** prompts again |
| User picks "never ask again" | The welcome switches to **Open settings** and stays put so the reason can be read. **Continue** moves on |
| A later launch after "never ask again" | The banner says **Turn on** (Android reports it as denied). Tapping it opens Settings, because no prompt can appear |
| Permission turned on in Settings | The banner clears when the app comes back to the foreground |
| Second account on the same phone | Gets its own welcome |
| Same account, new phone | Gets the welcome again |
| Signing out and back in | No welcome. The flag stays on the device |
| Offline | The whole flow works. Nothing here needs the network |

## Not covered yet

- **Notification permission** (Android 13+). It gets added when the server
  starts pushing "your note is ready".
- **iOS.** It needs `NSMicrophoneUsageDescription` in `Info.plist` (the sentence
  Apple shows in its prompt) and the `PERMISSION_MICROPHONE` flag in the
  Podfile. Without both, iOS crashes on the prompt or always denies.
- **Background recording.** Recording while the app isn't in front needs a
  foreground service and `FOREGROUND_SERVICE_MICROPHONE` in the manifest.
- **No way to replay the welcome.** It can go in settings later.
- **Signing out doesn't clear the flag.** That's deliberate: the same person
  signing back in shouldn't be welcomed twice.

## Testing

`setUpTestPrefs()` gives each test empty storage, and `setUpTestPermissions()`
stands in for the system prompts, where `answer` is what the user taps and
`prompts` and `settingsOpened` count what happened. Both are in
`test/helpers/test_device.dart`.

Covered: the flag per account, the gate's three routes, both welcome buttons,
denied and blocked, and the home banner appearing, clearing and opening
Settings.
