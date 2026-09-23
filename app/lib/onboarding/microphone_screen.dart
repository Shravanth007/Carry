import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../permissions/permissions.dart';
import '../theme.dart';
import '../widgets/scrollable_column.dart';

@Preview(name: 'Microphone', size: Size(412, 915), wrapper: previewApp)
Widget microphonePreview() => MicrophoneScreen(onDone: () {});

/// Asks for the microphone with the reason, instead of prompting cold on the
/// record button. Only shown when the phone hasn't granted it already.
class MicrophoneScreen extends StatefulWidget {
  const MicrophoneScreen({super.key, required this.onDone});

  /// Called when the user is finished here, whatever they chose.
  final VoidCallback onDone;

  @override
  State<MicrophoneScreen> createState() => _MicrophoneScreenState();
}

class _MicrophoneScreenState extends State<MicrophoneScreen> {
  bool _busy = false;
  bool _blocked = false;

  Future<void> _allow() async {
    setState(() => _busy = true);
    final mic = await Permissions.requestMic(where: 'onboarding');
    if (!mounted) return;
    setState(() {
      _busy = false;
      // The system won't ask again, so point at Settings instead of retrying.
      _blocked = mic == MicPermission.blocked;
    });
    if (!_blocked) widget.onDone();
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
                'Carry needs your microphone',
                style: text.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  height: 1.15,
                  color: CarryColors.ink,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Recording is how a note gets made. Nothing is recorded until '
              'you press record.',
              style: text.bodyLarge?.copyWith(color: CarryColors.muted),
            ),
            const Spacer(),
            if (_blocked) ...[
              Text(
                'Microphone access is turned off for Carry. Turn it on in '
                'Settings to record.',
                style: text.bodyMedium?.copyWith(color: CarryColors.error),
              ),
              const SizedBox(height: 16),
            ],
            SizedBox(
              width: double.infinity,
              height: 64,
              child: FilledButton(
                onPressed: _busy
                    ? null
                    : _blocked
                    ? () => Permissions.openSettings(where: 'onboarding')
                    : _allow,
                style: carryButton,
                child: _busy
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : Text(_blocked ? 'Open settings' : 'Allow microphone'),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: _busy ? null : widget.onDone,
                style: TextButton.styleFrom(foregroundColor: CarryColors.muted),
                child: Text(_blocked ? 'Continue' : 'Not now'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
