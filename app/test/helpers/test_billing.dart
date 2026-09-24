import 'package:carry/billing/billing.dart';
import 'package:flutter_test/flutter_test.dart';

/// A store a test drives: what it sells, and what buying does.
class TestStore implements PurchaseStore {
  List<Offer> selling = const [
    Offer(id: 'carry_plus_monthly', title: 'Carry Plus', price: '₹199 / month'),
  ];

  /// What `buy` answers. Null means it completed.
  String? whenBought;

  /// What `restore` answers.
  String? whenRestored;

  /// Set to make reading what's for sale fail, as a dead network does.
  Object? failOnOffers;

  final identified = <String>[];
  int forgets = 0;
  int purchases = 0;
  int restores = 0;

  @override
  Future<void> start(String key) async {}

  @override
  Future<void> identify(String uid) async => identified.add(uid);

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
  final store = TestStore();
  Billing.store = store;
  addTearDown(() => Billing.store = const DemoStore());
  return store;
}
