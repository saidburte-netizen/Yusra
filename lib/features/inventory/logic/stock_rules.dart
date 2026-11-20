// Pure stock rules for Agent B. No Flutter or Supabase imports so the rules can
// be unit-tested on their own. The database remains the source of truth for all
// stock mutations; these helpers only drive UI state and suggestions.

enum ExpiryTone { ok, gold, warning, danger }

enum StockStatus { inStock, low, outOfStock, expiringSoon, expired }

abstract final class StockRules {
  /// Reorder suggestion from the contract: reorder level x 2 minus available,
  /// with a minimum of one unit.
  static int suggestedOrder(int reorderLevel, int available) {
    final suggestion = reorderLevel * 2 - available;
    return suggestion < 1 ? 1 : suggestion;
  }

  /// Colour rule from B5: expired is danger, under 30 days is warning, under
  /// the configured alert window is gold, anything else is neutral.
  static ExpiryTone expiryTone(int daysLeft, {required int alertDays}) {
    if (daysLeft < 0) return ExpiryTone.danger;
    if (daysLeft < 30) return ExpiryTone.warning;
    if (daysLeft <= alertDays) return ExpiryTone.gold;
    return ExpiryTone.ok;
  }

  /// One status chip for the stock overview. Expired stock takes precedence.
  static StockStatus status({
    required int available,
    required int expiredQty,
    required int reorderLevel,
    required int daysToNearestExpiry,
    required int alertDays,
  }) {
    if (expiredQty > 0) return StockStatus.expired;
    if (available <= 0) return StockStatus.outOfStock;
    if (daysToNearestExpiry < 0) return StockStatus.expired;
    if (daysToNearestExpiry <= alertDays) return StockStatus.expiringSoon;
    if (available <= reorderLevel) return StockStatus.low;
    return StockStatus.inStock;
  }

  static String label(StockStatus status) => switch (status) {
        StockStatus.inStock => 'In stock',
        StockStatus.low => 'Low',
        StockStatus.outOfStock => 'Out of stock',
        StockStatus.expiringSoon => 'Expiring soon',
        StockStatus.expired => 'Expired',
      };

  /// Live stock-take variance: counted minus what the system says is on hand.
  static int variance({required int counted, required int systemQty}) =>
      counted - systemQty;

  /// The adjustment change sent to `adjust_stock` to reconcile a batch.
  static int adjustmentFor({required int counted, required int systemQty}) =>
      variance(counted: counted, systemQty: systemQty);
}
