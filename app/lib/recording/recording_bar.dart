import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/toast.dart';
import 'recording.dart';

/// The black bar that sits at the bottom of the notes list while recording.
///
/// It stays on the notes screen on purpose: you can see your notes while a
/// recording runs, and the bar is the one place that says it's running.
/// It only draws and reports taps: [Recording] does the work.
class RecordingBar extends StatefulWidget {
  const RecordingBar({
    super.key,
    required this.onFinished,
    this.previewElapsed,
  });

  /// Called with a sentence when there was nothing worth keeping, and with
  /// null when a note was saved.
  final void Function(String? message) onFinished;

  /// Fills the bar in for `flutter widget-preview start`, where there is no
  /// microphone to run.
  final Duration? previewElapsed;

  @override
  State<RecordingBar> createState() => _RecordingBarState();
}

class _RecordingBarState extends State<RecordingBar> {
  Timer? _ticker;
  late final AppLifecycleListener _lifecycle;
  Duration _elapsed = Duration.zero;
  double _level = 0;
  bool _finishing = false;

  bool get _isPreview => widget.previewElapsed != null;

  @override
  void initState() {
    super.initState();
    if (_isPreview) {
      _elapsed = widget.previewElapsed!;
      _level = 0.55;
      return;
    }
    // Without a foreground service the phone can cut the microphone once
    // Carry is out of sight, so keep what there is rather than lose it.
    _lifecycle = AppLifecycleListener(onPause: _saveBeforeTheAppGoes);
    _startTicking();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    if (!_isPreview) {
      _lifecycle.dispose();
      // The bar is going away with nothing to replace it — the account
      // signed out, or the screen was torn down. A recording with no
      // controls must not keep the microphone or leave a file behind.
      if (Recording.inProgress) unawaited(Recording.abandon());
    }
    super.dispose();
  }

  Future<void> _saveBeforeTheAppGoes() async {
    if (Recording.inProgress && !_finishing) {
      await _save(stoppedBy: 'app_backgrounded');
    }
  }

  Future<void> _pauseOrResume() async {
    final problem = await Recording.pauseOrResume();
    if (!mounted) return;
    setState(() {});
    if (problem != null) _say(problem);
  }

  /// [andSay] is shown when the save worked but wasn't asked for, so the
  /// person isn't left wondering why the bar went away.
  Future<void> _save({String? andSay, String stoppedBy = 'user'}) async {
    if (_finishing) return; // a second tap must not save twice
    setState(() => _finishing = true);
    _ticker?.cancel();

    final result = await Recording.finish(stoppedBy: stoppedBy);
    if (!mounted) return;
    if (result.stillRecording) {
      // The phone wouldn't stop: put the controls back rather than leaving
      // a bar nobody can use.
      setState(() => _finishing = false);
      _startTicking();
      _say(result.message!);
      return;
    }
    widget.onFinished(result.message ?? andSay);
  }

  Future<void> _discard() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Throw this recording away?'),
        content: Text(
          'You have recorded ${clock(_elapsed)}. It cannot be got back.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep recording'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Throw away'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    _ticker?.cancel();
    await Recording.throwAway();
    if (mounted) widget.onFinished(null);
  }

  void _startTicking() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) async {
      final level = await Recording.level();
      if (!mounted) return;
      setState(() {
        _elapsed = Recording.elapsed;
        _level = level;
      });
      // Long enough. Keep what there is instead of letting it grow into
      // something that can't be uploaded.
      if (Recording.atLimit) {
        unawaited(
          _save(
            stoppedBy: 'length_limit',
            andSay:
                'That is as long as a recording can be, so '
                'Carry saved it.',
          ),
        );
      }
    });
  }

  void _say(String message) => showToast(context, message);

  /// mm:ss, and h:mm:ss once it runs past an hour.
  static String clock(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0
        ? '${d.inHours}:$minutes:$seconds'
        : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final paused = _isPreview ? false : Recording.isPaused;
    return Semantics(
      liveRegion: true,
      label: paused
          ? 'Recording paused at ${_elapsed.inSeconds} seconds'
          : 'Recording, ${_elapsed.inSeconds} seconds',
      child: Material(
        color: CarryColors.ink,
        borderRadius: BorderRadius.circular(26),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
          child: Row(
            children: [
              _Blinker(paused: paused),
              const SizedBox(width: 12),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    clock(_elapsed),
                    style: const TextStyle(
                      color: CarryColors.ground,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: CustomPaint(
                    painter: _LevelPainter(level: paused ? 0 : _level),
                    size: Size.infinite,
                  ),
                ),
              ),
              _BarButton(
                icon: paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                label: paused ? 'Resume recording' : 'Pause recording',
                onPressed: _finishing ? null : _pauseOrResume,
              ),
              _BarButton(
                icon: Icons.delete_outline_rounded,
                label: 'Throw recording away',
                onPressed: _finishing ? null : _discard,
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _finishing ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: CarryColors.ground,
                  foregroundColor: CarryColors.ink,
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon),
      iconSize: 28,
      color: CarryColors.ground,
      tooltip: label,
      // Still a 44px target, without the default padding around it.
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
    );
  }
}

/// The red dot every recorder has. It stops moving when you pause, which is
/// the clearest way to show the difference at a glance.
class _Blinker extends StatefulWidget {
  const _Blinker({required this.paused});

  final bool paused;

  @override
  State<_Blinker> createState() => _BlinkerState();
}

class _BlinkerState extends State<_Blinker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = widget.paused || MediaQuery.disableAnimationsOf(context);
    return FadeTransition(
      opacity: still
          ? const AlwaysStoppedAnimation(0.4)
          : Tween<double>(begin: 1, end: 0.35).animate(_pulse),
      child: Container(
        width: 14,
        height: 14,
        decoration: const BoxDecoration(
          color: Color(0xFFE5484D),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

/// A small level meter, so it's obvious the microphone is hearing something.
class _LevelPainter extends CustomPainter {
  const _LevelPainter({required this.level});

  final double level;

  static const _bars = 14;

  @override
  void paint(Canvas canvas, Size size) {
    final slot = size.width / _bars;
    for (var i = 0; i < _bars; i++) {
      // A fixed pattern scaled by loudness: readable, and cheap to paint.
      final shape = 0.35 + 0.65 * ((i * 7) % 5) / 4;
      final height = (4 + size.height * level * shape).clamp(4.0, size.height);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(slot * i + slot / 2, size.height / 2),
            width: slot * 0.4,
            height: height,
          ),
          Radius.circular(slot * 0.2),
        ),
        Paint()..color = CarryColors.ground.withValues(alpha: 0.55),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LevelPainter old) => old.level != level;
}
