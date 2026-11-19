import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_pos/subscription_pricing.dart';

void main() {
  final catalog = SubscriptionCatalog.preview;
  test('Monthly terms use list prices without the annual discount', () {
    expect(catalog.quote('standard', 1).totalMmk, 28000);
    expect(catalog.quote('premium', 1).totalMmk, 38000);
    expect(catalog.quote('standard', 1).discountBps, 0);
  });
  test('All annual terms up to five years use the duration-specific discounts', () {
    const standard = [302400, 571200, 806400, 1075200, 1344000];
    const premium = [410400, 775200, 1094400, 1459200, 1824000];
    for (var years = 1; years <= 5; years++) {
      expect(catalog.quote('standard', years * 12).totalMmk, standard[years - 1]);
      expect(catalog.quote('premium', years * 12).totalMmk, premium[years - 1]);
    }
  });
  test('A different catalog can change prices and discounts without changing an old quote', () {
    final oldQuote = catalog.quote('standard', 12);
    final updated = SubscriptionCatalog(version: 'next', plans: const [
      SubscriptionPlan(id: 'standard', monthlyMmk: 30000, branchLimit: 2),
    ], discountsBps: const {12: 1000, 60: 2000});
    expect(updated.quote('standard', 12).totalMmk, 324000);
    expect(updated.quote('standard', 24).discountMmk, 0);
    expect(updated.quote('standard', 60).totalMmk, 1440000);
    expect(oldQuote.totalMmk, 302400);
    expect(oldQuote.catalogVersion, catalog.version);
  });
  test('Unsupported plans, terms and invalid configurations are rejected', () {
    for (final months in [0, -1, 2, 11, 13, 61, 72]) {
      expect(() => catalog.quote('standard', months), throwsArgumentError);
    }
    expect(() => catalog.quote('trial', 1), throwsArgumentError);
    expect(() => catalog.quote('unknown', 12), throwsArgumentError);
    expect(() => SubscriptionCatalog(version: 'bad', plans: catalog.plans,
      discountsBps: {12: 10001}), throwsArgumentError);
    expect(() => SubscriptionCatalog(version: 'bad', plans: catalog.plans,
      discountsBps: {2: 1500}), throwsArgumentError);
    expect(() => SubscriptionCatalog(version: 'bad', plans: const [
      SubscriptionPlan(id: 'standard', monthlyMmk: 0, branchLimit: 2),
    ], discountsBps: {}), throwsArgumentError);
  });
  test('Rounding is deterministic whole MMK and formatting ignores shop currency', () {
    final odd = SubscriptionCatalog(version: 'round', plans: const [
      SubscriptionPlan(id: 'test', monthlyMmk: 1, branchLimit: 1),
    ], discountsBps: {1: 5000});
    expect(odd.quote('test', 1).discountMmk, 1);
    expect(odd.quote('test', 1).totalMmk, 0);
    expect(subscriptionMmk(1275000), '1,275,000 MMK');
    expect(subscriptionMmk(0), '0 MMK');
  });
  test('Catalog defensively copies configuration collections', () {
    final plans = [const SubscriptionPlan(id: 'x', monthlyMmk: 100, branchLimit: 2)];
    final discounts = {12: 1500};
    final copied = SubscriptionCatalog(version: 'copy', plans: plans, discountsBps: discounts);
    plans.clear(); discounts[12] = 0;
    expect(copied.quote('x', 12).totalMmk, 1020);
    expect(() => copied.discountsBps[12] = 0, throwsUnsupportedError);
  });
}
