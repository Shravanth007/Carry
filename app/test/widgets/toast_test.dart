import 'package:carry/widgets/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump.dart';

/// A screen with a button that toasts, which is how every real caller uses it.
Widget _screenSaying(List<String> messages) => Builder(
  builder: (context) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final message in messages)
            TextButton(
              onPressed: () => showToast(context, message),
              child: Text('say $message'),
            ),
        ],
      ),
    ),
  ),
);

void main() {
  testWidgets('says what it was given', (tester) async {
    await pumpScreen(tester, _screenSaying(const ['Saved']));

    await tester.tap(find.text('say Saved'));
    await tester.pump();

    expect(find.text('Saved'), findsOneWidget);
  });

  testWidgets('the newest news replaces the last, rather than queueing', (
    tester,
  ) async {
    await pumpScreen(tester, _screenSaying(const ['First', 'Second']));

    await tester.tap(find.text('say First'));
    await tester.pump();
    await tester.tap(find.text('say Second'));
    await tester.pump();

    // Queued, the second would wait four seconds for the first to time out,
    // and the news worth reading would arrive last.
    expect(find.text('Second'), findsOneWidget);
    expect(find.text('First'), findsNothing);
  });

  testWidgets('a long message stays up longer than a short one', (
    tester,
  ) async {
    const long =
        "Couldn't open settings. Go to Settings → Apps → Carry → Permissions.";
    await pumpScreen(tester, _screenSaying(const [long]));

    await tester.tap(find.text('say $long'));
    await tester.pump();
    // Where a four-second toast would already be gone.
    await tester.pump(const Duration(seconds: 5));

    expect(find.text(long), findsOneWidget);
  });
}
