import 'package:flutter/material.dart';

/// The one way Carry says something in passing.
///
/// A toast confirms what just happened, or reports something the person can
/// do nothing about right now. **A problem that needs a decision does not go
/// here**: it stays on the screen, next to the thing it is about, where it can
/// be read twice and acted on. A message that disappears after four seconds is
/// no use to somebody who was looking at their phone, not at Carry.
///
/// The words follow the button that caused them. "Restore a purchase" produces
/// "Purchase restored" — same verb, so the interface reads as one voice.
void showToast(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.of(context);
  // One at a time. Without this a second toast waits for the first to time
  // out, so the newest news - the one worth reading - arrives last and looks
  // like a delay.
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      // Long enough to read the long ones. Four seconds is comfortable for a
      // confirmation and short for a sentence explaining where to tap next.
      duration: Duration(seconds: message.length > 60 ? 6 : 4),
    ),
  );
}
