import 'package:go_router/go_router.dart';

import '../../core/widgets/feedback.dart';

/// Route stub created by Agent A. The owning agent overwrites this file.
final List<RouteBase> suppliersRoutes = [
  GoRoute(
    path: '/suppliers',
    builder: (context, state) =>
        const ComingSoonScreen(title: 'Suppliers'),
  ),
];
