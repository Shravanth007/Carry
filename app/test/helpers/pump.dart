import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phone sizes in logical pixels, the unit Flutter lays out in.
/// Small: a compact or older Android. Medium: Pixel 7. Large: a big phone.
const phoneSizes = {
  'small phone': Size(360, 640),
  'medium phone': Size(412, 915),
  'large phone': Size(430, 932),
};

/// Pumps [screen] on a phone-sized surface (Pixel 7 by default).
Future<void> pumpScreen(
  WidgetTester tester,
  Widget screen, {
  Size size = const Size(412, 915),
  double textScale = 1,
}) async {
  tester.view
    ..physicalSize = size * 3
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  if (textScale != 1) {
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }
  await tester.pumpWidget(MaterialApp(home: screen));
}
