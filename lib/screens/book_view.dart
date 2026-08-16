import 'package:flutter/material.dart';

import '../ui/book/book_widget.dart';
import '../ui/book/void_background.dart';
import '../ui/fm_dev_back_button.dart';
import '../ui/fm_screen.dart';

/// Myst-style interactive book demo (imported from sfapp).
class BookView extends StatelessWidget {
  const BookView({super.key});

  @override
  Widget build(BuildContext context) {
    return FmScreen(
      backgroundColor: Colors.black,
      background: const Stack(
        fit: StackFit.expand,
        children: [
          VoidBackground(),
          BookWidget(),
        ],
      ),
      overlays: const [FmDevBackButton()],
    );
  }
}
