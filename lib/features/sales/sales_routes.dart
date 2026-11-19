import 'package:go_router/go_router.dart';

import '../../core/widgets/feedback.dart';

/// Route stub created by Agent A. The owning agent overwrites this file.
final List<RouteBase> salesRoutes = [
  GoRoute(
    path: '/sales',
    builder: (context, state) =>
        const ComingSoonScreen(title: 'Sales history'),
  ),
  GoRoute(
    path: '/sales/:id',
    builder: (context, state) =>
        const ComingSoonScreen(title: 'Sales history — id'),
  ),
  GoRoute(
    path: '/sales/returns',
    builder: (context, state) =>
        const ComingSoonScreen(title: 'Sales history — returns'),
  ),
];
