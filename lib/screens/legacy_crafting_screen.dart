import 'package:flutter/material.dart';

import '../data/crafting_state.dart';
import '../ui/crafting_workstation.dart';
import '../ui/fm_dev_back_button.dart';
import '../ui/fm_screen.dart';

class LegacyCraftingScreen extends StatefulWidget {
  const LegacyCraftingScreen({super.key, this.showDrawingPlane = false});

  /// When true, shows the large grey drawing-plane square.
  final bool showDrawingPlane;

  @override
  State<LegacyCraftingScreen> createState() => _LegacyCraftingScreenState();
}

class _LegacyCraftingScreenState extends State<LegacyCraftingScreen> {
  final CraftingStateStore _stateStore = CraftingStateStore();

  @override
  Widget build(BuildContext context) {
    return FmScreen(
      backgroundColor: const Color(0xFF1A1A2E),
      // Full-bleed canvas; HUD elements inset themselves via FmSafePositioned.
      overlays: const [FmDevBackButton()],
      background: CraftingTestView(
        structureId: 'legacy-test-structure',
        stateStore: _stateStore,
        canvasSize: 400.0,
        hideDrawingPlane: !widget.showDrawingPlane,
        showDotWipe: false,
        initialBlueprintSet: 'house_foo',
      ),
    );
  }
}
