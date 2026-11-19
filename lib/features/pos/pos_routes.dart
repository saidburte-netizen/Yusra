import 'package:go_router/go_router.dart';

import '../../core/widgets/feedback.dart';

/// Route stub created by Agent A. The owning agent overwrites this file.
final List<RouteBase> posRoutes = [
  GoRoute(
    path: '/pos',
    builder: (context, state) =>
        const ComingSoonScreen(title: 'New sale'),
  ),
];
