import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../analytics/analytics.dart';
import '../auth/auth.dart';
import '../permissions/permissions.dart';
import 'microphone_screen.dart';
import 'welcome_screen.dart';

/// Remembers whether an account has been welcomed on this device.
///
/// Stored per account, so signing in with a second account greets that person
/// too. The microphone step is not stored here: it's a property of the phone,
/// so it's read from the system instead.
abstract final class Onboarding {
  // Built per call, not cached: a cached handle keeps the storage it was
  // created with, which breaks tests that swap storage between cases.
  static SharedPreferencesAsync get _prefs => SharedPreferencesAsync();

  static String _key(String uid) => 'welcome_done_$uid';

  static Future<bool> isDone(String uid) async =>
      await _prefs.getBool(_key(uid)) ?? false;

  static Future<void> markDone(String uid) => _prefs.setBool(_key(uid), true);

  /// True only for an account signing in for the first time ever, which is
  /// what decides whether to welcome someone.
  ///
  /// The rule lives in [Auth] with the rest of what an account is; this is
  /// here so the onboarding code reads as onboarding.
  static bool isNewAccount(User user) => Auth.isNewAccount(user);
}

enum _Step { loading, welcome, microphone, home }

/// Runs a new account through the greeting, then the microphone screen if the
/// phone still needs it, then [home]. Returning accounts go straight to [home].
class OnboardingGate extends StatefulWidget {
  const OnboardingGate({super.key, required this.user, required this.home});

  final User user;
  final Widget home;

  @override
  State<OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends State<OnboardingGate> {
  _Step _step = _Step.loading;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(OnboardingGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.uid != widget.user.uid) {
      setState(() => _step = _Step.loading);
      _start();
    }
  }

  Future<void> _start() async {
    // Only a brand-new account is onboarded. An account that already exists
    // goes straight home, even on a fresh install — if the phone needs the
    // microphone, home's banner asks for it.
    final onboard =
        Onboarding.isNewAccount(widget.user) &&
        !await Onboarding.isDone(widget.user.uid);
    if (!mounted) return;
    Analytics.screen(onboard ? 'welcome' : 'home');
    setState(() => _step = onboard ? _Step.welcome : _Step.home);
  }

  /// After the greeting, only ask for the microphone if the phone hasn't
  /// granted it already — another account on this phone may have.
  Future<void> _afterWelcome() async {
    Analytics.event('welcome_continued');
    final mic = await Permissions.micStatus();
    if (!mounted) return;
    if (mic == MicPermission.granted) {
      // Another account on this phone already allowed it, so there is nothing
      // to ask.
      await _finish(askedForMic: false);
      return;
    }
    Analytics.screen('microphone');
    setState(() => _step = _Step.microphone);
  }

  /// Marked at the end, so an app closed mid-way starts the flow again.
  Future<void> _finish({bool askedForMic = true}) async {
    await Onboarding.markDone(widget.user.uid);
    Analytics.event('onboarding_finished', {'asked_for_mic': askedForMic});
    if (!mounted) return;
    Analytics.screen('home');
    setState(() => _step = _Step.home);
  }

  @override
  Widget build(BuildContext context) => switch (_step) {
    _Step.loading => const Scaffold(),
    _Step.welcome => WelcomeScreen(
      name: widget.user.displayName,
      onContinue: _afterWelcome,
    ),
    _Step.microphone => MicrophoneScreen(onDone: _finish),
    _Step.home => widget.home,
  };
}
