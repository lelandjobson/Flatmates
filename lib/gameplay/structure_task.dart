import 'package:flutter/material.dart';

import 'inventory.dart';

/// Status codes returned by a [StructureTask] when evaluated.
enum StructureTaskStatus { awaiting, ready, complete, failed }

/// A UI action surfaced by a task evaluation (e.g. "BUILD" button).
class TaskAction {
  const TaskAction({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
}

/// The result of evaluating a [StructureTask] against a structure's current
/// inventory. Contains the status and any UI actions the task makes available.
class StructureTaskResult {
  const StructureTaskResult({
    required this.status,
    this.actions = const [],
    this.progress = 0.0,
  });

  final StructureTaskStatus status;
  final List<TaskAction> actions;

  /// 0.0–1.0 progress towards readiness.
  final double progress;
}

/// Base class for tasks assignable to a structure.
///
/// Concrete implementations (e.g. [BlueprintTask]) override [evaluate] to
/// inspect the structure's inventory and return the current status plus any
/// available actions. [execute] performs the task's final action (consuming
/// ingredients, producing results, etc.).
abstract class StructureTask {
  String get id;
  String get displayName;
  Color? get iconColor;

  /// Inspect [structureInventory] and return the current status and available
  /// actions. This is called whenever the structure's state changes.
  StructureTaskResult evaluate(Inventory structureInventory);

  /// Perform the task's final action. Implementations should consume
  /// ingredients from [structureInventory] and place results into either the
  /// structure or [playerInventory] if the structure is full.
  void execute(Inventory structureInventory, Inventory playerInventory);
}
