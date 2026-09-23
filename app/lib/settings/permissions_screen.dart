import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../permissions/permissions.dart';
import '../theme.dart';
import 'widgets.dart';

@Preview(name: 'Permissions', size: Size(412, 915), wrapper: previewApp)
Widget permissionsSettingsPreview() => const PermissionsScreen();

/// What Carry is allowed to use on this phone. Microphone today,
/// notifications when the server starts pushing.
class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  MicPermission? _mic;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Re-check on resume: the user may have changed it in phone settings.
    _lifecycle = AppLifecycleListener(onResume: _checkMic);
    _checkMic();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _checkMic() async {
    final mic = await Permissions.micStatus();
    if (mounted) setState(() => _mic = mic);
  }

  Future<void> _toggleMic(bool wantOn) async {
    // Turning it on is the only change the app itself can make, and only
    // while the system will still show a prompt.
    if (wantOn && _mic == MicPermission.denied) {
      final mic = await Permissions.requestMic(where: 'settings');
      if (mounted) setState(() => _mic = mic);
      if (mic != MicPermission.blocked) return;
      // Android only reports "never ask again" from a request, so this is the
      // first moment we know no prompt appeared.
    }
    await _sendToPhoneSettings(turningOn: wantOn);
  }

  /// Everything else lives in the phone's settings, so explain that and offer
  /// to go there, rather than letting the switch flick back with no reason.
  Future<void> _sendToPhoneSettings({required bool turningOn}) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          turningOn ? 'Allow the microphone' : 'Turn off the microphone',
        ),
        content: Text(
          turningOn
              ? "Your phone won't ask again, so the microphone has to be "
                    'allowed in phone settings.'
              : 'Your phone keeps app permissions, so Carry cannot turn this '
                    'off itself. You can turn it off in phone settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Open settings'),
          ),
        ],
      ),
    );
    if (go != true) return;

    final opened = await Permissions.openSettings(where: 'settings');
    if (opened || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          "Couldn't open settings. Go to Settings → Apps → Carry → Permissions.",
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final mic = _mic;
    return Scaffold(
      appBar: AppBar(title: const Text('Permissions')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const SectionLabel('Recording'),
          SettingsCard(
            child: SettingsRow(
              title: 'Microphone',
              subtitle: switch (mic) {
                null => 'Checking…',
                MicPermission.granted => 'Carry can record.',
                MicPermission.denied => 'Needed to record notes.',
                MicPermission.blocked => 'Turn it on in phone settings.',
              },
              trailing: Switch(
                value: mic == MicPermission.granted,
                onChanged: mic == null ? null : _toggleMic,
                activeThumbColor: CarryColors.ground,
                activeTrackColor: CarryColors.ink,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Carry records only while you hold the record button. '
              'Your phone keeps permissions, so turning one off happens there.',
              style: text.bodySmall?.copyWith(color: CarryColors.muted),
            ),
          ),
        ],
      ),
    );
  }
}
