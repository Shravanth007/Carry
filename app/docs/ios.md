# Carry on iOS

Standing the iOS build up next to the Android one: what to install, what to
generate, and what behaves differently once it runs.

## Where it stands

The `ios/` folder does not exist yet. Until `flutter create --platforms=ios .`
has run, `lib/firebase_options.dart` throws `UnsupportedError` for iOS, so the
app would stop at launch. Everything else is ready: every iOS plugin is
already resolved in `pubspec.lock` (`record_ios`, `google_sign_in_ios`,
`permission_handler_apple`, `file_selector_ios`, `path_provider_foundation`,
`shared_preferences_foundation`), and all the Dart tests are
platform-neutral, so `flutter test` is unaffected by any of this.

The goal here is a build that runs on your own iPhone. Nothing below is about
the App Store.

## Before you start

| You need | Why |
|---|---|
| A Mac with **Xcode** (not just Command Line Tools) | Only Xcode builds and signs an iOS app. `xcode-select -p` must point inside `Xcode.app`. |
| **CocoaPods** | Flutter's iOS plugins are Pods. `flutter run` calls `pod install` for you. |
| An iPhone on **iOS 15 or newer** | `firebase_core 4.14.0` pulls the Firebase iOS SDK 12, which floors the deployment target at 15.0. That's the highest floor in the tree, so it sets the target. |
| A plain **Apple ID** | Free personal-team signing runs the app on your own device. The paid Developer Program is only for distribution. |

**Free signing has two limits**, both fine for a demo: the provisioning
profile lasts 7 days, after which you rebuild from Xcode to refresh it, and a
device holds at most three free-signed apps at a time.

## Setup, step by step

**1. Install the toolchain.**
```
xcode-select -p                                    # must be inside Xcode.app
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
xcodebuild -downloadPlatform iOS                   # SDK + a simulator runtime
sudo gem install cocoapods
flutter doctor                                     # the iOS row must be clean
```

**2. Generate the platform folder** (in `app/`):
```
flutter create --platforms=ios .
```
This writes `ios/` and adds an `ios` entry to `.metadata`. It touches nothing
in `lib/`, `test/` or `android/`.

**3. Set the bundle ID and the deployment target.** The bundle ID matches
Android's `applicationId` so both stores and both Firebase apps line up:

| Where | Set to |
|---|---|
| Xcode → Runner target → General → Bundle Identifier | `com.carry.carry` |
| Xcode → Runner target → Build Settings → iOS Deployment Target | `15.0` |
| `ios/Podfile`, first line | `platform :ios, '15.0'` |

**4. Register the iOS app with Firebase.** In the console, open **carry-92aeb**
→ Add app → iOS, with bundle ID `com.carry.carry`. Then, in `app/`:
```
dart pub global run flutterfire_cli:flutterfire configure \
  --project=carry-92aeb --platforms=ios
```
That writes `ios/Runner/GoogleService-Info.plist` and fills in the iOS branch
of `lib/firebase_options.dart`. Like `google-services.json`, the plist only
identifies the project, so it is safe to commit — see
[auth.md](auth.md) for what is and isn't a secret.

**5. Add the Info.plist keys.** In `ios/Runner/Info.plist`:

| Key | Value |
|---|---|
| `NSMicrophoneUsageDescription` | "Carry uses the microphone to record your voice notes." Apple shows this sentence in the prompt, so it follows the copy rules: plain, and it says what happens. |
| `GIDClientID` | `CLIENT_ID` from `GoogleService-Info.plist`. Android reads this from `google-services.json`; on iOS it has to be written here, or `Auth.init()` fails at launch. |
| `CFBundleURLTypes` → one entry with `REVERSED_CLIENT_ID` | The URL scheme Google redirects back to after the account picker. Without it sign-in opens and never returns. |

**6. Trim permission_handler in the Podfile.** `permission_handler_apple`
compiles every permission it supports unless told otherwise. Add to
`post_install` in `ios/Podfile`:
```ruby
target.build_configurations.each do |config|
  config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= [
    '$(inherited)', 'PERMISSION_MICROPHONE=1',
  ]
end
```
Everything not listed is compiled out, so the binary holds no permission API
Carry doesn't use.

