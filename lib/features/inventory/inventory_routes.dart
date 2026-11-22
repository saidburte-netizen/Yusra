import 'package:go_router/go_router.dart';

import 'screens/adjustments_screen.dart';
import 'screens/alerts_screen.dart';
import 'screens/batches_screen.dart';
import 'screens/categories_screen.dart';
import 'screens/medicine_detail_screen.dart';
import 'screens/medicines_screen.dart';
import 'screens/movements_screen.dart';
import 'screens/needs_ordering_screen.dart';
import 'screens/opening_stock_screen.dart';
import 'screens/stock_overview_screen.dart';
import 'screens/stocktake_screen.dart';

/// Agent B owns this file. Routes are mounted by Agent A's central router.
final List<RouteBase> inventoryRoutes = [
  GoRoute(
    path: '/inventory',
    builder: (context, state) => const StockOverviewScreen(),
  ),
  GoRoute(
    path: '/inventory/medicines',
    builder: (context, state) => const MedicinesScreen(),
  ),
  GoRoute(
    path: '/inventory/medicines/:id',
    builder: (context, state) => MedicineDetailScreen(
      medicineId: state.pathParameters['id'] ?? '',
    ),
  ),
  GoRoute(
    path: '/inventory/categories',
    builder: (context, state) => const CategoriesScreen(),
  ),
  GoRoute(
    path: '/inventory/batches',
    builder: (context, state) => const BatchesScreen(),
  ),
  GoRoute(
    path: '/inventory/opening-stock',
    builder: (context, state) => const OpeningStockScreen(),
  ),
  GoRoute(
    path: '/inventory/needs-ordering',
    builder: (context, state) => const NeedsOrderingScreen(),
  ),
  GoRoute(
    path: '/inventory/adjustments',
    builder: (context, state) => const AdjustmentsScreen(),
  ),
  GoRoute(
    path: '/inventory/movements',
    builder: (context, state) => const MovementsScreen(),
  ),
  GoRoute(
    path: '/inventory/alerts',
    builder: (context, state) => const AlertsScreen(),
  ),
  GoRoute(
    path: '/inventory/stocktake',
    builder: (context, state) => const StocktakeScreen(),
  ),
];
