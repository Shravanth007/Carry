import 'package:carry/home/home_screen.dart';
import 'package:carry/notes/notes.dart';
import 'package:carry/permissions/permissions.dart';
import 'package:carry/settings/settings_screen.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';

import 'package:carry/recording/recorder.dart';
import 'package:carry/recording/recording_bar.dart';

import '../helpers/pump.dart';
import '../helpers/test_auth.dart';
import '../helpers/test_device.dart';
import '../helpers/test_files.dart';
import '../helpers/test_recorder.dart';

void main() {
  late TestFilePicker picker;

  setUp(() async {
    await setUpTestAuth(signedIn: true);
    setUpTestPermissions(status: MicPermission.granted);
    setUpTestPrefs();
    setUpTestAvatarDownloads();
    picker = setUpTestFilePicker();
    Notes.clear();
  });

  Future<void> pumpHome(WidgetTester tester) async {
    await pumpScreen(
      tester,
      const HomeScreen(name: 'Ada Lovelace', email: testEmail),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapImport(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Import audio'));
    await tester.pumpAndSettle();
  }

  testWidgets('is titled Notes and shows only notes', (tester) async {
    await pumpHome(tester);

    expect(find.text('Notes'), findsOneWidget);
    expect(find.text('No notes yet'), findsOneWidget);
    expect(find.textContaining(testEmail), findsNothing);
    expect(find.text('Sign out'), findsNothing);
  });

  testWidgets('lists imported notes, newest first', (tester) async {
    await pumpHome(tester);

    picker.pick = testFile('Monday call.m4a');
    await tapImport(tester);
    picker.pick = testFile('Tuesday call.m4a');
    await tapImport(tester);

    expect(find.text('No notes yet'), findsNothing);
    final titles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((tile) => (tile.title! as Text).data);
    expect(titles, ['Tuesday call', 'Monday call']);
  });

  testWidgets('says why an import was refused', (tester) async {
    await pumpHome(tester);
    picker.pick = testFile('budget.pdf');

    await tapImport(tester);

    expect(
      find.text("That isn't an audio file. Pick a recording."),
      findsOneWidget,
    );
    expect(find.text('No notes yet'), findsOneWidget);
  });

  testWidgets('cancelling the picker changes nothing', (tester) async {
    await pumpHome(tester);
    picker.pick = null;

    await tapImport(tester);

    expect(picker.opens, 1);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('No notes yet'), findsOneWidget);
  });

  group('record button', () {
    Future<void> tapRecord(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Record'));
      // Not pumpAndSettle: the bar's level meter ticks forever by design.
      // A second covers the Scaffold's own animation as the button leaves.
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('is the main action on the screen', (tester) async {
      await pumpHome(tester);

      expect(find.byTooltip('Record'), findsOneWidget);
    });

    testWidgets('asks for the microphone when it is off', (tester) async {
      final permissions = setUpTestPermissions();
      await pumpHome(tester);

      await tapRecord(tester);

      expect(permissions.prompts, 1);
    });

    testWidgets('says what to do when the microphone stays off', (
      tester,
    ) async {
      setUpTestPermissions(status: MicPermission.blocked).answer =
          PermissionStatus.permanentlyDenied;
      await pumpHome(tester);

      await tapRecord(tester);

      expect(
        find.textContaining("Carry can't record without the microphone"),
        findsOneWidget,
      );
    });

    testWidgets('grows under a cursor and dips when pressed', (tester) async {
      await pumpHome(tester);
      double scale() => tester
          .widget<AnimatedScale>(
            find.ancestor(
              of: find.byType(FloatingActionButton),
              matching: find.byType(AnimatedScale),
            ),
          )
          .scale;
      expect(scale(), 1.0);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.byTooltip('Record')));
      await tester.pumpAndSettle();

      expect(scale(), greaterThan(1.0), reason: 'grows under the cursor');

      await tester.press(find.byTooltip('Record'));
      await tester.pump();

      expect(scale(), lessThan(1.0), reason: 'dips while held');
    });

    testWidgets('starts recording and shows the bar, without leaving', (
      tester,
    ) async {
      setUpTestRecorder();
      Recorder.clockForTesting = () => tester.binding.clock.now();
      await pumpHome(tester);

      await tapRecord(tester);

      expect(Recorder.isRecording, isTrue);
      expect(find.byType(RecordingBar), findsOneWidget);
      expect(find.text('Notes'), findsOneWidget, reason: 'still on the list');
      // The Scaffold animates the old button out, so check what we set
      // rather than what is still on screen mid-animation.
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(
        scaffold.floatingActionButton,
        isNull,
        reason: 'the bar has the controls now',
      );
    });

    testWidgets('a saved recording lands on the list', (tester) async {
      setUpTestRecorder();
      Recorder.clockForTesting = () => tester.binding.clock.now();
      await pumpHome(tester);
      await tapRecord(tester);
      await tester.pump(const Duration(seconds: 4));

      await tester.tap(find.text('Save'));
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(RecordingBar), findsNothing);
      expect(
        find.byTooltip('Record'),
        findsOneWidget,
        reason: 'button is back',
      );
      expect(Notes.all.value, hasLength(1));
      expect(find.text('No notes yet'), findsNothing);
    });
  });

  testWidgets('opens settings from the app bar', (tester) async {
    await pumpHome(tester);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.text('Ada Lovelace'), findsOneWidget);
  });
}
