import 'package:flutter/material.dart';

import '../../crafting/placed_paper.dart';
import '../../gameplay/volumes/volume_program.dart';

/// Thin vertical tool strip, matching mixed-3D / crafting HUD chrome.
class GameToolSidebar extends StatelessWidget {
  const GameToolSidebar({
    super.key,
    required this.volumesActive,
    required this.onToggleVolumes,
    required this.pathsActive,
    required this.onTogglePaths,
    required this.wallsActive,
    required this.onToggleWalls,
    required this.eraserActive,
    required this.onToggleEraser,
    required this.onIsolate,
    this.showShapeButton = false,
    this.onVolumeShape,
  });

  final bool volumesActive;
  final VoidCallback onToggleVolumes;
  final bool pathsActive;
  final VoidCallback onTogglePaths;
  final bool wallsActive;
  final VoidCallback onToggleWalls;
  final bool eraserActive;
  final VoidCallback onToggleEraser;
  final VoidCallback onIsolate;
  final bool showShapeButton;
  final VoidCallback? onVolumeShape;

  @override
  Widget build(BuildContext context) {
    return _ToolStrip(
      children: [
        _ToolBtn(
          icon: Icons.filter_center_focus,
          tooltip: 'Isolate 3D',
          active: false,
          onTap: onIsolate,
        ),
        const SizedBox(height: 2),
        _ToolBtn(
          icon: Icons.add_box,
          tooltip: 'Volumes',
          active: volumesActive,
          onTap: onToggleVolumes,
        ),
        const SizedBox(height: 2),
        _ToolBtn(
          icon: Icons.add_road,
          tooltip: 'Paths',
          active: pathsActive,
          onTap: onTogglePaths,
        ),
        const SizedBox(height: 2),
        _ToolBtn(
          icon: Icons.fence,
          tooltip: 'Walls',
          active: wallsActive,
          onTap: onToggleWalls,
        ),
        const SizedBox(height: 2),
        _ToolBtn(
          icon: Icons.auto_fix_off,
          tooltip: 'Eraser',
          active: eraserActive,
          onTap: onToggleEraser,
        ),
        if (showShapeButton) ...[
          const SizedBox(height: 2),
          _ToolBtn(
            icon: Icons.crop_square,
            tooltip: 'Volume shape',
            active: false,
            onTap: onVolumeShape,
          ),
        ],
      ],
    );
  }
}

class GamePlane2dSidebar extends StatelessWidget {
  const GamePlane2dSidebar({
    super.key,
    required this.paintActive,
    required this.onTogglePaint,
    required this.fillActive,
    required this.onToggleFill,
    required this.eraseActive,
    required this.onToggleErase,
    required this.paintColor,
    required this.onPaintColor,
    required this.telephoto,
    required this.onToggleTelephoto,
    this.resolvePaper,
  });

  final bool paintActive;
  final VoidCallback onTogglePaint;
  final bool fillActive;
  final VoidCallback onToggleFill;
  final bool eraseActive;
  final VoidCallback onToggleErase;
  final PaperColor paintColor;
  final ValueChanged<PaperColor> onPaintColor;
  final bool telephoto;
  final VoidCallback onToggleTelephoto;
  final Color Function(PaperColor)? resolvePaper;

  @override
  Widget build(BuildContext context) {
    return _ToolStrip(
      children: [
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
        if (paintActive || fillActive) ...[
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
    );
  }
}

/// Separate bubble above the right tool strip to leave plane2d.
class GameInteriorSidebar extends StatelessWidget {
  const GameInteriorSidebar({
    super.key,
    required this.kind,
    required this.onKind,
  });

  final VolumeProgramKind kind;
  final ValueChanged<VolumeProgramKind> onKind;

  @override
  Widget build(BuildContext context) {
    return _ToolStrip(
      children: [
        for (final value in VolumeProgramKind.values) ...[
          if (value != VolumeProgramKind.values.first) const SizedBox(height: 2),
          Tooltip(
            message: value.label,
            child: _ColorDot(
              color: Color(value.paperArgb),
              selected: kind == value,
              onTap: () => onKind(value),
            ),
          ),
        ],
      ],
    );
  }
}

class GameFaceFocusSidebar extends StatelessWidget {
  const GameFaceFocusSidebar({super.key});

  @override
  Widget build(BuildContext context) {
    return _ToolStrip(
      children: [
        Tooltip(
          message: 'Door 2×4',
          child: _ColorDot(
            color: const Color(0xFFF7F7F2),
            selected: true,
            onTap: () {},
          ),
        ),
      ],
    );
  }
}

class GameViewerBackButton extends StatelessWidget {
  const GameViewerBackButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return _ToolStrip(
      children: [
        _ToolBtn(
          icon: Icons.arrow_back,
          tooltip: 'Return to map',
          active: false,
          onTap: onPressed,
        ),
      ],
    );
  }
}

class _ToolStrip extends StatelessWidget {
  const _ToolStrip({required this.children});

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

/// Left-hand layer toggles (connection graph, etc.).
class GameLayerSidebar extends StatelessWidget {
  const GameLayerSidebar({
    super.key,
    required this.graphActive,
    required this.onToggleGraph,
    this.onPopulateRecording,
    this.onSaveRecording,
    this.canSaveRecording = false,
  });

