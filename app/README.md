# Carry — the app

The Flutter half of Carry. What the project is and what it does:
[../README.md](../README.md). How to work on it, and the rules it follows:
[CLAUDE.md](CLAUDE.md).

```
flutter run                      # r = hot reload, R = hot restart
flutter test
flutter analyze
flutter widget-preview start     # every screen in Chrome, no Firebase needed
```

One codebase for Android and iOS. Android is what has been run on a device so
far; [docs/ios.md](docs/ios.md) is the runbook for standing the iOS build up
next to it.

Each feature has a doc in [docs/](docs/): sign-in, onboarding, notes,
analytics, payments and iOS.
