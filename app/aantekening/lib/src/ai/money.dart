/// Sums of money, as the AI's prices and costs are shown.
library;

/// [amount] of US dollars, as short as says it: `$5`, `$2.50`, `$0.28`,
/// `$0.0013` — two figures for what is under ten cents.
String dollars(double amount) {
  if (amount == 0) return r'$0';
  if (amount < 0.0001) return r'under $0.0001';
  if (amount >= 1 && amount == amount.roundToDouble()) {
    return '\$${amount.round()}';
  }
  if (amount >= 0.1) return '\$${amount.toStringAsFixed(2)}';
  final figures = amount
      .toStringAsPrecision(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
  return '\$$figures';
}

/// What something the AI did cost, reckoned, or null for what cost
/// nothing or is not known.
String? costNote(double? cost) =>
    cost == null || cost <= 0 ? null : '≈ ${dollars(cost)}';
