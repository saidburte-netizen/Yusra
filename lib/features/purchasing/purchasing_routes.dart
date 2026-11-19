import 'package:go_router/go_router.dart';

import '../../core/widgets/feedback.dart';

/// Route stub created by Agent A. The owning agent overwrites this file.
final List<RouteBase> purchasingRoutes = [
  GoRoute(
    path: '/purchasing/orders',
    builder: (context, state) =>
        const ComingSoonScreen(title: 'Purchasing'),
  ),
  GoRoute(
    path: '/purchasing/orders/new',
    builder: (context, state) =>
        const ComingSoonScreen(title: 'Purchasing — new'),
  ),
  GoRoute(
    path: '/purchasing/orders/:id',
    builder: (context, state) =>
        const ComingSoonScreen(title: 'Purchasing — id'),
  ),
];
