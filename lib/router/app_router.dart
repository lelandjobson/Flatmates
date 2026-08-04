import 'package:go_router/go_router.dart';

import '../screens/dev_routes_screen.dart';
import '../screens/gesture_system_view.dart';
import '../screens/legacy_crafting_screen.dart';
import '../screens/loading_screen.dart';
import '../screens/main_menu_screen.dart';
import '../screens/intro_screen.dart';
import '../screens/intro_crafting_view.dart';

/// Swap between '/dev-routes' and '/' to start at the dev menu or title screen.
const kInitialLocation = '/dev-routes';

final router = GoRouter(
  initialLocation: kInitialLocation,
  routes: [
    GoRoute(
      path: '/dev-routes',
      name: 'dev_routes',
      builder: (context, state) => const DevRoutesScreen(),
    ),
    GoRoute(
      path: '/',
      name: 'loading',
      builder: (context, state) => const LoadingScreen(),
    ),
    GoRoute(
      path: '/main-menu',
      name: 'main_menu',
      builder: (context, state) => const MainMenuScreen(),
    ),
    GoRoute(
      path: '/intro',
      name: 'intro',
      builder: (context, state) => const IntroScreen(),
    ),
    GoRoute(
      path: '/intro-crafting',
      name: 'intro_crafting',
      builder: (context, state) => const IntroCraftingView(),
    ),
    GoRoute(
      path: '/gesture-system',
      name: 'gesture_system',
      builder: (context, state) => const GestureSystemView(),
    ),
    GoRoute(
      path: '/legacy-crafting',
      name: 'legacy_crafting',
      builder: (context, state) => const LegacyCraftingScreen(),
    ),
  ],
);
