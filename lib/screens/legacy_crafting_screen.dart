import 'package:flutter/material.dart';

import '../data/crafting_state.dart';
import '../ui/crafting_workstation.dart';
import '../ui/fm_screen.dart';

class LegacyCraftingScreen extends StatefulWidget {
  const LegacyCraftingScreen({super.key});

  @override
  State<LegacyCraftingScreen> createState() => _LegacyCraftingScreenState();
}

class _LegacyCraftingScreenState extends State<LegacyCraftingScreen> {
  final CraftingStateStore _stateStore = CraftingStateStore();

  @override
  Widget build(BuildContext context) {
    return FmScreen(
      backgroundColor: const Color(0xFF1A1A2E),
      // The workstation is full-bleed; its HUD applies safe insets per element.
      background: CraftingTestView(
        structureId: 'legacy-test-structure',
        stateStore: _stateStore,
        canvasSize: 400.0,
        hideDrawingPlane: false,
        showDotWipe: false,
        onDismiss: () => Navigator.of(context).maybePop(),
      ),
    );
  }
}
