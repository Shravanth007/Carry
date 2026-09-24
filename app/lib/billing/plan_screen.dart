import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../api/api.dart';
import '../limits.dart';
import '../settings/widgets.dart';
import '../theme.dart';
import '../widgets/scrollable_column.dart';
import 'billing.dart';

/// What Carry is offering, and what this account has.
///
/// The plan shown here is the **server's** answer, never the store's. The
/// store makes buying happen; what someone may do afterwards is read back from
/// `/me`, because that is the one answer a modified app can't fake.
class PlanScreen extends StatefulWidget {
  const PlanScreen({super.key, this.previewUser, this.previewProblem});

  /// Fills the screen in for `flutter widget-preview start`, where there is
  /// no server to ask.
  final ServerUser? previewUser;
  final String? previewProblem;

  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  ServerUser? _account;
  List<Offer> _offers = const [];
  bool _loading = true;
  bool _busy = false;
  String? _problem;

  /// True when a purchase went through but the server hasn't heard yet.
  bool _justBought = false;

  /// Which read of the plan is the current one.
  ///
  /// A pull-to-refresh can overlap the read that follows a purchase. Without
  /// this the slower answer wins, and an older "free" can replace a confirmed
  /// "plus" - putting the buy button back in front of somebody who just paid.
  int _read = 0;

  bool get _isPreview =>
      widget.previewUser != null || widget.previewProblem != null;

  bool get _hasPlus => _account?.plan == 'plus';

  @override
  void initState() {
    super.initState();
    if (_isPreview) {
      _account = widget.previewUser;
      _problem = widget.previewProblem;
      _offers = const [
        Offer(id: 'plus', title: 'Carry Plus', price: '₹199 / month'),
      ];
      _loading = false;
      return;
    }
    _load();
  }

  Future<void> _load() async {
    final mine = ++_read;
    final account = await Billing.fromServer();
    final offers = await Billing.offers();
    if (!mounted) return;
    // Between two answers, the newer one wins - always, whatever either says.
    // Letting a "confirmation" jump the queue sounds safe and isn't: an older
    // paid answer would then hide the buy button after the plan had expired.
    if (mine != _read) return;
    setState(() {
      _loading = false;
      if (account == null) {
        // A read that failed knows nothing, so it replaces nothing. Wiping a
        // plan the server already confirmed would put the buy button back in
        // front of somebody who has just paid.
        _problem = "Carry couldn't check your plan. Pull down to try again.";
        return;
      }
      _account = account;
      _offers = offers;
      _problem = null;
      if (account.plan == 'plus') _justBought = false;
    });
  }

  Future<void> _buy(Offer offer) async {
    setState(() {
      _busy = true;
      _problem = null;
    });
    String? trouble;
    try {
      trouble = await Billing.buy(offer);
      if (!mounted) return;
      if (trouble == cancelled) return; // closing the sheet is a decision
      // Whatever the store said, the server decides - and it hears through a
      // webhook, which takes a moment to arrive. So: read once, and if the
      // server hasn't caught up, say so and offer "Check again" rather than
      // showing "Free" and a buy button to somebody who has just paid.
      await _load();
      if (mounted && trouble == null && !_hasPlus) {
        setState(() => _justBought = true);
      }
      if (mounted && trouble != null) setState(() => _problem = trouble);
    } catch (e) {
      debugPrint('Buying went wrong: $e');
      if (mounted) {
        setState(
          () => _problem = "That didn't go through. Nothing was charged.",
        );
      }
    } finally {
      // Every path, including the ones that threw: a screen whose buttons
      // never come back is worse than the failure that disabled them.
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      final trouble = await Billing.restore();
      if (trouble != null) {
        if (mounted) setState(() => _problem = trouble);
        return;
      }
      await _load();
      if (!mounted) return;
      setState(() {
        // "Nothing to restore" is a claim about the account, so it can only
        // be made when the server actually answered. If the plan is unknown,
        // _load has already said so, and saying this instead would tell a
        // paying customer they never bought anything.
        if (_account != null && !_hasPlus) {
          _problem = 'No earlier purchase to restore.';
        }
      });
    } catch (e) {
      debugPrint('Restoring went wrong: $e');
      if (mounted) {
        setState(
          () => _problem = "Carry couldn't check for an earlier purchase.",
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Plan')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ScrollableColumn(
                alwaysScrollable: true, // the refresh needs a drag to start
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  _Current(account: _account),
                  const SizedBox(height: 20),
                  if (!_hasPlus) ...[
                    for (final offer in _offers)
                      _PlusCard(
                        offer: offer,
                        busy: _busy,
                        onBuy: () => _buy(offer),
                      ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _busy ? null : _restore,
                      child: const Text('Restore a purchase'),
                    ),
                  ],
                  if (_justBought && !_hasPlus) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Thanks — the store has your payment. It can take a moment '
                      'to reach Carry.',
                      style: text.bodyMedium,
                    ),
                    TextButton(
                      onPressed: _busy ? null : _load,
                      child: const Text('Check again'),
                    ),
                  ],
                  if (_problem != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _problem!,
                      style: text.bodyMedium?.copyWith(
                        color: CarryColors.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    'Carry never stops you reaching what you already recorded. '
                    'A plan only decides how much new audio it will transcribe.',
                    style: text.bodySmall?.copyWith(color: CarryColors.muted),
                  ),
                ],
              ),
            ),
    );
  }
}

