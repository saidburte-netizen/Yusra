import 'package:go_router/go_router.dart';

import 'screens/customers_screen.dart';

final List<RouteBase> customersRoutes = [
  GoRoute(
    path: '/customers',
    builder: (context, state) => const CustomersScreen(),
  ),
  GoRoute(
    path: '/customers/:id',
    builder: (context, state) => CustomerDetailScreen(
      id: state.pathParameters['id'] ?? '',
    ),
  ),
];
