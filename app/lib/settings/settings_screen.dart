import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../session.dart';
import '../theme.dart';
import 'permissions_screen.dart';
import 'widgets.dart';

@Preview(name: 'Settings', size: Size(412, 915), wrapper: previewApp)
Widget settingsPreview() =>
    const SettingsScreen(name: 'Ada Lovelace', email: 'ada@gmail.com');

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.name,
    required this.email,
    this.photoUrl,
  });

  final String? name;
  final String email;

  /// The Google account picture. Falls back to an initial when missing or
  /// when the phone is offline.
  final String? photoUrl;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _signingOut = false;

  Future<void> _signOut() async {
    setState(() => _signingOut = true);
    try {
      await signOutAndForget();
    } catch (e) {
      debugPrint('Sign-out failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't sign out. Try again.")),
        );
      }
    }
    // On success this screen normally goes away with the signed-in app. If
    // it's somehow still here, put the row back rather than spinning forever.
    if (mounted) setState(() => _signingOut = false);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const SectionLabel('Account'),
          SettingsCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Avatar(
                    photoUrl: widget.photoUrl,
                    name: widget.name,
                    email: widget.email,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.name ?? 'Signed in',
                          style: text.titleMedium?.copyWith(
                            color: CarryColors.ink,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.email,
                          style: text.bodyMedium?.copyWith(
                            color: CarryColors.muted,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const SectionLabel('App'),
          SettingsCard(
            child: Column(
              children: [
                SettingsRow(
                  title: 'Permissions',
                  subtitle: 'Microphone',
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: CarryColors.muted,
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const PermissionsScreen(),
                    ),
                  ),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                // Not built yet: shown so it's clearly on the way.
                const SettingsRow(
                  title: 'MCP',
                  subtitle: 'Let your AI tools read your notes',
                  trailing: _SoonBadge(),
                  titleColor: CarryColors.muted,
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          SettingsCard(
            child: SettingsRow(
              title: 'Sign out',
              titleColor: CarryColors.error,
              // Signing out of Google can take a moment: show that it started.
              trailing: _signingOut
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        semanticsLabel: 'Signing out',
                      ),
                    )
                  : null,
              onTap: _signingOut ? null : _signOut,
            ),
          ),
        ],
      ),
    );
  }
}

class _SoonBadge extends StatelessWidget {
  const _SoonBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: CarryColors.ink.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'Soon',
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: CarryColors.muted),
      ),
    );
  }
}