  final bool graphActive;
  final VoidCallback onToggleGraph;
  final VoidCallback? onPopulateRecording;
  final VoidCallback? onSaveRecording;
  final bool canSaveRecording;

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
        children: [
          _ToolBtn(
            icon: Icons.hub,
            tooltip: 'Connection graph',
            active: graphActive,
            onTap: onToggleGraph,
          ),
          if (onPopulateRecording != null) ...[
            const SizedBox(height: 2),
            _ToolBtn(
              icon: Icons.holiday_village,
              tooltip: 'Populate recording',
              active: false,
              onTap: onPopulateRecording,
            ),
          ],
          if (onSaveRecording != null) ...[
            const SizedBox(height: 2),
            _ToolBtn(
              icon: Icons.save_alt,
              tooltip: canSaveRecording
                  ? 'Save recording'
                  : 'Save recording (no changes)',
              active: false,
              onTap: canSaveRecording ? onSaveRecording : null,
            ),
          ],
        ],
      ),
    );
  }
}

/// Focus3d crop tool. Reset flies out beside the crop button without widening
/// the sidebar column.
class GameFocus3dSidebar extends StatelessWidget {
  const GameFocus3dSidebar({
    super.key,
    required this.cropActive,
    required this.onToggleCrop,
    required this.showReset,
    required this.onReset,
  });

  final bool cropActive;
  final VoidCallback onToggleCrop;
  final bool showReset;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          _ToolStrip(
            children: [
              _ToolBtn(
                icon: Icons.crop_free,
                tooltip: 'Crop box',
                active: cropActive,
                onTap: onToggleCrop,
              ),
            ],
          ),
          if (showReset)
            Positioned(
              top: 4,
              right: 44,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ToolBtn(
                      icon: Icons.restart_alt,
                      tooltip: 'Reset crop',
                      active: false,
                      onTap: onReset,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class GameViewRotateButton extends StatelessWidget {
  const GameViewRotateButton({
    super.key,
    required this.clockwise,
    required this.onPressed,
  });

  final bool clockwise;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return _HudCircleButton(
      icon: clockwise ? Icons.rotate_right : Icons.rotate_left,
      tooltip: clockwise ? 'Rotate right' : 'Rotate left',
      color: Colors.white,
      onPressed: onPressed,
    );
  }
}

class GameViewUndoRedoBar extends StatelessWidget {
  const GameViewUndoRedoBar({
    super.key,
    required this.canUndo,
    required this.canRedo,
    required this.onUndo,
    required this.onRedo,
  });

  final bool canUndo;
  final bool canRedo;
  final VoidCallback onUndo;
  final VoidCallback onRedo;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.undo, size: 22),
            color: canUndo ? Colors.white : Colors.white24,
            tooltip: 'Undo',
            onPressed: canUndo ? onUndo : null,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
          IconButton(
            icon: const Icon(Icons.redo, size: 22),
            color: canRedo ? Colors.white : Colors.white24,
            tooltip: 'Redo',
            onPressed: canRedo ? onRedo : null,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
        ],
      ),
    );
  }
}

class VolumeCancelButton extends StatelessWidget {
  const VolumeCancelButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return _HudCircleButton(
      icon: Icons.close,
      tooltip: 'Cancel',
      color: Colors.grey.shade500,
      onPressed: onPressed,
    );
  }
}

class VolumeConfirmButton extends StatelessWidget {
  const VolumeConfirmButton({
    super.key,
    required this.onPressed,
    this.enabled = true,
  });

  final VoidCallback? onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return _HudCircleButton(
      icon: Icons.check,
      tooltip: 'OK',
      color: enabled ? const Color(0xFF69F0AE) : Colors.white24,
      onPressed: enabled ? onPressed : null,
    );
  }
}

class _HudCircleButton extends StatelessWidget {
  const _HudCircleButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black.withValues(alpha: 0.7),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(icon, color: color, size: 26),
          ),
        ),
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
  });

  final IconData icon;
  final String tooltip;
  final bool active;
  final VoidCallback? onTap;

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
              color: onTap == null
                  ? Colors.white24
                  : active
                      ? Colors.white
                      : Colors.white70,
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
