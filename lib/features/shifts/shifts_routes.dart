import 'package:go_router/go_router.dart';

import 'screens/shifts_screen.dart';

final List<RouteBase> shiftsRoutes = [
  GoRoute(
    path: '/shifts',
    builder: (context, state) => const ShiftsScreen(),
  ),
];
