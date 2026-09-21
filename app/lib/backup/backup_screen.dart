import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../settings/widgets.dart';
import '../theme.dart';
import 'backup.dart';

@Preview(name: 'Backup', size: Size(412, 915), wrapper: previewApp)
Widget backupPreview() => const BackupScreen();

/// Where recordings are kept besides the phone. Off until asked for.
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool? _on;
  DateTime? _since;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final on = await Backup.isOn();
    final since = await Backup.onSince();
    if (mounted) {
      setState(() {
        _on = on;
        _since = since;
      });
    }
  }

  /// One answer at a time. Writing the choice and reading it back takes a
  /// moment, and two taps racing through that can finish in the wrong order
  /// and leave backup on after the person turned it off.
  Future<void> _toggle(bool on) async {
    if (_saving) return;
    setState(() {
      _on = on;
      _saving = true;
    });
    try {
      await Backup.setOn(on);
    } finally {
      // What's stored wins, even if the write failed: the switch must never
      // sit there showing an answer nothing was saved for.
      await _load();
      if (mounted) setState(() => _saving = false);
    }
  }

  static String _date(DateTime when) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${when.day} ${months[when.month - 1]} ${when.year}';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final on = _on;
    final since = _since;
    return Scaffold(
      appBar: AppBar(title: const Text('Backup')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const SectionLabel('Where recordings are kept'),
          SettingsCard(
            child: SettingsRow(
              title: 'Carry cloud',
              subtitle: switch (on) {
                null => 'Checking…',
                true => 'New recordings are uploaded.',
                false => 'Recordings stay on this phone.',
              },
              trailing: Switch(
                value: on ?? false,
                onChanged: on == null || _saving ? null : _toggle,
                activeThumbColor: CarryColors.ground,
                activeTrackColor: CarryColors.ink,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              on == true && since != null
                  ? 'On since ${_date(since)}. Recordings made before that '
                        'stay on this phone: turning backup on does not reach '
                        'back over what you already recorded.'
                  : 'Turn this on and new recordings are copied to Carry '
                        'cloud, so you still have them if you lose your phone. '
                        'Anything already recorded stays here.',
              style: text.bodySmall?.copyWith(color: CarryColors.muted),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Uploaded recordings are only stored so you can get them back. '
              'They are not used for anything else.',
              style: text.bodySmall?.copyWith(color: CarryColors.muted),
            ),
          ),
          const SizedBox(height: 28),
          const SectionLabel('Somewhere else'),
          const SettingsCard(
            child: SettingsRow(
              title: 'Google Drive',
              subtitle: 'Keep recordings in your own Drive',
              trailing: SoonBadge(),
              titleColor: CarryColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}
