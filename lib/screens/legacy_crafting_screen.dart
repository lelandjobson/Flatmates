import 'package:flutter/material.dart';

import '../data/crafting_state.dart';
import '../ui/crafting_workstation.dart';

class LegacyCraftingScreen extends StatefulWidget {
  const LegacyCraftingScreen({super.key});

  @override
  State<LegacyCraftingScreen> createState() => _LegacyCraftingScreenState();
}

class _LegacyCraftingScreenState extends State<LegacyCraftingScreen> {
  final CraftingStateStore _stateStore = CraftingStateStore();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: CraftingTestView(
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