**7. Sign and run.** In Xcode → Runner → Signing & Capabilities, set Team to
your Apple ID's Personal Team. Then on the phone, trust it once under
Settings → General → VPN & Device Management. After that:
```
flutter devices
flutter run -d <device-id>
```

## Already done in the code

- **The file picker.** iOS filters by uniform type identifier and throws on a
  type group that gives it none, so the Android-shaped `extensions` +
  `mimeTypes` filter in `audio_import.dart` would have raised an
  `ArgumentError` the first time Import was tapped. The group now also carries
  `uniformTypeIdentifiers: ['public.audio']`, which Android ignores. The
  extension check after the pick is still what decides what's accepted, so a
  looser picker filter changes nothing about what gets in.
- **CI.** The workflow has an `ios` job that builds unsigned. It stays skipped
  until `app/ios/` exists, then turns itself on — see below.

## What differs from Android

| Thing | Android | iOS |
|---|---|---|
| "Never ask again" | `micStatus()` reports `denied`; only `requestMic()` comes back `blocked` | The system asks once. After a denial `micStatus()` itself reports `blocked` |
| Picker filter | Extensions and MIME types | Uniform type identifiers |
| Declaring the microphone | `RECORD_AUDIO` in the manifest | `NSMicrophoneUsageDescription` plus the Podfile flag |
| Google client ID | Read from `google-services.json` | `GIDClientID` in `Info.plist` |
| Going back | The system back button | A swipe from the left edge, which `MaterialPageRoute` already handles |

The three-state `Permissions` mapping covers both, so no code changes. But one
sentence in [onboarding.md](onboarding.md) is Android-only: "saying no is not a
dead end, tapping Record asks again". On iOS the prompt never returns, so
Record goes straight to the "Turn it on in Settings → Permissions" line, which
is what `Recording.begin()` already does.

## What to check on the device

- Sign in with Google, sign out, sign in again.
- A brand-new account gets the welcome; an existing one goes straight home.
- The microphone prompt shows your sentence.
- Deny it, then tap Record: the settings sentence appears. Settings →
  Permissions offers **Open settings**, and the row updates when you come back.
- Record five seconds, pause, resume, save. The note's length excludes the pause.
- Record under a second: nothing is saved.
- Throw away: the dialog says how much would be lost, and no note appears.
- The level meter moves while you talk and sits still while paused.
- Import an `.m4a`, then try a non-audio file and check the message.
- Background the app mid-recording, or take a call: Carry keeps what it has.
- **The record pill and the recording bar clear the home indicator.** This is
  the most likely visual bug — both sit at the bottom, and Android has no
  inset there.
- The profile photo loads, then still shows after a relaunch in airplane mode.

## Testing

The 151 Dart tests are platform-neutral and pass unchanged; none of them
touch a platform channel outside the helpers in `test/helpers/`.

Worth adding once you can run them: `pumpScreen` in `test/helpers/pump.dart`
sets no `MediaQuery` padding, so every screen is tested with zero safe-area
insets. Giving it an optional inset and running the bottom-anchored screens
with an iPhone's (`top: 59, bottom: 34`) is what would catch the home
indicator problem in CI rather than by eye.

## CI

The `ios` job builds `flutter build ios --no-codesign` on `macos-latest`,
which is free for public repositories. It runs on the same rule as the APK
build: only when `app/ios/` or `app/pubspec.*` changed.

It is also gated on `app/ios/` existing at all, because a job that builds a
platform folder the repo doesn't have would fail on every PR. Nothing to
switch on: the guard passes by itself once step 2 above is committed.

## Not covered yet

- **Background recording.** Recording with the app behind needs
  `UIBackgroundModes: audio` in `Info.plist`, the same gap Android has.
- **Notifications.** Needs APNs and a paid account, and waits for the server
  to push "your note is ready".
- **Release signing.** Free provisioning expires every 7 days. Distribution
  needs the paid Developer Program.
- **iPad.** The layouts are phone-sized; `responsive_test.dart` only pumps
  phone sizes.
- **The simulator.** It records through the Mac's microphone and never
  reproduces a phone call interrupting the audio session, so the recorder
  checks above need the real device.
