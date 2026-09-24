import 'package:carry/api/api.dart';
import 'package:flutter/material.dart';
import 'package:carry/auth/auth.dart';
import 'package:carry/billing/plan_screen.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../helpers/pump.dart';
import '../helpers/test_analytics.dart';
import '../helpers/test_billing.dart';

void main() {
  late TestStore store;

  setUp(() {
    store = setUpTestStore();
    setUpTestAnalytics();
    Auth.firebaseForTesting = MockFirebaseAuth(signedIn: true);
  });

  tearDown(() {
    Auth.firebaseForTesting = null;
    Api.client = http.Client();
  });

  void serverSays({
    String plan = 'free',
    int secondsLeft = 3600,
    int status = 200,
  }) {
    Api.client = MockClient(
      (_) async => http.Response(
        '{"uid":"firebase-uid","email":null,"since":"2026-01-01T00:00:00Z",'
        '"plan":"$plan","plan_until":null,"seconds_left":$secondsLeft}',
        status,
      ),
    );
  }

  /// Lets the taps' async work finish.
  Future<void> settle(WidgetTester tester) async {
    for (var round = 0; round < 6; round++) {
      await tester.pump();
    }
  }

  Future<void> openPlan(WidgetTester tester) async {
    await pumpScreen(tester, const PlanScreen());
    await tester.pump(); // the server answers
    await tester.pump();
  }

  testWidgets('a free account is offered the plan, with what is left', (
    tester,
  ) async {
    serverSays(secondsLeft: 2400);

    await openPlan(tester);

    expect(find.text('Free'), findsOneWidget);
    expect(find.textContaining('40 minutes'), findsOneWidget);
    expect(find.text('₹199 / month'), findsOneWidget);
  });

  testWidgets('a paid account is not sold anything again', (tester) async {
    serverSays(plan: 'plus', secondsLeft: 71000);

    await openPlan(tester);

    expect(find.text('Carry Plus'), findsOneWidget);
    expect(find.text('₹199 / month'), findsNothing);
    expect(find.text('Restore a purchase'), findsNothing);
  });

  testWidgets('a server that cannot be reached says so, and assumes nothing', (
    tester,
  ) async {
    Api.client = MockClient((_) async => throw http.ClientException('offline'));

    await openPlan(tester);

    expect(find.textContaining("couldn't check your plan"), findsOneWidget);
    // Not "you're on free": a wrong answer here is one somebody is paying for.
    expect(find.text('Free'), findsNothing);
  });

  testWidgets(
    'buying asks the server afterwards rather than believing itself',
    (tester) async {
      serverSays();
      await openPlan(tester);
      // The store says the purchase worked; the server still says free, which
      // is what the screen must show.
      store.whenBought = null;

      await tester.tap(find.text('₹199 / month'));
      await tester.pump();
      await tester.pump();

      expect(store.purchases, 1);
      expect(find.text('Free'), findsOneWidget);
    },
  );

  testWidgets('cancelling the store sheet shows nothing at all', (
    tester,
  ) async {
    serverSays();
    await openPlan(tester);
    store.whenBought = 'cancelled';

    await tester.tap(find.text('₹199 / month'));
    await tester.pump();
    await settle(tester);

    expect(find.textContaining('cancelled'), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('restoring with nothing to restore says so plainly', (
    tester,
  ) async {
    serverSays();
    await openPlan(tester);

    await tester.tap(find.text('Restore a purchase'));
    await tester.pump();
    await settle(tester);

    expect(store.restores, 1);
    expect(find.textContaining('No earlier purchase'), findsOneWidget);
  });

  testWidgets('a confirmed purchase survives a refresh that fails after it', (
    tester,
  ) async {
    // Pull to refresh while the post-purchase read is in flight: the refresh
    // fails, the purchase read confirms Plus. Showing "unknown" and the buy
    // button to somebody the server has just confirmed is the worst outcome
    // of the two.
    var call = 0;
    Api.client = MockClient((_) async {
      call++;
      if (call == 2) throw http.ClientException('offline');
      return http.Response(
        '{"uid":"firebase-uid","email":null,"since":"2026-01-01T00:00:00Z",'
        '"plan":"plus","plan_until":null,"seconds_left":71000}',
        200,
      );
    });

    await openPlan(tester); // call 1 confirms plus
    await tester.drag(find.text('Carry Plus').first, const Offset(0, 300));
    await settle(tester); // call 2 fails

    expect(find.text('Carry Plus'), findsOneWidget);
    expect(find.text('₹199 / month'), findsNothing);
  });

  testWidgets('it says what a plan does not do', (tester) async {
    serverSays();

    await openPlan(tester);

    // The promise that matters: paying decides what gets transcribed, never
    // whether you can reach what you already recorded.
    expect(find.textContaining('never stops you reaching'), findsOneWidget);
  });
}
