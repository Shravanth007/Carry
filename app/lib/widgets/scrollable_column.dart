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
  });

  final List<Widget> children;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final room = constraints.maxHeight - padding.vertical;
        return SingleChildScrollView(
          padding: padding,
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
