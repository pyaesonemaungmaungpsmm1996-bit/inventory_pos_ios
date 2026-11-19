import 'package:flutter/material.dart';

import 'app_language.dart';

/// Every destination keeps a readable label; no selected-only labels.
class PosNavigationBar extends StatelessWidget {
  const PosNavigationBar({
    super.key,
    required this.selected,
    required this.onSelected,
  });
  final int selected;
  final ValueChanged<int> onSelected;
  static const labels = [
    'Dashboard',
    'Sale',
    'Inventory',
    'Expense',
    'Ledger',
    'Settings',
  ];
  static const myLabels = [
    'ပင်မ',
    'အရောင်း',
    'ပစ္စည်း',
    'စရိတ်',
    'စာရင်း',
    'ဆက်တင်',
  ];
  static const icons = [
    Icons.dashboard_outlined,
    Icons.point_of_sale_outlined,
    Icons.inventory_2_outlined,
    Icons.payments_outlined,
    Icons.menu_book_outlined,
    Icons.settings_outlined,
  ];
  Widget destination(BuildContext context, int index) {
    final colors = Theme.of(context).colorScheme;
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: selected == index
                  ? colors.primaryContainer
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icons[index],
              size: 21,
              color: selected == index
                  ? colors.secondary
                  : colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            AppLanguage.current.value == 'my' ? myLabels[index] : labels[index],
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(fontSize: 10, color: colors.onSurface),
          ),
        ],
      ),
    );
    return Expanded(
      child: Semantics(
        selected: selected == index,
        button: true,
        label: AppLanguage.text(labels[index]),
        child: Tooltip(
          message: AppLanguage.text(labels[index]),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => onSelected(index),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 60),
              child: content,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < labels.length; i++) destination(context, i),
          ],
        ),
      ),
    ),
  );
}
