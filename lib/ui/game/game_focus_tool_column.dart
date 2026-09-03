import 'package:flutter/material.dart';

import '../../crafting/placed_paper.dart';
import '../../gameplay/picking/focus_sticker.dart';

/// Right-hand focus tools: expanding paint and sticker subcolumns.
class GameFocusToolColumn extends StatelessWidget {
  const GameFocusToolColumn({
    super.key,
    required this.surface,
    required this.paintExpanded,
    required this.onTogglePaintGroup,
    required this.stickerExpanded,
    required this.onToggleStickerGroup,
    required this.paintActive,
    required this.onTogglePaint,
    required this.fillActive,
    required this.onToggleFill,
    required this.eraseActive,
    required this.onToggleErase,
    required this.paintColor,
    required this.onPaintColor,
    required this.selectedSticker,
    required this.onSelectSticker,
    required this.telephoto,
    required this.onToggleTelephoto,
    this.resolvePaper,
  });

  final FocusWorkSurface surface;
  final bool paintExpanded;
  final VoidCallback onTogglePaintGroup;
  final bool stickerExpanded;
  final VoidCallback onToggleStickerGroup;
  final bool paintActive;
  final VoidCallback onTogglePaint;
  final bool fillActive;
  final VoidCallback onToggleFill;
  final bool eraseActive;
  final VoidCallback onToggleErase;
  final PaperColor paintColor;
  final ValueChanged<PaperColor> onPaintColor;
  final FocusStickerKind? selectedSticker;
  final ValueChanged<FocusStickerKind> onSelectSticker;
  final bool telephoto;
  final VoidCallback onToggleTelephoto;
  final Color Function(PaperColor)? resolvePaper;

  @override
  Widget build(BuildContext context) {
    final accent = focusPaintAccent(paintColor, resolvePaper);
    final stickers = focusStickersFor(surface);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Subcolumn(
          children: [
            _ToolBtn(
              icon: Icons.brush,
              tooltip: paintExpanded ? 'Collapse paint' : 'Paint tools',
              active: paintExpanded || paintActive || fillActive || eraseActive,
              onTap: onTogglePaintGroup,
              accent: accent,
            ),
            if (paintExpanded) ...[
              const SizedBox(height: 2),
              _ToolBtn(
                icon: Icons.brush,
                tooltip: 'Paint',
                active: paintActive,
                onTap: onTogglePaint,
              ),
              const SizedBox(height: 2),
              _ToolBtn(
                icon: Icons.format_color_fill,
                tooltip: 'Fill',
                active: fillActive,
                onTap: onToggleFill,
              ),
              const SizedBox(height: 2),
              _ToolBtn(
                icon: Icons.auto_fix_off,
                tooltip: 'Erase',
                active: eraseActive,
                onTap: onToggleErase,
              ),
              for (final color in PaperColor.values) ...[
                const SizedBox(height: 2),
                _ColorDot(
                  color: resolvePaper?.call(color) ?? color.color,
                  selected: paintColor == color,
                  onTap: () => onPaintColor(color),
                ),
              ],
            ],
            const SizedBox(height: 2),
            _ToolBtn(
              icon: telephoto ? Icons.crop_square : Icons.videocam,
              tooltip: telephoto ? 'Perspective' : 'Telephoto',
              active: telephoto,
              onTap: onToggleTelephoto,
            ),
          ],
        ),
        if (stickers.isNotEmpty) ...[
          const SizedBox(width: 6),
          _Subcolumn(
            children: [
              _ToolBtn(
                icon: Icons.sticky_note_2_outlined,
                tooltip: stickerExpanded ? 'Collapse stickers' : 'Stickers',
                active: stickerExpanded || selectedSticker != null,
                onTap: onToggleStickerGroup,
              ),
              if (stickerExpanded)
                for (final spec in stickers) ...[
                  const SizedBox(height: 2),
                  _StickerBtn(
                    spec: spec,
                    selected: selectedSticker == spec.kind,
                    onTap: () => onSelectSticker(spec.kind),
                  ),
                ],
            ],
          ),
        ],
      ],
    );
  }
}

class _Subcolumn extends StatelessWidget {
  const _Subcolumn({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}

class _ToolBtn extends StatelessWidget {
  const _ToolBtn({
    required this.icon,
    required this.tooltip,
    required this.active,
    required this.onTap,
    this.accent,
  });

  final IconData icon;
  final String tooltip;
  final bool active;
  final VoidCallback onTap;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active ? Colors.white.withValues(alpha: 0.2) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(
              icon,
              color: accent ?? (active ? Colors.white : Colors.white70),
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Paint color',
      child: Material(
        color: selected ? Colors.white.withValues(alpha: 0.2) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: SizedBox(
            width: 36,
            height: 36,
            child: Center(
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? Colors.white : Colors.white38,
                    width: selected ? 2 : 1,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StickerBtn extends StatelessWidget {
  const _StickerBtn({
    required this.spec,
    required this.selected,
    required this.onTap,
  });

  final FocusStickerSpec spec;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: spec.label,
      child: Material(
        color: selected ? Colors.white.withValues(alpha: 0.2) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: SizedBox(
            width: 36,
            height: 36,
            child: Center(
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: spec.swatch,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: selected ? Colors.white : Colors.white38,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: Icon(spec.icon, size: 14, color: const Color(0xFF5A5A5A)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
