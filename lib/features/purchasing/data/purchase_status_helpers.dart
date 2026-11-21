/// Ordered RPC fallbacks for a purchase-order status change.
///
/// Kept free of Supabase/Flutter imports so the fallback policy can be unit
/// tested. `set_purchase_order_status` is tried first; the legacy
/// approve/cancel functions are only used when the server reports that the
/// first function does not exist (PGRST202).
List<String> purchaseStatusRpcCandidates(String status) => switch (status) {
      'ordered' => const [
          'set_purchase_order_status',
          'approve_purchase_order',
        ],
      'cancelled' => const [
          'set_purchase_order_status',
          'cancel_purchase_order',
        ],
      _ => const ['set_purchase_order_status'],
    };
