import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_pos/app_currency.dart';

void main() {
  tearDown(() => AppCurrency.current.value = 'MMK');
  test('existing MMK amounts retain their exact whole-kyat value', () {
    expect(AppCurrency.tryParse('3000'), 3000);
    expect(AppCurrency.format(3000), '3,000 Ks');
    expect(AppCurrency.format(1000000), '1,000,000 Ks');
    expect(AppCurrency.displayCode, 'Ks');
    expect(AppCurrency.tryParse('3.50'), isNull);
    expect(AppCurrency.input(2900), '2900');
  });
  for (final currency in ['USD', 'THB', 'CNY']) {
    test(
      '$currency decimal amounts are stored without floating point loss',
      () {
        AppCurrency.current.value = currency;
        expect(AppCurrency.parse('0.10') + AppCurrency.parse('0.20'), 30);
        expect(AppCurrency.format(30), '0.30 $currency');
        expect(AppCurrency.parse('12.5'), 1250);
        expect(AppCurrency.parse('12'), 1200);
        expect(AppCurrency.format(123456), '1,234.56 $currency');
        expect(AppCurrency.format(-123456), '-1,234.56 $currency');
        expect(AppCurrency.tryParse('1.001'), isNull);
        // A realistic split-payment sale and a later credit collection.
        final total =
            AppCurrency.parse('12.50') * 3 - AppCurrency.parse('0.25');
        final paid = AppCurrency.parse('10.10') + AppCurrency.parse('20.20');
        expect(total, 3725);
        expect(paid, 3030);
        expect(AppCurrency.format(total - paid), '6.95 $currency');
        expect(
          AppCurrency.format(total - paid - AppCurrency.parse('2.05')),
          '4.90 $currency',
        );
      },
    );
  }
  test('JPY only accepts whole yen', () {
    AppCurrency.current.value = 'JPY';
    expect(AppCurrency.parse('1250'), 1250);
    expect(AppCurrency.format(1250), '1,250 JPY');
    expect(AppCurrency.tryParse('1250.50'), isNull);
  });
  test('invalid formats and out-of-range amounts are rejected', () {
    for (final currency in AppCurrency.precision.keys) {
      AppCurrency.current.value = currency;
      for (final input in [
        '',
        '-1',
        '+1',
        '1e3',
        '1,00',
        '1,,000',
        'NaN',
        'Infinity',
        '.5',
        '1.',
        '၁၂',
      ]) {
        expect(
          AppCurrency.tryParse(input),
          isNull,
          reason: '$currency: $input',
        );
      }
      expect(AppCurrency.tryParse('9000000000001'), isNull);
      for (final minor in [
        0,
        1,
        10,
        99,
        100,
        1250,
        2147483647,
        9000000000000,
      ]) {
        expect(
          AppCurrency.parse(AppCurrency.input(minor)),
          minor,
          reason: '$currency: $minor',
        );
      }
    }
  });
  test('valid grouped commas preserve exact currency precision', () {
    expect(AppCurrency.tryParse('1,000', currency: 'MMK'), 1000);
    expect(AppCurrency.tryParse('1,000.25', currency: 'USD'), 100025);
    expect(AppCurrency.tryParse('12,34', currency: 'MMK'), isNull);
  });
  test(
    'historical invoice currency is independent from current display choice',
    () {
      AppCurrency.current.value = 'USD';
      expect(
        AppCurrency.format(3000, currency: 'MMK', decimalPlaces: 0),
        '3,000 Ks',
      );
      expect(
        () => AppCurrency.format(3000, currency: 'MMK', decimalPlaces: 2),
        throwsStateError,
      );
    },
  );
  test('unknown or inconsistent persisted currency fails closed', () {
    expect(
      () => AppCurrency.apply({'currency_code': 'XYZ', 'currency_digits': 2}),
      throwsStateError,
    );
    expect(
      () => AppCurrency.apply({'currency_code': 'USD', 'currency_digits': 0}),
      throwsStateError,
    );
    AppCurrency.apply({'currency_code': 'THB', 'currency_digits': 2});
    expect(AppCurrency.code, 'THB');
  });
}
