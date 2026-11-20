import 'package:go_router/go_router.dart';

import 'screens/prescriptions_screen.dart';

final List<RouteBase> prescriptionsRoutes = [
  GoRoute(
    path: '/prescriptions',
    builder: (context, state) => const PrescriptionsScreen(),
  ),
];
