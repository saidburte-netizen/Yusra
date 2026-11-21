// Device-persisted held carts. A dropped network or an accidental app restart
// never loses the cashier's work.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'cart.dart';

class HeldCart {
  const HeldCart({
    required this.id,
    required this.label,
    required this.savedAt,
    required this.cart,
  });

  final String id;
  final String label;
  final DateTime savedAt;
  final Cart cart;

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'saved_at': savedAt.toIso8601String(),
        'cart': cart.toJson(),
      };

  factory HeldCart.fromJson(Map<String, dynamic> json) => HeldCart(
        id: (json['id'] as String?) ?? '',
        label: (json['label'] as String?) ?? 'Held cart',
        savedAt: DateTime.tryParse(json['saved_at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        cart: Cart.fromJson(
            Map<String, dynamic>.from(json['cart'] as Map? ?? {})),
      );
}

class HeldCartStore {
  HeldCartStore(this._prefs);
  final SharedPreferences _prefs;

  static const key = 'yusra.pos.held_carts';
  static const draftKey = 'yusra.pos.draft_cart';

  List<HeldCart> list() {
    final raw = _prefs.getString(key);
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded
          .map((item) =>
              HeldCart.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(HeldCart held) async {
    final items = list().where((item) => item.id != held.id).toList()
      ..add(held);
    await _prefs.setString(
        key, jsonEncode(items.map((item) => item.toJson()).toList()));
  }

  Future<void> delete(String id) async {
    final items = list().where((item) => item.id != id).toList();
    await _prefs.setString(
        key, jsonEncode(items.map((item) => item.toJson()).toList()));
  }

  Future<void> saveDraft(Cart cart) =>
      _prefs.setString(draftKey, jsonEncode(cart.toJson()));

  Cart loadDraft() {
    final raw = _prefs.getString(draftKey);
    if (raw == null) return const Cart();
    try {
      return Cart.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      return const Cart();
    }
  }

  Future<void> clearDraft() => _prefs.remove(draftKey);
}
