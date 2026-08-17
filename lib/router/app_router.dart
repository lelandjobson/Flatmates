import 'package:go_router/go_router.dart';

import '../screens/cards_debug_view.dart';
import '../screens/dev_routes_screen.dart';
import '../screens/gesture_system_view.dart';
import '../screens/legacy_crafting_screen.dart';
import '../screens/loading_screen.dart';
import '../screens/main_menu_screen.dart';
import '../screens/intro_screen.dart';
import '../screens/intro_crafting_view.dart';
import '../screens/mixed_3d_crafting_view.dart';
import '../screens/book_view.dart';
import '../screens/craft_assembly_view.dart';
import '../screens/craft_model_preview_view.dart';
import '../screens/landscape_tiles_debug_view.dart';
import '../screens/test_3d_map_view.dart';

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
    GoRoute(
      path: '/mixed-3d-crafting',
      name: 'mixed_3d_crafting',
      builder: (context, state) => const Mixed3dCraftingView(),
    ),
    GoRoute(
      path: '/cards-debug',
      name: 'cards_debug',
      builder: (context, state) => const CardsDebugView(),
    ),
    GoRoute(
      path: '/book',
      name: 'book',
      builder: (context, state) => const BookView(),
    ),
    GoRoute(
      path: '/craft-model-preview',
      name: 'craft_model_preview',
      builder: (context, state) => const CraftModelPreviewView(),
    ),
    GoRoute(
      path: '/craft-assembly',
      name: 'craft_assembly',
      builder: (context, state) => const CraftAssemblyView(),
    ),
    GoRoute(
      path: '/landscape-tiles-debug',
      name: 'landscape_tiles_debug',
      builder: (context, state) => const LandscapeTilesDebugView(),
    ),
    GoRoute(
      path: '/test-3d-map',
      name: 'test_3d_map',
      builder: (context, state) => const Test3dMapView(),
    ),
  ],
);
