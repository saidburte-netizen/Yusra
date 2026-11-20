import 'package:go_router/go_router.dart';

import 'screens/pos_screen.dart';

final List<RouteBase> posRoutes = [
  GoRoute(
    path: '/pos',
    builder: (context, state) => const PosScreen(),
  ),
];
