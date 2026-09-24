import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:purchases_flutter/purchases_flutter.dart';

import '../analytics/analytics.dart';
import '../api/api.dart';

/// What Carry sells. The server decides which one an account is on.
enum Plan {
  free,
  plus;

  static Plan named(String name) =>
      Plan.values.firstWhere((p) => p.name == name, orElse: () => Plan.free);
}

/// Something that can be bought, as the screen needs it.
@immutable
class Offer {
  const Offer({
    required this.id,
    required this.title,
    required this.price,
    this.package,
  });

  final String id;
  final String title;

  /// Already formatted by the store, in the person's own currency. Never
  /// build this from a number: the store knows the tax and the symbol.
  final String price;

  /// The store's own object, handed back when buying. Null in the demo.
  final Object? package;
}

/// Where buying happens. Tests and previews put their own here.
abstract interface class PurchaseStore {
  Future<void> start(String key);
  Future<void> identify(String uid);
  Future<void> forget();
  Future<List<Offer>> offers();

  /// Null when it completed, or a sentence to show. Cancelling is not an
  /// error: it returns [cancelled].
  Future<String?> buy(Offer offer);

  /// Null when it worked, or a sentence to show.
  Future<String?> restore();
}

/// The person closed the store's sheet. Not a failure, and shown as nothing.
const cancelled = 'cancelled';

/// Every purchase call in the app goes through here.
///
/// **The store is never what grants anything.** It makes the screen respond
/// the instant a purchase completes; what someone may actually do comes from
/// the server, which hears it from RevenueCat's webhook and writes it down.
/// When the two disagree, the server is right — it is the only one that can't
/// be lied to by a modified app.
///
/// Nothing is sold unless the build was given a key:
///   flutter run --dart-define=REVENUECAT_KEY=goog_...
/// Without one the screens still work against a demo store, so the paywall can
/// be seen and tested without an account, a product, or any money.
abstract final class Billing {
  /// RevenueCat's public SDK key. Public by design, like PostHog's and
  /// Firebase's: it identifies the app, it doesn't authorise anything.
  static const _key = String.fromEnvironment('REVENUECAT_KEY');

  @visibleForTesting
  static PurchaseStore store = const DemoStore();

  /// True when real money can change hands.
  static bool get isLive => store is _RevenueCat;

  /// Starts the store if this build has a key. Never throws: a shop that
  /// won't open is not a reason for the app not to.
  static Future<void> init() async {
    if (_key.isEmpty) {
      debugPrint('No REVENUECAT_KEY in this build: showing the demo store.');
      return;
    }
    try {
      const real = _RevenueCat();
      await real.start(_key);
      store = real;
    } catch (e) {
      debugPrint('The store would not start, carrying on without it: $e');
    }
  }

  /// Ties purchases to the account, using the same uid as everything else.
  ///
  /// It has to be the Firebase uid: the webhook tells the server which
  /// account changed by that id, and an account that bought under a different
  /// one is an account the server can't credit.
  static Future<void> identify(String uid) => _quietly(
    () => store.identify(uid),
    'Could not tell the store who is signed in',
  );

  static Future<void> forget() =>
      _quietly(store.forget, 'Could not sign out of the store');

  static Future<List<Offer>> offers() async {
    try {
      return await store.offers();
    } catch (e) {
      debugPrint('Could not read what is for sale: $e');
      return const [];
    }
  }

  static Future<String?> buy(Offer offer) async {
    Analytics.event('upgrade_started', {'offer': offer.id});
    final trouble = await store.buy(offer);
    Analytics.event(
      switch (trouble) {
        null => 'upgrade_completed',
        cancelled => 'upgrade_abandoned',
        _ => 'upgrade_failed',
      },
      {'offer': offer.id},
    );
    return trouble;
  }

  static Future<String?> restore() async {
    Analytics.event('restore_used');
    return store.restore();
  }

  /// What the server says this account may do.
  ///
  /// Asked after every purchase and every restore, because the store saying
  /// yes is a claim and this is the answer. A server that can't be reached
  /// leaves the plan unknown rather than assuming the good case: assuming
  /// would hand out Plus to anyone who turns off their wifi at the right
  /// moment.
  static Future<ServerUser?> fromServer() async {
    try {
      return await Api.me();
    } catch (e) {
      debugPrint('Could not read the plan from the server: $e');
      return null;
    }
  }

  static Future<void> _quietly(
    Future<void> Function() call,
    String whenWrong,
  ) async {
    try {
      await call();
    } catch (e) {
      debugPrint('$whenWrong: $e');
    }
  }
}

/// The real one.
class _RevenueCat implements PurchaseStore {
  const _RevenueCat();

  @override
  Future<void> start(String key) =>
      Purchases.configure(PurchasesConfiguration(key));

  @override
  Future<void> identify(String uid) async => Purchases.logIn(uid);

  @override
  Future<void> forget() async => Purchases.logOut();

  @override
  Future<List<Offer>> offers() async {
    final offerings = await Purchases.getOfferings();
    final current = offerings.current;
    if (current == null) return const [];
    return [
      for (final package in current.availablePackages)
        Offer(
          id: package.identifier,
          title: package.storeProduct.title,
          price: package.storeProduct.priceString,
          package: package,
        ),
    ];
  }

  @override
  Future<String?> buy(Offer offer) async {
    final package = offer.package;
    if (package is! Package) return "That isn't for sale right now.";
    try {
      await Purchases.purchase(PurchaseParams.package(package));
      return null;
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError) return cancelled;
      debugPrint('Purchase failed: $code');
      return _sentenceFor(code);
    }
  }

  @override
  Future<String?> restore() async {
    try {
      await Purchases.restorePurchases();
      return null;
    } on PlatformException catch (e) {
      debugPrint('Restore failed: $e');
      return "Carry couldn't check for an earlier purchase. Try again.";
    }
  }

  /// The store's codes, in words. Never the raw error: it carries ids and
  /// sometimes a URL.
  static String _sentenceFor(PurchasesErrorCode code) => switch (code) {
    PurchasesErrorCode.purchaseNotAllowedError =>
      "This phone doesn't allow purchases.",
    PurchasesErrorCode.paymentPendingError =>
      'That payment is still going through. Carry will catch up when it does.',
    PurchasesErrorCode.productAlreadyPurchasedError =>
      'You already have Carry Plus. Try restoring it.',
    PurchasesErrorCode.networkError =>
      'No internet connection. Connect and try again.',
    _ => "That didn't go through. Nothing was charged.",
  };
}

/// A store with nothing behind it, for builds with no key.
///
/// It exists so the plan screen can be opened, laid out, previewed and tested
/// without a RevenueCat account, a Play product, or a single rupee. It cannot
/// grant anything, because granting isn't the store's job in the first place —
/// after a purchase the app asks the server, and in a demo build the server
/// will quite correctly still say free.
class DemoStore implements PurchaseStore {
  const DemoStore();

  @override
  Future<void> start(String key) async {}

  @override
  Future<void> identify(String uid) async {}

  @override
  Future<void> forget() async {}

  @override
  Future<List<Offer>> offers() async => const [
    Offer(id: 'carry_plus_monthly', title: 'Carry Plus', price: '₹199 / month'),
  ];

  @override
  Future<String?> buy(Offer offer) async =>
      'This build has no store behind it, so nothing was bought.';

  @override
  Future<String?> restore() async =>
      'This build has no store behind it, so there is nothing to restore.';
}
