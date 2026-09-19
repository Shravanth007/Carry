import 'package:carry/onboarding/microphone_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';

import '../helpers/pump.dart';
import '../helpers/test_device.dart';

void main() {
  late TestPermissions permissions;
  var done = 0;

  setUp(() {
    permissions = setUpTestPermissions();
    done = 0;
  });

  Future<void> pumpPermission(WidgetTester tester) =>
      pumpScreen(tester, MicrophoneScreen(onDone: () => done++));

  testWidgets('explains why before prompting', (tester) async {
    await pumpPermission(tester);

    expect(find.text('Carry needs your microphone'), findsOneWidget);
    expect(
      find.textContaining('Nothing is recorded until you press record'),
      findsOneWidget,
    );
    expect(permissions.prompts, 0, reason: 'no prompt without a tap');
  });

  testWidgets('allowing moves on', (tester) async {
    await pumpPermission(tester);

    await tester.tap(find.text('Allow microphone'));
    await tester.pumpAndSettle();

    expect(permissions.prompts, 1);
    expect(done, 1);
  });

  testWidgets('"Not now" moves on without prompting', (tester) async {
    await pumpPermission(tester);

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();

    expect(permissions.prompts, 0);
    expect(done, 1);
  });

  testWidgets('denying once still moves on', (tester) async {
    permissions.answer = PermissionStatus.denied;
    await pumpPermission(tester);

    await tester.tap(find.text('Allow microphone'));
    await tester.pumpAndSettle();

    expect(done, 1, reason: 'home shows the reminder banner instead');
  });

  testWidgets('a blocked microphone points at Settings', (tester) async {
    permissions.answer = PermissionStatus.permanentlyDenied;
    await pumpPermission(tester);

    await tester.tap(find.text('Allow microphone'));
    await tester.pumpAndSettle();

    expect(done, 0, reason: 'stays put so the user can read why');
    expect(find.textContaining('Turn it on in Settings'), findsOneWidget);

    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();
    expect(permissions.settingsOpened, 1);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(done, 1);
  });
}
