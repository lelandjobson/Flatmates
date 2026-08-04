import 'package:flutter/foundation.dart';

import '../data/placed_asset_database.dart';
import 'structure_task.dart';

/// Manages one [StructureTask] per structure.
///
/// Replaces the ad-hoc `_blueprintAssignments` map that previously lived in
/// `MapViewIso`. Notifies listeners whenever a task is assigned or cleared.
class StructureTaskManager extends ChangeNotifier {
  final Map<PlacedAssetId, StructureTask> _tasks = {};

  /// All current task assignments.
  Map<PlacedAssetId, StructureTask> get tasks => Map.unmodifiable(_tasks);

  /// Get the task assigned to [structureId], if any.
  StructureTask? getTask(PlacedAssetId structureId) => _tasks[structureId];

  /// Get the task assigned to the structure at tile key [tileKey], if any.
  StructureTask? getTaskByTileKey(String tileKey) {
    for (final entry in _tasks.entries) {
      if (entry.key == tileKey) return entry.value;
    }
    return null;
  }

  /// Assign [task] to [structureId], replacing any existing task.
  void assignTask(PlacedAssetId structureId, StructureTask task) {
    _tasks[structureId] = task;
    notifyListeners();
  }

  /// Clear the task assigned to [structureId].
  void clearTask(PlacedAssetId structureId) {
    if (_tasks.remove(structureId) != null) {
      notifyListeners();
    }
  }

  /// Whether [structureId] has an assigned task.
  bool hasTask(PlacedAssetId structureId) => _tasks.containsKey(structureId);
}
