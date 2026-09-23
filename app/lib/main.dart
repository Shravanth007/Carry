import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'analytics/analytics.dart';
import 'auth/auth.dart';
import 'firebase_options.dart';
import 'home/home_screen.dart';
import 'onboarding/onboarding.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await Auth.init();
  // Before the first frame so the first screen someone sees is counted. It
  // does nothing at all unless the build carried a POSTHOG_KEY.
  await Analytics.init();
  final alreadySignedIn = Auth.currentUser;
  if (alreadySignedIn != null) Analytics.identify(alreadySignedIn.uid);
  runApp(const CarryApp());
}

class CarryApp extends StatelessWidget {
  const CarryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Carry',
      debugShowCheckedModeBanner: false,
      theme: carryTheme,
      home: AuthGate(
        signedIn: (user) => OnboardingGate(
          user: user,
          home: HomeScreen(
            name: user.displayName,
            email: user.email ?? '',
            photoUrl: user.photoURL,
          ),
        ),
      ),
    );
  }
}
