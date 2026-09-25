import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../theme.dart';
import '../widgets/scrollable_column.dart';
import 'auth.dart';

@Preview(name: 'Sign in', size: Size(412, 915), wrapper: previewApp)
Widget signInPreview() => const SignInScreen();

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // On success the auth stream in main.dart swaps this screen out.
      await Auth.signInWithGoogle();
    } catch (e) {
      debugPrint('Google sign-in failed: $e');
      _error = Auth.messageFor(e);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final error = _error;
    return Scaffold(
      body: SafeArea(
        child: ScrollableColumn(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      'Carry',
                      style: text.displayMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1.5,
                        height: 1,
                        color: CarryColors.ink,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const SizedBox(
                    height: 120,
                    width: double.infinity,
                    child: CustomPaint(painter: _WaveformPainter()),
                  ),
                ],
              ),
            ),
            Text(
              'Speak a thought.\nKeep it as a note.',
              style: text.headlineMedium?.copyWith(
                fontWeight: FontWeight.w600,
                height: 1.2,
                letterSpacing: -0.5,
                color: CarryColors.ink,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Record voice notes and Carry writes them down for you.',
              style: text.bodyLarge?.copyWith(color: CarryColors.muted),
            ),
            const SizedBox(height: 40),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    error,
                    style: text.bodyMedium?.copyWith(color: CarryColors.error),
                  ),
                ),
              ),
            _GoogleButton(busy: _busy, onPressed: _signIn),
            const SizedBox(height: 16),
            Text(
              'Carry only uses your Google account to sign you in.',
              style: text.bodySmall?.copyWith(color: CarryColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

/// Light "Continue with Google" button per Google's branding guidelines.
class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.busy, required this.onPressed});

  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: OutlinedButton(
        onPressed: busy ? null : onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF1F1F1F),
          side: const BorderSide(color: Color(0xFF747775)),
          shape: const StadiumBorder(),
          // From the theme's type, so the label is the same face as the
          // rest of the screen wherever the default font isn't Roboto.
          textStyle: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontSize: 16),
        ),
        child: busy
            ? const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  semanticsLabel: 'Signing in',
                ),
              )
            : const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    dimension: 20,
                    child: CustomPaint(painter: _GoogleLogoPainter()),
                  ),
                  SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      'Continue with Google',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ponytail: painted "G" instead of an SVG asset + flutter_svg dependency.
class _GoogleLogoPainter extends CustomPainter {
  const _GoogleLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final stroke = s * 0.2;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, s - stroke, s - stroke);
    double rad(double deg) => deg * pi / 180;
    void arc(Color color, double start, double sweep) => canvas.drawArc(
      rect,
      rad(start),
      rad(sweep),
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );

    arc(const Color(0xFF4285F4), 0, 45);
    arc(const Color(0xFF34A853), 45, 105);
    arc(const Color(0xFFFBBC05), 150, 60);
    arc(const Color(0xFFEA4335), 210, 105);
    canvas.drawRect(
      Rect.fromLTWH(s / 2, s / 2 - stroke / 2, s / 2, stroke),
      Paint()..color = const Color(0xFF4285F4),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// A voice waveform: the recorded part in ink, the rest still to come.
class _WaveformPainter extends CustomPainter {
  const _WaveformPainter();

  static const _bars = 36;
  static const _recorded = 22;

  @override
  void paint(Canvas canvas, Size size) {
    final slot = size.width / _bars;
    final barWidth = slot * 0.55;
    for (var i = 0; i < _bars; i++) {
      final level = 0.2 + 0.8 * (sin(i * 0.9) * cos(i * 0.37)).abs();
      final height = size.height * level;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(slot * i + slot / 2, size.height / 2),
            width: barWidth,
            height: height,
          ),
          Radius.circular(barWidth / 2),
        ),
        Paint()
          ..color = i < _recorded
              ? CarryColors.ink
              : CarryColors.ink.withValues(alpha: 0.15),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
