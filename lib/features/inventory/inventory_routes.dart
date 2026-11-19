import 'package:go_router/go_router.dart';

import '../../core/widgets/feedback.dart';

/// Route stub created by Agent A. The owning agent overwrites this file.
final List<RouteBase> inventoryRoutes = [
  GoRoute(
    path: '/inventory',
    builder: (context, state) =>
        const ComingSoonScreen(title: 'Inventory'),
  ),
  GoRoute(
    path: '/inventory/medicines',
    builder: (context, state) =>
        const ComingSoonScreen(title: 'Inventory — medicines'),
  ),
  GoRoute(
    path: '/inventory/medicines/:id',
    builder: (context, state) =>
        const ComingSoonScreen(title: 'Inventory — id'),
  ),
  GoRoute(
    path: '/inventory/categories',
    builder: (context, state) =>
        const ComingSoonScreen(title: 'Inventory — categories'),
  ),
  GoRoute(
    path: '/inventory/batches',
    builder: (context, state) =>
        const ComingSoonScreen(title: 'Inventory — batches'),
  ),
  GoRoute(
    path: '/inventory/adjustments',
    builder: (context, state) =>
        const ComingSoonScreen(title: 'Inventory — adjustments'),
  ),
  GoRoute(
    path: '/inventory/movements',
    builder: (context, state) =>
        const ComingSoonScreen(title: 'Inventory — movements'),
  ),
  GoRoute(
    path: '/inventory/alerts',
    builder: (context, state) =>
        const ComingSoonScreen(title: 'Inventory — alerts'),
  ),
  GoRoute(
    path: '/inventory/stocktake',
    builder: (context, state) =>
        const ComingSoonScreen(title: 'Inventory — stocktake'),
  ),
];