/// What this account has right now, as the server sees it.
class _Current extends StatelessWidget {
  const _Current({required this.account});

  final ServerUser? account;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final user = account;
    final plus = user?.plan == 'plus';
    return SettingsCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              // Never "Free" when we simply couldn't ask: somebody paying
              // shouldn't be told they didn't.
              switch (user) {
                null => 'Plan unknown',
                _ when plus => 'Carry Plus',
                _ => 'Free',
              },
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(switch (user?.secondsLeft) {
              // Three different things, and only one of them is bad news.
              null when user == null => "Couldn't reach the server",
              null => 'How much is left is unknown just now',
              final int left =>
                '${_minutes(left)} of transcription left this month',
            }, style: text.bodyMedium?.copyWith(color: CarryColors.muted)),
            if (plus && user?.planUntil != null) ...[
              const SizedBox(height: 4),
              Text(
                // Not "renews": a cancelled subscription still runs to this
                // date, and telling somebody it renews would be wrong in the
                // one case they care about.
                'Your plan runs until ${_date(user!.planUntil!)}',
                style: text.bodySmall?.copyWith(color: CarryColors.muted),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _minutes(int seconds) {
    final minutes = seconds ~/ 60;
    if (minutes < 60) return '$minutes ${minutes == 1 ? 'minute' : 'minutes'}';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    final saidHours = '$hours ${hours == 1 ? 'hour' : 'hours'}';
    // Nearly two hours should not read as one: dropping the minutes
    // understates the allowance for most of every hour.
    return rest == 0 ? saidHours : '$saidHours $rest min';
  }

  static String _date(DateTime when) =>
      '${when.day}/${when.month}/${when.year}';
}

class _PlusCard extends StatelessWidget {
  const _PlusCard({
    required this.offer,
    required this.busy,
    required this.onBuy,
  });

  final Offer offer;
  final bool busy;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SettingsCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              offer.title,
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              'What you get',
              style: text.bodySmall?.copyWith(color: CarryColors.muted),
            ),
            const SizedBox(height: 12),
            // Not const: a record's field can't be read in a const
            // expression, and the numbers belong in limits.dart.
            _Benefit(
              gives: Plans.plus.transcription,
              insteadOf: Plans.free.transcription,
            ),
            const SizedBox(height: 10),
            _Benefit(gives: Plans.plus.audio, insteadOf: Plans.free.audio),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: busy ? null : onBuy,
                style: carryButton,
                child: busy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    // The price the store quoted, in the money the person
                    // actually pays. Never a number typed in here.
                    : Text('Upgrade for ${offer.price}'),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Google Play takes the payment and manages it. Cancel any time '
              'in Play, and Plus runs to the end of the period you paid for.',
              style: text.bodySmall?.copyWith(color: CarryColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

/// One thing Plus gives, and what Free gives instead.
///
/// Both lines, not just the good one: "20 hours a month" means nothing to
/// somebody who doesn't know what they have now, and a paywall that hides the
/// comparison is the kind that gets refunded.
class _Benefit extends StatelessWidget {
  const _Benefit({required this.gives, required this.insteadOf});

  final String gives;
  final String insteadOf;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          // Sits on the first line of text however large the type is.
          padding: const EdgeInsets.only(top: 2),
          child: Icon(Icons.check_rounded, size: 18, color: CarryColors.accent),
        ),
        const SizedBox(width: 10),
        // Flexible, because at the largest text size these wrap to three
        // lines on a small phone.
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(gives, style: text.bodyMedium),
              Text(
                'Free: $insteadOf',
                style: text.bodySmall?.copyWith(color: CarryColors.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

ServerUser _someone({String plan = 'free', int secondsLeft = 2400}) =>
    ServerUser(
      uid: 'preview',
      since: DateTime(2026, 1, 1),
      plan: plan,
      planUntil: plan == 'plus' ? DateTime(2026, 11, 1) : null,
      secondsLeft: secondsLeft,
    );

@Preview(name: 'Plan · free', wrapper: previewApp)
Widget planFree() => PlanScreen(previewUser: _someone());

@Preview(name: 'Plan · out of minutes', wrapper: previewApp)
Widget planEmpty() => PlanScreen(previewUser: _someone(secondsLeft: 0));

@Preview(name: 'Plan · plus', wrapper: previewApp)
Widget planPlus() =>
    PlanScreen(previewUser: _someone(plan: 'plus', secondsLeft: 71000));

@Preview(name: 'Plan · server unreachable', wrapper: previewApp)
Widget planUnknown() => const PlanScreen(
  previewProblem: "Carry couldn't check your plan. Pull down to try again.",
);
