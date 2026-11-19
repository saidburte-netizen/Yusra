import 'package:go_router/go_router.dart';

import '../../core/widgets/feedback.dart';

/// Route stub created by Agent A. The owning agent overwrites this file.
final List<RouteBase> customersRoutes = [
  GoRoute(
    path: '/customers',
    builder: (context, state) =>
        const ComingSoonScreen(title: 'Customers'),
  ),
  GoRoute(
    path: '/customers/:id',
    builder: (context, state) =>
        const ComingSoonScreen(title: 'Customers — id'),
  ),
];
