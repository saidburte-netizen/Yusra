import 'package:go_router/go_router.dart';

import 'screens/suppliers_screen.dart';

/// Agent B owns this file.
final List<RouteBase> suppliersRoutes = [
  GoRoute(
    path: '/suppliers',
    builder: (context, state) => const SuppliersScreen(),
  ),
  GoRoute(
    path: '/suppliers/:id',
    builder: (context, state) => SupplierDetailScreen(
      supplierId: state.pathParameters['id'] ?? '',
    ),
  ),
];
