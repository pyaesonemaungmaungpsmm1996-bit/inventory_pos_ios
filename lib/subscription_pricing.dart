/// Prices are whole MMK and independent of the shop's accounting currency.
/// This bundled catalog is a preview. Production checkout must use server quotes.
class SubscriptionPlan {
  const SubscriptionPlan({
    required this.id,
    required this.monthlyMmk,
    required this.branchLimit,
  });
  final String id;
  final int monthlyMmk;
  final int? branchLimit;
}

class SubscriptionQuote {
  const SubscriptionQuote({
    required this.catalogVersion,
    required this.plan,
    required this.months,
    required this.baseMmk,
    required this.discountBps,
    required this.discountMmk,
    required this.totalMmk,
  });
  final String catalogVersion;
  final SubscriptionPlan plan;
  final int months, baseMmk, discountBps, discountMmk, totalMmk;
}

class SubscriptionCatalog {
  SubscriptionCatalog({
    required this.version,
    required List<SubscriptionPlan> plans,
    required Map<int, int> discountsBps,
  }) : plans = List.unmodifiable(plans),
       discountsBps = Map.unmodifiable(discountsBps) {
    if (version.trim().isEmpty ||
        plans.isEmpty ||
        plans.map((p) => p.id).toSet().length != plans.length) {
      throw ArgumentError('Invalid pricing catalog');
    }
    for (final plan in plans) {
      if (plan.id.trim().isEmpty ||
          plan.monthlyMmk <= 0 ||
          plan.monthlyMmk > 1000000000 ||
          (plan.branchLimit != null && plan.branchLimit! < 1)) {
        throw ArgumentError('Invalid plan');
      }
    }
    for (final entry in discountsBps.entries) {
      if (!terms.contains(entry.key) ||
          entry.value < 0 ||
          entry.value > 10000) {
        throw ArgumentError('Invalid discount');
      }
    }
  }
  static const terms = [1, 12, 24, 36, 48, 60];
  final String version;
  final List<SubscriptionPlan> plans;

  /// Basis points: 1500 = 15%. Absent terms have no discount.
  final Map<int, int> discountsBps;
  static final preview = SubscriptionCatalog(
    version: 'preview-2026-11-10-v2',
    plans: const [
      SubscriptionPlan(id: 'standard', monthlyMmk: 28000, branchLimit: 1),
      SubscriptionPlan(id: 'premium', monthlyMmk: 38000, branchLimit: null),
    ],
    discountsBps: const {12: 1000, 24: 1500, 36: 2000, 48: 2000, 60: 2000},
  );

  SubscriptionQuote quote(String planId, int months) {
    if (!terms.contains(months)) {
      throw ArgumentError('Unsupported subscription term');
    }
    final matches = plans.where((p) => p.id == planId);
    if (matches.length != 1) {
      throw ArgumentError('Unknown subscription plan');
    }
    final plan = matches.single;
    final base = plan.monthlyMmk * months;
    final bps = discountsBps[months] ?? 0;
    // Nearest whole kyat, half rounded up. No floating point money arithmetic.
    final discount = (base * bps + 5000) ~/ 10000;
    return SubscriptionQuote(
      catalogVersion: version,
      plan: plan,
      months: months,
      baseMmk: base,
      discountBps: bps,
      discountMmk: discount,
      totalMmk: base - discount,
    );
  }
}

String subscriptionMmk(int amount) {
  final digits = amount.abs().toString();
  final result = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) {
      result.write(',');
    }
    result.write(digits[i]);
  }
  return '${amount < 0 ? '-' : ''}$result MMK';
}
