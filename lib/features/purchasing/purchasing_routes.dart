import 'package:go_router/go_router.dart';

import 'screens/purchase_order_screen.dart';
import 'screens/purchase_orders_screen.dart';

/// Agent B owns this file.
final List<RouteBase> purchasingRoutes = [
  GoRoute(
    path: '/purchasing/orders',
    builder: (context, state) => const PurchaseOrdersScreen(),
  ),
  GoRoute(
    path: '/purchasing/orders/new',
    builder: (context, state) => const PurchaseOrderScreen(orderId: 'new'),
  ),
  GoRoute(
    path: '/purchasing/orders/:id',
    builder: (context, state) => PurchaseOrderScreen(
      orderId: state.pathParameters['id'] ?? '',
    ),
  ),
];
