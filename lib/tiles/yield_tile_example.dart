// Example usage of the YieldTileFeature system
// This file demonstrates how to work with material yields

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../tiles/tiles.dart';

const Map<String, Color> _exampleColors = {
  'fm-copper': Color(0xFFD4824F),
  'fm-wood': Color(0xFF795548),
  'fm-clay': Color(0xFFBF8040),
};

/// Example: Creating a tile with material yields
YieldTileFeature createExampleTile() {
  final yields = [
    const MaterialYield(materialId: 'fm-copper', amount: 70),
    const MaterialYield(materialId: 'fm-wood', amount: 30),
  ];

  final dominantColor =
      _exampleColors['fm-copper'] ?? const Color(0xFF6B6B6B);

  return YieldTileFeature(
    id: 'example-tile',
    yields: yields,
    edgeSize: 220,
    height: 18,
    color: dominantColor,
    elevation: 0,
  );
}

/// Example: Modifying yields on a tile
YieldTileFeature incrementMaterial(
  YieldTileFeature tile,
  String materialId,
  int amount,
) {
  final updatedYields = tile.yields.map((yield) {
    if (yield.materialId == materialId) {
      final newAmount = (yield.amount + amount).clamp(0, 100);
      return yield.copyWith(amount: newAmount);
    }
    return yield;
  }).toList();

  final newDominant = updatedYields
      .reduce((a, b) => a.amount > b.amount ? a : b)
      .materialId;

  if (newDominant != tile.dominantMaterialId) {
    final newColor =
        _exampleColors[newDominant] ?? const Color(0xFF6B6B6B);
    return tile.copyWithYields(updatedYields).copyWithColor(newColor);
  }

  return tile.copyWithYields(updatedYields);
}

/// Example: Transferring material between tiles
(YieldTileFeature, YieldTileFeature) transferMaterial(
  YieldTileFeature source,
  YieldTileFeature destination,
  String materialId,
  int amount,
) {
  final newSource = incrementMaterial(source, materialId, -amount);
  final newDestination = incrementMaterial(destination, materialId, amount);
  return (newSource, newDestination);
}

/// Example: Getting material information
void printTileInfo(YieldTileFeature tile) {
  print('Tile ${tile.id}:');
  print('  Dominant Material: ${tile.dominantMaterialId}');
  for (final yield in tile.yields) {
    print('    - ${yield.materialId}: ${yield.amount}');
  }
}

/// Example: Creating a tile with specific material distribution
YieldTileFeature createResourceRichTile(String primaryId) {
  return YieldTileFeature(
    id: 'resource-rich-tile',
    yields: [
      MaterialYield(materialId: primaryId, amount: 90),
    ],
    edgeSize: 220,
    height: 18,
    color: _exampleColors[primaryId] ?? const Color(0xFF6B6B6B),
    elevation: 0,
  );
}

/// Example: Checking if a tile has enough of a material
bool hasEnoughMaterial(
  YieldTileFeature tile,
  String materialId,
  int required,
) {
  return tile.getYieldFor(materialId) >= required;
}

/// Example: Get all materials on a tile above a threshold
List<String> getMaterialsAboveThreshold(
  YieldTileFeature tile,
  int threshold,
) {
  return tile.yields
      .where((yield) => yield.amount >= threshold)
      .map((yield) => yield.materialId)
      .toList();
}
