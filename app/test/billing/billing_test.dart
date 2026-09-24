import 'package:carry/api/api.dart';
import 'package:carry/auth/auth.dart';
import 'package:carry/billing/billing.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../helpers/test_analytics.dart';
import '../helpers/test_billing.dart';

/// The store makes buying happen. What somebody may do afterwards is the
/// server's answer, and these are about keeping those two apart.
void main() {
  late TestStore store;

  setUp(() {
    store = setUpTestStore();
    Auth.firebaseForTesting = MockFirebaseAuth(signedIn: true);
  });

  tearDown(() {
    Auth.firebaseForTesting = null;
    Api.client = http.Client();
  });

  void serverSays(String body, {int status = 200}) {
    Api.client = MockClient((_) async => http.Response(body, status));
  }

  String account({String plan = 'free', int secondsLeft = 3600}) =>
      '{"uid":"firebase-uid","email":null,"since":"2026-01-01T00:00:00Z",'
      '"plan":"$plan","plan_until":null,"seconds_left":$secondsLeft}';

  test('a build with no key shows the demo store, and sells nothing', () async {
    Billing.store = const DemoStore();

    expect(Billing.isLive, isFalse);
    expect(await Billing.offers(), hasLength(1));
    expect(
      await Billing.buy((await Billing.offers()).single),
      contains('no store behind it'),
    );
  });

  test('what is for sale comes from the store', () async {
    expect((await Billing.offers()).single.price, '₹199 / month');
  });

  test(
    'a store that will not answer sells nothing, rather than throwing',
    () async {
      store.failOnOffers = Exception('no network');

      expect(await Billing.offers(), isEmpty);
    },
  );

  test('cancelling is not a failure', () async {
    store.whenBought = cancelled;

    expect(await Billing.buy(store.selling.single), cancelled);
  });

  group('what gets counted', () {
    test('a purchase that worked', () async {
      final events = setUpTestAnalytics();
      store.whenBought = null;

      await Billing.buy(store.selling.single);

      expect(events.names(), ['upgrade_started', 'upgrade_completed']);
    });

    test('a purchase somebody backed out of is not a failure', () async {
      final events = setUpTestAnalytics();
      store.whenBought = cancelled;

      await Billing.buy(store.selling.single);

      expect(events.names().last, 'upgrade_abandoned');
    });

    test('a purchase that went wrong', () async {
      final events = setUpTestAnalytics();
      store.whenBought = 'the card was refused';

      await Billing.buy(store.selling.single);

      expect(events.names().last, 'upgrade_failed');
    });

    test('and it is counted in the facade, not the screen', () async {
      // A screen can be rebuilt; deciding to buy happens once.
      final events = setUpTestAnalytics();

      await Billing.restore();

      expect(events.has('restore_used'), isTrue);
    });
  });

  group('the server decides', () {
    test('the plan comes from the server, not from the store', () async {
      serverSays(account(plan: 'plus', secondsLeft: 71000));

      final user = await Billing.fromServer();

      expect(user?.plan, 'plus');
      expect(user?.secondsLeft, 71000);
    });

    test('a store that says yes cannot make the server say plus', () async {
      // The whole point: a modified app can make `buy` return success. It
      // still reads free until the webhook has reached the server.
      store.whenBought = null; // "it worked"
      serverSays(account());

      await Billing.buy(store.selling.single);

      expect((await Billing.fromServer())?.plan, 'free');
    });

    test('a server that cannot be reached leaves the plan unknown', () async {
      // Not "free", and certainly not "plus": assuming either is how somebody
      // ends up paying for nothing, or getting it for nothing.
      Api.client = MockClient(
        (_) async => throw http.ClientException('offline'),
      );

      expect(await Billing.fromServer(), isNull);
    });
  });

  group('buying needs an identity the store accepted', () {
    test('a store that refuses the uid refuses the purchase', () async {
      // The alternative is a purchase under whoever the store thinks it is -
      // anonymous, or the last person on this phone. The server credits by
      // uid, so that money reaches nobody.
      store.refuseIdentity = true;
      await Billing.identify(Auth.currentUser!.uid);

      final trouble = await Billing.buy(store.selling.single);

      expect(trouble, contains("couldn't confirm your account"));
      expect(store.purchases, 0);
    });

    test('and says so for restoring too', () async {
      store.refuseIdentity = true;
      await Billing.identify(Auth.currentUser!.uid);

      expect(await Billing.restore(), contains("couldn't confirm"));
      expect(store.restores, 0);
    });

    test('an identity the store took lets buying through', () async {
      await Billing.identify(Auth.currentUser!.uid);

      expect(await Billing.buy(store.selling.single), isNull);
      expect(store.purchases, 1);
    });

    test('signed out, nothing is bought', () async {
      Auth.firebaseForTesting = MockFirebaseAuth();

      expect(await Billing.buy(store.selling.single), 'Sign in first.');
      expect(store.purchases, 0);
    });

    test(
      'a signed-in person the store never heard of is identified first',
      () async {
        // Nobody called identify - the app was opened straight onto the plan
        // screen after a restart.
        expect(await Billing.buy(store.selling.single), isNull);
        expect(store.identified, [Auth.currentUser!.uid]);
      },
    );
  });

  group('identity', () {
    test('purchases are tied to the Firebase uid', () async {
      await Billing.identify('ada');

      expect(store.identified, ['ada']);
    });

    test('signing out forgets who was buying', () async {
      await Billing.forget();

      expect(store.forgets, 1);
    });

    test(
      'a store that throws while identifying does not break signing in',
      () async {
        Billing.store = _BrokenStore();
        addTearDown(() => Billing.store = const DemoStore());

        await Billing.identify('ada');
        await Billing.forget();
      },
    );
  });
}

/// A store having a bad day.
class _BrokenStore implements PurchaseStore {
  @override
  Future<void> start(String key) async => throw StateError('no');

  @override
  Future<void> identify(String uid) async => throw StateError('no');

  @override
  Future<void> forget() async => throw StateError('no');

  @override
  Future<List<Offer>> offers() async => throw StateError('no');

  @override
  Future<String?> buy(Offer offer) async => throw StateError('no');

  @override
  Future<String?> restore() async => throw StateError('no');
}
