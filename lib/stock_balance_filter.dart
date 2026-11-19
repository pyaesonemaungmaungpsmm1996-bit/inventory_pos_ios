import 'package:flutter/material.dart';

import 'app_language.dart';

/// A requested filter may arrive before its asynchronous choices.
/// A missing choice is never silently converted to All in the underlying query.
class StockBalanceFilter extends StatelessWidget {
  const StockBalanceFilter({
    super.key,
    required this.title,
    required this.value,
    required this.data,
    required this.loading,
    required this.onChanged,
  });
  final String title;
  final int value;
  final List<Map<String, Object?>> data;
  final bool loading;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) {
    final my = AppLanguage.current.value == 'my';
    final choices = {
      for (final row in data)
        if (row['id'] is int && row['id'] != 0) row['id'] as int: row,
    };
    final int? displayed = value == 0 || choices.containsKey(value)
        ? value
        : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<int>(
        key: ValueKey('$title:$value:$displayed'),
        initialValue: displayed,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: title,
          helperText: displayed != null
              ? null
              : loading
              ? (my ? 'ရွေးချယ်စရာများ ဖတ်နေပါသည်…' : 'Loading choices…')
              : (my
                    ? 'ရွေးထားသည့်စာရင်း မရှိတော့ပါ။ ပြန်စမ်းပါ သို့မဟုတ် အသစ်ရွေးပါ။'
                    : 'Selected filter is unavailable. Retry or choose another.'),
        ),
        items: [
          DropdownMenuItem(value: 0, child: Text(my ? 'အားလုံး' : 'All')),
          for (final entry in choices.entries)
            DropdownMenuItem(
              value: entry.key,
              child: Text('${entry.value['name']}'),
            ),
        ],
        onChanged: loading
            ? null
            : (v) {
                if (v != null) onChanged(v);
              },
      ),
    );
  }
}
