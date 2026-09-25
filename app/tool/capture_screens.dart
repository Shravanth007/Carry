// Writes the README's picture of the app: a PNG per screen in build/screens/,
// and the frame sequence the GIF is made from in build/frames/.
//
//   flutter test tool/capture_screens.dart
//   ffmpeg -y -framerate 2 -i build/frames/%02d.png \
//     -vf "scale=300:-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=64[p];[s1][p]paletteuse" \
//     -loop 0 ../docs/carry.gif
//
// These are the real screens, built by the real widgets — the same builders
// the widget previews use, so a screen that changes shape here has changed
// shape in the app. It is not a recording of a phone: nothing is tapped and
// nothing animates. When there is a device to record, a real screen capture
// belongs in the README instead of this.
//
// Lives in tool/ rather than test/ so `flutter test` and CI never run it: it
// writes files and needs fonts from the Flutter SDK, neither of which belongs
// in a test suite.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:carry/auth/sign_in_screen.dart';
import 'package:carry/api/api.dart';
import 'package:carry/billing/plan_screen.dart';
import 'package:carry/home/home_screen.dart';
import 'package:carry/notes/notes.dart';
import 'package:carry/onboarding/welcome_screen.dart';
import 'package:carry/recording/recording_bar.dart';
import 'package:carry/settings/settings_screen.dart';
import 'package:carry/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A mid-range Android phone, the same size the previews use.
const _phone = Size(412, 915);

final _out = Directory('build/screens');
final _frames = Directory('build/frames');

/// The screens in order, and how long each one holds: one entry per frame at
/// ffmpeg's 2 fps. The two recording frames alternate so the timer ticks
/// rather than sitting still.
const _sequence = [
  ...['1-sign-in', '1-sign-in', '1-sign-in', '1-sign-in'],
  ...['2-welcome', '2-welcome', '2-welcome', '2-welcome'],
  ...['3-recording', '4-recording', '3-recording', '4-recording'],
  ...['5-notes', '5-notes', '5-notes', '5-notes'],
  ...['6-plan', '6-plan', '6-plan', '6-plan', '6-plan'],
  ...['7-settings', '7-settings', '7-settings', '7-settings'],
];

void main() {
  setUpAll(() async {
    for (final dir in [_out, _frames]) {
      dir.createSync(recursive: true);
      for (final file in dir.listSync()) {
        file.deleteSync();
      }
    }
    await _loadFonts();
  });

  testWidgets('capture', (tester) async {
    await _shot(tester, '1-sign-in', const SignInScreen());
    await _shot(
      tester,
      '2-welcome',
      WelcomeScreen(name: 'Ada Lovelace', onContinue: () {}),
    );

    // The bar sits over the list it was started from, which is what somebody
    // actually sees. Two frames a second apart, so there is a moment of
    // motion in it rather than five stills.
    for (final (frame, elapsed) in const [(3, 46), (4, 47)]) {
      Notes.all.value = _someNotes().skip(1).toList();
      await _shot(
        tester,
        '$frame-recording',
        Scaffold(
          appBar: AppBar(title: const Text('Notes')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
            children: [
              for (final note in Notes.all.value)
                ListTile(
                  title: Text(note.title),
                  subtitle: const Text('Not transcribed yet'),
                ),
            ],
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
              child: RecordingBar(
                onFinished: (_) {},
                previewElapsed: Duration(seconds: elapsed),
              ),
            ),
          ),
        ),
        settle: false,
      );
    }

    Notes.all.value = _someNotes();
    await _shot(
      tester,
      '5-notes',
      const HomeScreen(name: 'Ada Lovelace', email: 'ada@gmail.com'),
    );

    await _shot(tester, '6-plan', PlanScreen(previewUser: _freeAccount));
    await _shot(
      tester,
      '7-settings',
      const SettingsScreen(name: 'Ada Lovelace', email: 'ada@gmail.com'),
    );

    Notes.all.value = const [];
    _writeSequence();
  });
}

