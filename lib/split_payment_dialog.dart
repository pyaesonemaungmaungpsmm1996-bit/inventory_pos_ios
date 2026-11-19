import 'package:flutter/material.dart';

import 'app_currency.dart';
import 'app_language.dart';
import 'amount_input.dart';
import 'desktop_ui.dart';

/// Collects allocations only; the caller posts the voucher and payments together.
Future<List<Map<String, int>>?> showSplitPaymentDialog(
  BuildContext context, {
  required int total,
  required List<Map<String, Object?>> accounts,
  List<Map<String, int>> initial = const [],
  bool purchase = false,
  String? actionLabel,
}) async {
  String t(String en, String my) => AppLanguage.current.value == 'my' ? my : en;
  final inputs = {
    for (final a in accounts)
      a['id'] as int: TextEditingController(
        text: initial.where((p) => p['account_id'] == a['id']).isEmpty
            ? ''
            : AmountInputFormatter.group(
                AppCurrency.input(
                  initial
                      .where((p) => p['account_id'] == a['id'])
                      .fold<int>(0, (sum, p) => sum + p['amount']!),
                ),
              ),
      ),
  };
  String? error;
  try {
    return await showDialog<List<Map<String, int>>>(
      context: context,
      barrierDismissible: false,
      builder: (dialog) => StatefulBuilder(
        builder: (context, update) {
          final paid = inputs.values.fold<int>(
            0,
            (sum, c) =>
                sum +
                (AppCurrency.tryParse(c.text.isEmpty ? '0' : c.text) ?? 0),
          );
          return DesktopDialog(
            title: Text(
              purchase
                  ? t('Purchase payment', 'အဝယ် ငွေရှင်းခြင်း')
                  : t('Sale payment', 'အရောင်း ငွေရှင်းခြင်း'),
            ),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${t('Total', 'စုစုပေါင်း')}: ${AppCurrency.format(total)}',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      t(
                        'Split across accounts, pay a deposit, or leave all blank for credit.',
                        'အကောင့်ခွဲရှင်း၊ စရံရှင်းနိုင်သည်။ အကြွေးထားရန် အားလုံးဗလာထားပါ။',
                      ),
                    ),
                    for (final a in accounts)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: TextField(
                          key: ValueKey('split-payment-${a['id']}'),
                          controller: inputs[a['id']],
                          inputFormatters: const [AmountInputFormatter()],
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: (_) => update(() => error = null),
                          decoration: InputDecoration(
                            labelText: '${a['name']} (${a['type']})',
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Text('${t('Paid', 'ပေးငွေ')}: ${AppCurrency.format(paid)}'),
                    Text(
                      '${t('Balance', 'လက်ကျန်')}: ${AppCurrency.format(total - paid)}',
                    ),
                    if (error != null)
                      Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: Text(t('Cancel', 'မလုပ်တော့ပါ')),
              ),
              FilledButton(
                key: const ValueKey('confirm-split-payment'),
                onPressed: () {
                  final result = <Map<String, int>>[];
                  var allocated = 0;
                  for (final a in accounts) {
                    final raw = inputs[a['id']]!.text.trim();
                    final amount = AppCurrency.tryParse(
                      raw.isEmpty ? '0' : raw,
                    );
                    if (amount != null) allocated += amount;
                    if (amount == null || amount < 0 || allocated > total) {
                      update(
                        () => error = t(
                          'Check amounts; paid cannot exceed total.',
                          'ငွေပမာဏစစ်ပါ။ ပေးငွေသည် စုစုပေါင်းထက် မကျော်ရပါ။',
                        ),
                      );
                      return;
                    }
                    if (amount > 0) {
                      result.add({
                        'account_id': a['id'] as int,
                        'amount': amount,
                      });
                    }
                  }
                  Navigator.pop(dialog, result);
                },
                child: Text(
                  actionLabel ??
                      t(
                        'Confirm & continue to print',
                        'အတည်ပြုပြီး Print သို့သွားမည်',
                      ),
                ),
              ),
            ],
          );
        },
      ),
    );
  } finally {
    // Let the closing route release its text fields before disposing controllers.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    for (final c in inputs.values) {
      c.dispose();
    }
  }
}
