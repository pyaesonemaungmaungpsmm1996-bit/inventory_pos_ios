import 'dart:async';

import 'package:flutter/material.dart';

import 'app_currency.dart';
import 'app_language.dart';
import 'branch_records_sync.dart';

class SyncedBranchBalancePage extends StatefulWidget {
  const SyncedBranchBalancePage({
    super.key,
    required this.reader,
    required this.accounts,
  });

  final BranchRecordsSync reader;
  final bool accounts;

  @override
  State<SyncedBranchBalancePage> createState() =>
      _SyncedBranchBalancePageState();
}

class _SyncedBranchBalancePageState extends State<SyncedBranchBalancePage> {
  Timer? _timer;
  Map<String, dynamic>? _document;
  bool _loading = false;
  Object? _error;

  String t(String en, String my) => AppLanguage.current.value == 'my' ? my : en;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      unawaited(_refresh());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_loading || !mounted) return;
    setState(() => _loading = true);
    try {
      final document = await widget.reader.read();
      if (!mounted) return;
      setState(() {
        _document = document;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accounts = widget.accounts;
    final currency = _document?['currency'] as Map?;
    final records = _document?[accounts ? 'accounts' : 'stock'] as List?;
    final updated = DateTime.tryParse('${_document?['updated_at']}')?.toLocal();
    final localizations = MaterialLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          accounts
              ? t('Money Accounts', 'ငွေအကောင့်များ')
              : t('Balance Stock', 'ပစ္စည်းလက်ကျန်'),
        ),
        actions: [
          IconButton(
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 1 + (records?.length ?? 0),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Windows · ${widget.reader.branchCode}'),
                if (updated != null)
                  Text(
                    '${localizations.formatShortDate(updated)} · '
                    '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(updated))}',
                  ),
                if (_loading) const LinearProgressIndicator(),
                if (_error != null)
                  Text(
                    t(
                      'Could not refresh Windows records. Try again when online.',
                      'Windows စာရင်း မရသေးပါ။ အင်တာနက်ရလျှင် ပြန်စမ်းပါ။',
                    ),
                  ),
                if (!_loading && _error == null && records == null)
                  Text(
                    t(
                      'Open the updated Windows app and sync this branch.',
                      'ပြင်ထားသည့် Windows app မှ ဤဆိုင်ခွဲကို sync လုပ်ပါ။',
                    ),
                  ),
              ],
            );
          }
          final row = records![index - 1] as Map;
          return ListTile(
            title: Text('${row['name']}'),
            subtitle: Text('${row[accounts ? 'type' : 'item_code']}'),
            trailing: Text(
              accounts
                  ? AppCurrency.format(
                      row['balance'] as int,
                      currency: currency?['currency_code'] as String?,
                      decimalPlaces: currency?['currency_digits'] as int?,
                    )
                  : '${row['stock']}',
            ),
          );
        },
      ),
    );
  }
}
