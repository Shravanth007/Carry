import 'dart:async';

import 'package:flutter/material.dart';

import '../notes/notes.dart';
import '../theme.dart';
import 'recorder.dart';

/// The black bar that sits at the bottom of the notes list while recording.
///
/// It stays on the notes screen on purpose: you can see your notes while a
/// recording runs, and the bar is the one place that says it's running.
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
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) async {
      final level = Recorder.isPaused
          ? 0.0
          : await Recorder.level().catchError((_) => 0.0);
      if (!mounted) return;
      setState(() {
        _elapsed = Recorder.elapsed;
        _level = level;
      });
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _pauseOrResume() async {
    if (Recorder.isPaused) {
      await Recorder.resume();
    } else {
      await Recorder.pause();
    }
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    if (_finishing) return; // a second tap must not save twice
    setState(() => _finishing = true);
    _ticker?.cancel();
    final finished = await Recorder.stop();
    if (!mounted) return;
    if (finished == null) {
      widget.onFinished('Too short to save. Hold on a little longer.');
      return;
    }
    Notes.addRecorded(
      path: finished.path,
      duration: finished.duration,
      bytes: finished.bytes,
    );
    widget.onFinished(null);
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
    await Recorder.discard();
    if (mounted) widget.onFinished(null);
  }

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
    final paused = _isPreview ? false : Recorder.isPaused;
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
