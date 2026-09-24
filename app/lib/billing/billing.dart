import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:purchases_flutter/purchases_flutter.dart';

import '../analytics/analytics.dart';
import '../api/api.dart';
import '../auth/auth.dart';

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

  /// Identity changes, one after another, in the order they were asked for.
  ///
  /// Signing in and out are fire-and-forget from the caller's point of view,
  /// so without this a sign-out started first can finish last and wipe the
  /// identity of whoever just signed in. Buying waits on the same chain, so a
  /// purchase can never be made under the previous account — the server would
  /// have no way to credit it.
  ///
  /// **Null means nothing is in flight**, rather than a future that has
  /// already completed. A `Future` belongs to the zone that made it, and a
  /// widget test runs in a zone of its own: one made in `setUp` never gets its
  /// microtask run inside the test, so awaiting it hangs for ever. Storing
  /// null and making the future where it is awaited keeps that impossible.
  static Future<void>? _identity;

  /// Who the store last accepted, or null if it refused or was never told.
  ///
  /// A failed `logIn` used to be logged and forgotten, which left buying to go
  /// ahead under whoever the store thought it was - anonymous, or the last
  /// person on this phone. The server credits by uid, so that purchase would
  /// reach nobody.
  static String? _identifiedAs;

  static Future<void> _queue(Future<void> Function() change) {
    final next = settled().then((_) => change()).catchError((Object e) {
      debugPrint('Store identity: $e');
    });
    _identity = next;
    return next;
  }

  /// Waits for any identity change still in flight.
  @visibleForTesting
  static Future<void> settled() => _identity ?? Future<void>.value();

  /// Back to how a fresh app starts: the demo store, and nothing in flight.
  ///
  /// The identity chain is static, so without this one test's unfinished
  /// sign-in can be what the next test is waiting on.
  @visibleForTesting
  static void resetForTesting() {
    store = const DemoStore();
    _identity = null;
    _identifiedAs = null;
  }

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
  static Future<void> identify(String uid) => _queue(() async {
    await store.identify(uid);
    _identifiedAs = uid;
  });

  static Future<void> forget() => _queue(() async {
    await store.forget();
    _identifiedAs = null;
  });

  static Future<List<Offer>> offers() async {
    try {
      return await store.offers();
    } catch (e) {
      debugPrint('Could not read what is for sale: $e');
      return const [];
    }
  }

  static Future<String?> buy(Offer offer) async {
    // Whoever is signed in now is who this is bought for, and the store has to
    // agree about that before any money moves.
    final refusal = await _readyToBuy();
    if (refusal != null) return refusal;
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
    final refusal = await _readyToBuy();
    if (refusal != null) return refusal;
    Analytics.event('restore_used');
    return store.restore();
  }

  /// Makes sure the store knows who is buying, and says so if it can't.
  ///
  /// Refusing is the right answer. A purchase made under the wrong identity
  /// takes real money and reaches no account, and there is nothing the person
  /// could do about it afterwards.
  static Future<String?> _readyToBuy() async {
    await settled();
    final uid = Auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) return 'Sign in first.';
    if (_identifiedAs == uid) return null;
    await identify(uid);
    if (_identifiedAs == uid) return null;
    return "Carry couldn't confirm your account with the store. Try again.";
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
