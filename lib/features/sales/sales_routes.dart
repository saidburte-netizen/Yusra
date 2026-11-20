import 'package:go_router/go_router.dart';

import 'screens/returns_screen.dart';
import 'screens/sale_detail_screen.dart';
import 'screens/sales_screen.dart';

final List<RouteBase> salesRoutes = [
  GoRoute(
    path: '/sales',
    builder: (context, state) => const SalesScreen(),
  ),
  // Static paths must come before the :id parameter or "returns" is read as
  // an invoice id.
  GoRoute(
    path: '/sales/returns',
    builder: (context, state) => const ReturnsScreen(),
  ),
  GoRoute(
    path: '/sales/:id',
    builder: (context, state) => SaleDetailScreen(
      id: state.pathParameters['id'] ?? '',
    ),
  ),
];