/// Copies the screens into build/frames/ as 01.png, 02.png ... so one ffmpeg
/// command makes the GIF. Repeats are how long a screen stays up: ffmpeg
/// holds one frame rate for the whole run, so dwell time is a copy count.
void _writeSequence() {
  var frame = 1;
  for (final name in _sequence) {
    final png = File('${_out.path}/$name.png');
    if (!png.existsSync()) {
      throw StateError('$name is in the sequence but was never captured.');
    }
    png.copySync('${_frames.path}/${frame.toString().padLeft(2, '0')}.png');
    frame++;
  }
}

/// Renders one screen at phone size and writes it as a PNG.
Future<void> _shot(
  WidgetTester tester,
  String name,
  Widget screen, {
  bool settle = true,
}) async {
  await tester.binding.setSurfaceSize(_phone);
  final key = GlobalKey();
  await tester.pumpWidget(RepaintBoundary(key: key, child: previewApp(screen)));
  // The recording bar pulses for as long as it is on screen, so there is no
  // settled state to wait for: pump a couple of frames and take it as it is.
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 120));
  }

  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  late Uint8List png;
  // Encoding is real async work, which a widget test's fake clock would
  // otherwise never let finish.
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    png = data!.buffer.asUint8List();
    image.dispose();
  });
  File('${_out.path}/$name.png').writeAsBytesSync(png);
}

/// Real glyphs instead of the test font's boxes. Roboto and the Material
/// icons both ship inside the Flutter SDK, so there is nothing to download.
Future<void> _loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) {
    throw StateError('Run this with `flutter test`, which sets FLUTTER_ROOT.');
  }
  final fonts = Directory('$root/bin/cache/artifacts/material_fonts');

  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final file in files) {
      loader.addFont(
        File('${fonts.path}/$file').readAsBytes().then(ByteData.sublistView),
      );
    }
    await loader.load();
  }

  // Every weight, not just the three in use: the buttons ask for w600, which
  // has no file of its own, and a weight with nothing to fall back on renders
  // as boxes. On a phone Roboto is the system font and this never arises.
  await load('Roboto', [
    'roboto-light.ttf',
    'roboto-regular.ttf',
    'roboto-medium.ttf',
    'roboto-bold.ttf',
    'roboto-black.ttf',
  ]);
  await load('MaterialIcons', ['materialicons-regular.otf']);

  // Text whose style names no family - the buttons' own TextStyle - falls
  // back to the family flutter_test makes default, whose glyphs are all
  // boxes. Pointing that name at Roboto too is the difference between a
  // screenshot of the app and a screenshot of empty rectangles. On a phone
  // the system font answers instead and none of this applies.
  // Button labels set a size and a weight but name no family, so they fall
  // through to whatever the engine calls default - which under `flutter test`
  // is a font whose every glyph is a filled box. Registering Roboto with no
  // family name puts it in that fallback chain. On a phone the system font is
  // already Roboto and none of this applies.
  for (final file in ['roboto-regular.ttf', 'roboto-medium.ttf']) {
    await ui.loadFontFromList(await File('${fonts.path}/$file').readAsBytes());
  }
}

final _freeAccount = ServerUser(
  uid: 'demo',
  since: DateTime(2026, 1, 1),
  plan: 'free',
  secondsLeft: 2400,
);

List<Note> _someNotes() {
  final now = DateTime(2026, 9, 25, 9, 12);
  return [
    for (final (minutes, title, seconds) in const [
      (0, '25 Sep, 9:12am', 47),
      (95, '25 Sep, 7:37am', 142),
      (1180, '24 Sep, 1:32pm', 21),
    ])
      Note(
        id: '$minutes',
        ownerUid: 'demo',
        title: title,
        path: '/audio/$minutes.m4a',
        addedAt: now.subtract(Duration(minutes: minutes)),
        duration: Duration(seconds: seconds),
        bytes: seconds * 32000,
      ),
  ];
}
