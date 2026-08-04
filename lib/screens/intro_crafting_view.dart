import 'package:flutter/widgets.dart';
import '../l10n/app_localizations.dart';

import '../ui/fm_card.dart';
import '../ui/fm_column_box.dart';
import '../ui/fm_row_box.dart';
import '../ui/fm_square_button.dart';
import '../ui/fm_circular_button.dart';
import '../ui/fm_bevelled_button.dart';
import '../ui/fm_hexagonal_button.dart';
import '../ui/fm_slider.dart';
import '../ui/fm_dev_back_button.dart';

class IntroCraftingView extends StatefulWidget {
  const IntroCraftingView({super.key});

  @override
  State<IntroCraftingView> createState() => _IntroCraftingViewState();
}

class _IntroCraftingViewState extends State<IntroCraftingView> {
  double _sliderValue = 0.5;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Stack(
      children: [
        ColoredBox(
          color: const Color(0xFF111111),
          child: Center(
            child: FmCard(
              tooltip: l10n.crafting,
              child: FmColumnBox(
                children: [
                  Text(
                    l10n.crafting,
                    style: const TextStyle(
                      color: Color(0xFFFFFFFF),
                      fontSize: 20,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 16),
                  FmRowBox(
                    children: [
                      FmSquareButton(
                        icon: const IconData(0xe145, fontFamily: 'MaterialIcons'),
                        tooltip: 'Square',
                        onPressed: () {},
                      ),
                      const SizedBox(width: 8),
                      FmCircularButton(
                        icon: const IconData(0xe3c9, fontFamily: 'MaterialIcons'),
                        tooltip: 'Circle',
                        onPressed: () {},
                      ),
                      const SizedBox(width: 8),
                      FmBevelledButton(
                        icon: const IconData(0xe8b8, fontFamily: 'MaterialIcons'),
                        tooltip: 'Bevelled',
                        onPressed: () {},
                      ),
                      const SizedBox(width: 8),
                      FmHexagonalButton(
                        icon: const IconData(0xe55b, fontFamily: 'MaterialIcons'),
                        tooltip: 'Hexagon',
                        onPressed: () {},
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  FmSlider(
                    value: _sliderValue,
                    onChanged: (v) => setState(() => _sliderValue = v),
                    tooltip: 'Adjust',
                  ),
                ],
              ),
            ),
          ),
        ),
        const FmDevBackButton(),
      ],
    );
  }
}
