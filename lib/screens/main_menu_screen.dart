import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../ui/fm_dev_back_button.dart';

class MainMenuScreen extends StatelessWidget {
  const MainMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: () => context.goNamed('intro'),
                  child: const Text(
                    'New Game',
                    style: TextStyle(color: Colors.white, fontSize: 18),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: null,
                  child: Text(
                    'Load Game',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.3),
                      fontSize: 18,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const FmDevBackButton(),
        ],
      ),
    );
  }
}
