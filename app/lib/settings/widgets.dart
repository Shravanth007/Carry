import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme.dart';
import 'avatar_cache.dart';

/// Small heading above a group of settings.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall
            ?.copyWith(color: CarryColors.muted),
      ),
    );
  }
}

/// A light panel on the cream background, holding one group of settings.
class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Material, so a row's tap ripple paints inside the card.
    return Material(
      color: CarryColors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: CarryColors.ink.withValues(alpha: 0.08)),
      ),
      child: child,
    );
  }
}

/// One row inside a [SettingsCard].
///
// ponytail: built from a Row rather than ListTile, which paints its own
// background and swallowed these rows on the cream theme.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.titleColor = CarryColors.ink,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color titleColor;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final subtitleText = subtitle;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: text.titleMedium?.copyWith(
                      color: titleColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitleText != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitleText,
                      style: text.bodyMedium?.copyWith(
                        color: CarryColors.muted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 12), trailing!],
          ],
        ),
      ),
    );
  }
}

/// The Google account picture, or the first letter when there isn't one.
class Avatar extends StatelessWidget {
  const Avatar({
    super.key,
    required this.photoUrl,
    required this.name,
    required this.email,
    this.size = 48,
  });

  final String? photoUrl;
  final String? name;
  final String email;
  final double size;

  String get _initial {
    final source = (name?.trim().isNotEmpty ?? false) ? name!.trim() : email;
    return source.isEmpty ? '?' : source[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final url = photoUrl;
    final fallback = _Initial(letter: _initial, size: size);
    return ClipOval(
      child: SizedBox.square(
        dimension: size,
        child: url == null
            ? fallback
            : FutureBuilder<Uint8List?>(
                // Saved on the phone after the first load, so it shows
                // straight away next time and works offline.
                future: AvatarCache.load(url),
                builder: (context, snapshot) {
                  final bytes = snapshot.data;
                  if (bytes == null) return fallback;
                  return Image.memory(bytes, fit: BoxFit.cover);
                },
              ),
      ),
    );
  }
}

class _Initial extends StatelessWidget {
  const _Initial({required this.letter, required this.size});

  final String letter;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: CarryColors.ink,
      child: Center(
        child: Text(
          letter,
          style: TextStyle(
            color: CarryColors.ground,
            fontSize: size * 0.4,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
