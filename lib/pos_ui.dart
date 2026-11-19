import 'package:flutter/material.dart';

import 'app_currency.dart';

/// Numbers keep their exact configured precision; currency is visually secondary.
class MoneyText extends StatelessWidget {
  const MoneyText(
    this.amount, {
    super.key,
    this.currency,
    this.decimalPlaces,
    this.style,
    this.size = 14,
  });
  final int amount;
  final String? currency;
  final int? decimalPlaces;
  final TextStyle? style;
  final double size;
  @override
  Widget build(BuildContext context) {
    final value = AppCurrency.format(
      amount,
      currency: currency,
      decimalPlaces: decimalPlaces,
    );
    final split = value.lastIndexOf(' ');
    final base = (style ?? Theme.of(context).textTheme.titleMedium!).copyWith(
      fontSize: style?.fontSize ?? size,
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final screenWidth = MediaQuery.sizeOf(context).width;
    return Semantics(
      label: value,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: screenWidth > 0 ? screenWidth * .6 : double.infinity,
        ),
        child: Text.rich(
          TextSpan(
            style: base,
            children: [
              TextSpan(text: value.substring(0, split)),
              TextSpan(
                text: value.substring(split),
                style: base.copyWith(
                  fontSize: (base.fontSize ?? size) * .65,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AmountSummary extends StatelessWidget {
  const AmountSummary({super.key, required this.label, required this.amount});
  final String label;
  final int amount;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(vertical: 10),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(14),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < 310 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.25;
        final children = [
          Text(label, style: Theme.of(context).textTheme.titleSmall),
          MoneyText(amount, size: 20),
        ];
        return stacked
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [children[0], const SizedBox(height: 6), children[1]],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(child: children[0]),
                  const SizedBox(width: 12),
                  Flexible(child: children[1]),
                ],
              );
      },
    ),
  );
}
