import 'package:flutter/foundation.dart';

import '../data/crafting_state.dart';
import 'placed_paper.dart';

/// Immutable snapshot of the mutable crafting canvas state.
class CraftingSnapshot {
  const CraftingSnapshot({
    required this.papers,
    required this.nextPaperId,
    required this.inventory,
    required this.selectedPaperIds,
    required this.label,
    this.noOp = false,
    this.restoresOperativeOnRedo = false,
  });

  final List<CraftingPaperState> papers;
  final int nextPaperId;
  final Map<PaperColor, int> inventory;
  final Set<String> selectedPaperIds;
  final String label;
  final bool noOp;

  /// Set on snapshots stored in the redo stack: redoing restores an action
  /// that should count toward [CraftingHistory.operativeActionCount].
  final bool restoresOperativeOnRedo;

  CraftingSnapshot copyWith({
    List<CraftingPaperState>? papers,
    int? nextPaperId,
    Map<PaperColor, int>? inventory,
    Set<String>? selectedPaperIds,
    String? label,
    bool? noOp,
    bool? restoresOperativeOnRedo,
  }) {
    return CraftingSnapshot(
      papers: papers ?? this.papers,
      nextPaperId: nextPaperId ?? this.nextPaperId,
      inventory: inventory ?? this.inventory,
      selectedPaperIds: selectedPaperIds ?? this.selectedPaperIds,
      label: label ?? this.label,
      noOp: noOp ?? this.noOp,
      restoresOperativeOnRedo:
          restoresOperativeOnRedo ?? this.restoresOperativeOnRedo,
    );
  }

  factory CraftingSnapshot.capture({
    required List<PlacedPaper> papers,
    required int nextPaperId,
    required Map<PaperColor, int> inventory,
    required Set<String> selectedPaperIds,
    required String label,
    bool noOp = false,
  }) {
    return CraftingSnapshot(
      papers: papers.map(CraftingPaperState.fromPaper).toList(),
      nextPaperId: nextPaperId,
      inventory: Map<PaperColor, int>.from(inventory),
      selectedPaperIds: Set<String>.from(selectedPaperIds),
      label: label,
      noOp: noOp,
    );
  }
}

/// Snapshot-based undo / redo stack for the crafting canvas.
class CraftingHistory extends ChangeNotifier {
  final List<CraftingSnapshot> _undoStack = [];
  final List<CraftingSnapshot> _redoStack = [];
  static const int maxDepth = 50;

  int _operativeActionCount = 0;

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
  int get operativeActionCount => _operativeActionCount;

  /// Push the *current* state before a mutation. [snapshot] is the state
  /// **before** the change is applied so that undoing restores it.
  void pushSnapshot(CraftingSnapshot snapshot) {
    _undoStack.add(snapshot);
    if (!snapshot.noOp) {
      _operativeActionCount++;
    }
    if (_undoStack.length > maxDepth) {
      final removed = _undoStack.removeAt(0);
      if (!removed.noOp) {
        _operativeActionCount--;
      }
    }
    _redoStack.clear();
    notifyListeners();
  }

  /// Undo: returns the snapshot to restore, or null if nothing to undo.
  /// [current] is the state right now (pushed onto the redo stack).
  CraftingSnapshot? undo(CraftingSnapshot current) {
    if (_undoStack.isEmpty) return null;
    final previous = _undoStack.removeLast();
    if (!previous.noOp) {
      _operativeActionCount--;
    }
    _redoStack.add(
      current.copyWith(restoresOperativeOnRedo: !previous.noOp),
    );
    notifyListeners();
    return previous;
  }

  /// Redo: returns the snapshot to restore, or null if nothing to redo.
  /// [current] is the state right now (pushed onto the undo stack).
  CraftingSnapshot? redo(CraftingSnapshot current) {
    if (_redoStack.isEmpty) return null;
    _undoStack.add(current);
    final next = _redoStack.removeLast();
    if (next.restoresOperativeOnRedo) {
      _operativeActionCount++;
    }
    notifyListeners();
    return next;
  }

  void clear() {
    if (_undoStack.isEmpty && _redoStack.isEmpty && _operativeActionCount == 0) {
      return;
    }
    _undoStack.clear();
    _redoStack.clear();
    _operativeActionCount = 0;
    notifyListeners();
  }
}
