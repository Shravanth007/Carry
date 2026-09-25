import 'package:carry/billing/billing.dart';
import 'package:flutter_test/flutter_test.dart';

/// A store a test drives: what it sells, and what buying does.
class TestStore implements PurchaseStore {
  List<Offer> selling = const [
    Offer(
      id: 'carry_plus_monthly',
      title: 'Carry Plus',
      price: '\$2.99 / month',
    ),
  ];

  /// What `buy` answers. Null means it completed.
  String? whenBought;

  /// What `restore` answers.
  String? whenRestored;

  /// Set to make reading what's for sale fail, as a dead network does.
  Object? failOnOffers;

  final identified = <String>[];

  /// Set to make the store refuse who is signed in, as RevenueCat does when
  /// logIn fails.
  bool refuseIdentity = false;

  /// Set to make buying throw rather than answer - a store adapter meeting
  /// something it doesn't handle.
  bool throwOnBuy = false;

  int forgets = 0;
  int purchases = 0;
  int restores = 0;

  @override
  Future<void> start(String key) async {}

  @override
  Future<void> identify(String uid) async {
    if (refuseIdentity) throw StateError('the store would not take that uid');
    identified.add(uid);
  }

  @override
  Future<void> forget() async => forgets++;

  @override
  Future<List<Offer>> offers() async {
    final failure = failOnOffers;
    if (failure != null) throw failure;
    return selling;
  }

  @override
  Future<String?> buy(Offer offer) async {
    purchases++;
    return whenBought;
  }

  @override
  Future<String?> restore() async {
    restores++;
    return whenRestored;
  }
}

/// Points [Billing] at a test store for the current test.
TestStore setUpTestStore() {
  Billing.resetForTesting();
  final store = TestStore();
  Billing.store = store;
  addTearDown(Billing.resetForTesting);
  return store;
}
