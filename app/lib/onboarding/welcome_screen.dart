import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../theme.dart';
import '../widgets/scrollable_column.dart';

@Preview(name: 'Welcome', size: Size(412, 915), wrapper: previewApp)
Widget welcomePreview() =>
    WelcomeScreen(name: 'Ada Lovelace', onContinue: () {});

/// Greeting for an account that hasn't been seen on this phone before.
/// Says nothing about permissions: that's the next screen, and only when
/// the phone actually needs it.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({
    super.key,
    required this.name,
    required this.onContinue,
  });

  /// The account's display name, if Google gave us one.
  final String? name;
  final VoidCallback onContinue;

  String get _greeting {
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty) return 'Welcome to Carry';
    return 'Welcome, ${trimmed.split(' ').first}';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: ScrollableColumn(
          padding: const EdgeInsets.all(24),
          children: [
            const Spacer(),
            Semantics(
              header: true,
              child: Text(
                _greeting,
                style: text.headlineLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.8,
                  height: 1.1,
                  color: CarryColors.ink,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Say what you want to remember. Carry writes it down for you '
              'and keeps it here.',
              style: text.bodyLarge?.copyWith(color: CarryColors.muted),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 64,
              child: FilledButton(
                onPressed: onContinue,
                style: carryButton,
                child: const Text('Get started'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
