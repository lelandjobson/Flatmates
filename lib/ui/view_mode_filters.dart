import 'package:flutter/material.dart';

/// Visual settings for a single element category (opacity, brightness, saturation).
class ElementVisualSettings {
  ElementVisualSettings({
    this.opacity = 1.0,
    this.brightness = 1.0,
    this.saturation = 1.0,
  });

  double opacity;
  double brightness;
  double saturation;

  ElementVisualSettings copy() => ElementVisualSettings(
    opacity: opacity,
    brightness: brightness,
    saturation: saturation,
  );
}

/// The categories of visual elements that can be independently controlled.
enum ElementCategory {
  friends('Friends'),
  structures('Structures'),
  tileDecorations('Tile Decorations'),
  tiles('Tiles'),
  tileIcons('Tile Icons'),
  statusUi('Status UI');

  const ElementCategory(this.label);
  final String label;
}

/// Filter settings for a single view mode — per-element-type opacity,
/// brightness, and saturation controls.
class ViewModeFilters {
  ViewModeFilters()
      : _settings = {
          ElementCategory.friends: ElementVisualSettings(opacity: 0.75),
          ElementCategory.structures: ElementVisualSettings(),
          ElementCategory.tileDecorations: ElementVisualSettings(),
          ElementCategory.tiles: ElementVisualSettings(opacity: 1.0),
          ElementCategory.tileIcons: ElementVisualSettings(opacity: 0.0),
          ElementCategory.statusUi: ElementVisualSettings(),
        };

  final Map<ElementCategory, ElementVisualSettings> _settings;

  ElementVisualSettings operator [](ElementCategory cat) => _settings[cat]!;

  ViewModeFilters copy() {
    final c = ViewModeFilters();
    for (final cat in ElementCategory.values) {
      final src = _settings[cat]!;
      c._settings[cat] = src.copy();
    }
    return c;
  }
}

/// Manages per-mode filter settings.
class ViewModeFilterSet {
  final Map<String, ViewModeFilters> _filters = {
    'friends': ViewModeFilters(),
    'tasks': ViewModeFilters(),
    'planning': ViewModeFilters(),
    'crafting': ViewModeFilters(),
  };

  ViewModeFilters forMode(String mode) => _filters[mode] ?? ViewModeFilters();
}

/// A floating panel exposing per-element sliders for the current view mode.
class ViewModeFilterPanel extends StatefulWidget {
  const ViewModeFilterPanel({
    super.key,
    required this.modeName,
    required this.filters,
    required this.onChanged,
    required this.onClose,
  });

  final String modeName;
  final ViewModeFilters filters;
  final VoidCallback onChanged;
  final VoidCallback onClose;

  @override
  State<ViewModeFilterPanel> createState() => _ViewModeFilterPanelState();
}

class _ViewModeFilterPanelState extends State<ViewModeFilterPanel> {
  ElementCategory? _expandedCategory;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withOpacity(0.85),
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 260,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'View Filters — ${widget.modeName[0].toUpperCase()}${widget.modeName.substring(1)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: widget.onClose,
                    child: const Icon(
                      Icons.close,
                      color: Colors.white54,
                      size: 18,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              for (final cat in ElementCategory.values)
                _buildCategorySection(cat),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategorySection(ElementCategory cat) {
    final isExpanded = _expandedCategory == cat;
    final settings = widget.filters[cat];
    final isDefault = settings.opacity == 1.0 &&
        settings.brightness == 1.0 &&
        settings.saturation == 1.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () {
            setState(() {
              _expandedCategory = isExpanded ? null : cat;
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(
                  isExpanded ? Icons.expand_more : Icons.chevron_right,
                  color: Colors.white54,
                  size: 16,
                ),
                const SizedBox(width: 4),
                Text(
                  cat.label,
                  style: TextStyle(
                    color: isDefault ? Colors.white70 : Colors.cyanAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (!isDefault) ...[
                  const Spacer(),
                  GestureDetector(
                    onTap: () {
                      settings.opacity = 1.0;
                      settings.brightness = 1.0;
                      settings.saturation = 1.0;
                      widget.onChanged();
                    },
                    child: const Icon(
                      Icons.replay,
                      color: Colors.white38,
                      size: 14,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (isExpanded) ...[
          _buildSlider('Opacity', settings.opacity, (v) {
            settings.opacity = v;
            widget.onChanged();
          }),
          _buildSlider('Brightness', settings.brightness, (v) {
            settings.brightness = v;
            widget.onChanged();
          }),
          _buildSlider('Saturation', settings.saturation, (v) {
            settings.saturation = v;
            widget.onChanged();
          }),
          const SizedBox(height: 4),
        ],
      ],
    );
  }

  Widget _buildSlider(
    String label,
    double value,
    ValueChanged<double> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(left: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ${(value * 100).round()}%',
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 2,
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 6),
              activeTrackColor: Colors.cyanAccent,
              inactiveTrackColor: Colors.white24,
              thumbColor: Colors.cyanAccent,
              overlayColor: Colors.cyanAccent.withOpacity(0.15),
            ),
            child: Slider(
              value: value,
              min: 0.0,
              max: 1.0,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
