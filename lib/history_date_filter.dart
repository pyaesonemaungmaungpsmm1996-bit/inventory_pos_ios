import 'package:flutter/material.dart';

import 'app_language.dart';

class HistoryDates {
  static String day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  static bool includes(Object? date, DateTime? from, DateTime? to) {
    if (from == null && to == null) return true;
    final parsed = DateTime.tryParse('$date');
    if (parsed == null) return false;
    final value = day(parsed);
    return (from == null || value.compareTo(day(from)) >= 0) &&
        (to == null || value.compareTo(day(to)) <= 0);
  }
}

class HistoryDateFilter extends StatelessWidget {
  const HistoryDateFilter({
    super.key,
    this.from,
    this.to,
    required this.onChanged,
  });
  final DateTime? from, to;
  final void Function(DateTime? from, DateTime? to) onChanged;
  String t(String en, String my) => AppLanguage.current.value == 'my' ? my : en;
  Future<void> choose(BuildContext context, bool start) async {
    final first = start ? DateTime(1900) : from ?? DateTime(1900);
    final last = start ? to ?? DateTime(2200) : DateTime(2200);
    var initial = (start ? from : to) ?? DateTime.now();
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );
    if (date != null && context.mounted) {
      onChanged(start ? date : from, start ? to : date);
    }
  }

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      OutlinedButton.icon(
        key: const ValueKey('history-from-date'),
        onPressed: () => choose(context, true),
        icon: const Icon(Icons.date_range_outlined, size: 18),
        label: Text(
          '${t('From date', 'စရက်')}${from == null ? '' : ': ${HistoryDates.day(from!)}'}',
        ),
      ),
      OutlinedButton.icon(
        key: const ValueKey('history-to-date'),
        onPressed: () => choose(context, false),
        icon: const Icon(Icons.date_range_outlined, size: 18),
        label: Text(
          '${t('To date', 'ဆုံးရက်')}${to == null ? '' : ': ${HistoryDates.day(to!)}'}',
        ),
      ),
      TextButton(
        key: const ValueKey('history-clear-dates'),
        onPressed: from == null && to == null
            ? null
            : () => onChanged(null, null),
        child: Text(t('Clear dates', 'ရက်စွဲ ရှင်းမည်')),
      ),
    ],
  );
}
