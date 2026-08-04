import 'package:flutter/material.dart';

/// Represents a material type used in the crafting canvas, replacing the old
/// fixed PaperColor enum. Each material maps to a game material ID from the
/// tile yield / crafts system.
class CraftingMaterial {
  const CraftingMaterial({
    required this.materialId,
    required this.color,
    required this.label,
  });

  final String materialId;
  final Color color;
  final String label;

  /// An 8x8 paper consumes this many material units.
  static const int pixelsPerSheet = 64;

  /// Each gather action yields this many material units.
  static const int unitsPerGather = 16;

  /// Max units of a single material in one inventory slot.
  static const int maxPerSlot = 1000;

  /// Paper dimensions in grid cells.
  static const int paperSizeCells = 8;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CraftingMaterial && materialId == other.materialId;

  @override
  int get hashCode => materialId.hashCode;

  @override
  String toString() => 'CraftingMaterial($materialId)';
}

/// Registry that resolves material IDs to crafting-usable materials.
/// Reads colors from a provider map (typically CraftsTechProvider.materialIdToColor).
class CraftingMaterialRegistry {
  CraftingMaterialRegistry({
    Map<String, Color> colorMap = const {},
  }) : _colorMap = colorMap;

  final Map<String, Color> _colorMap;

  static const Color _defaultGrey = Color(0xFF6B6B6B);

  static const Map<String, Color> _fallbackPalette = {
    'fm-clay': Color(0xFFCC8855),
    'fm-coal': Color(0xFF444444),
    'fm-cotton': Color(0xFFF5F0E0),
    'fm-sand': Color(0xFFE8D44D),
    'fm-logs': Color(0xFF7B4A2B),
    'fm-iron-ore': Color(0xFFB85C3A),
    'fm-fabric-dye': Color(0xFF5B8DC9),
    'fm-foam-rubber': Color(0xFF66BB6A),
  };

  Color colorFor(String materialId) =>
      _colorMap[materialId] ?? _fallbackPalette[materialId] ?? _defaultGrey;

  String labelFor(String materialId) {
    final name = materialId.startsWith('fm-')
        ? materialId.substring(3)
        : materialId;
    return name.split('-').map((w) => w.isNotEmpty
        ? '${w[0].toUpperCase()}${w.substring(1)}'
        : w).join(' ');
  }

  CraftingMaterial resolve(String materialId) => CraftingMaterial(
        materialId: materialId,
        color: colorFor(materialId),
        label: labelFor(materialId),
      );

  /// Default raw material IDs available when no crafts are loaded.
  static const List<String> defaultMaterialIds = [
    'fm-clay',
    'fm-coal',
    'fm-cotton',
    'fm-sand',
    'fm-logs',
    'fm-iron-ore',
    'fm-fabric-dye',
    'fm-foam-rubber',
  ];
}
