import 'package:flutter/material.dart';

/// A full-height column that scrolls instead of overflowing.
///
/// On a roomy phone it behaves like a normal `Column`, so `Spacer`s push
/// content apart as usual. On a short phone, or when the system text size is
/// large, the spacers collapse first and then the screen scrolls.
class ScrollableColumn extends StatelessWidget {
  const ScrollableColumn({
    super.key,
    required this.children,
    this.padding = EdgeInsets.zero,
    this.alwaysScrollable = false,
  });

  final List<Widget> children;
  final EdgeInsets padding;

  /// Lets a drag start even when everything already fits.
  ///
  /// A `RefreshIndicator` needs a scroll to attach to: with nothing
  /// overflowing there is no scroll extent, so the gesture never begins and a
  /// screen that says "pull down to try again" is telling people to do
  /// something that cannot work.
  final bool alwaysScrollable;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final room = constraints.maxHeight - padding.vertical;
        return SingleChildScrollView(
          padding: padding,
          physics: alwaysScrollable
              ? const AlwaysScrollableScrollPhysics()
              : null,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: room < 0 ? 0 : room),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
          ),
        );
      },
    );
  }
}
