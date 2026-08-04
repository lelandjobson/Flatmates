import 'package:flutter/material.dart';
import '../rendering/iso/iso_coordinate.dart';

enum SequencedActionType { move, gather, repeat }

class SequencedAction {
  SequencedAction({
    required this.id,
    required this.type,
    this.targetTile,
    this.targetFoliageId,
    required this.label,
    required this.icon,
    this.repeatCount = 0,
  });

  final String id;
  final SequencedActionType type;
  final IsoCoordinate? targetTile;

  /// When set, the gather action targets this specific foliage instance
  /// instead of the tile material.
  final String? targetFoliageId;

  String label;
  IconData icon;

  /// 0 = infinite, >0 = repeat N times
  int repeatCount;

  bool get isRepeat => type == SequencedActionType.repeat;

  static int _counter = 0;
  static String generateId() => 'seq_${DateTime.now().millisecondsSinceEpoch}_${_counter++}';
}

/// Per-friend ordered list of actions that can be recorded, reordered,
/// and played back with optional repeat loops.
class FriendActionSequence extends ChangeNotifier {
  FriendActionSequence({required this.friendId});

  final String friendId;
  final List<SequencedAction> actions = [];

  /// Index of the action currently being executed. -1 = not executing.
  int currentIndex = -1;

  /// Whether the sequence is actively being played.
  bool isExecuting = false;

  /// Position when execution started. Used for static path preview geometry
  /// so paths don't change as the friend moves.
  IsoCoordinate? sequenceStartPosition;

  /// Whether the current action has been dispatched (move started, gather
  /// initiated). Reset to false when advancing to the next action.
  bool _currentDispatched = false;
  bool get currentDispatched => _currentDispatched;

  /// Seconds elapsed while waiting for a failed/impossible action.
  double waitingSeconds = 0.0;
  static const double waitTimeout = 5.0;
  static const double retryInterval = 0.1;
  double _lastRetryAt = 0.0;
  bool get isWaiting => waitingSeconds > 0.0;

  /// True if we should retry dispatch (every [retryInterval] seconds while waiting).
  bool get shouldRetryDispatch =>
      waitingSeconds > 0 && (waitingSeconds - _lastRetryAt) >= retryInterval;

  void markRetryAttempted() {
    _lastRetryAt = waitingSeconds;
  }

  void clearWaiting() {
    waitingSeconds = 0.0;
    _lastRetryAt = 0.0;
    notifyListeners();
  }

  SequencedAction? get currentAction =>
      isExecuting && currentIndex >= 0 && currentIndex < actions.length
          ? actions[currentIndex]
          : null;

  bool get hasRepeat => actions.any((a) => a.isRepeat);

  void addAction(SequencedAction action) {
    actions.add(action);
    notifyListeners();
  }

  void removeAt(int index) {
    if (index < 0 || index >= actions.length) return;
    actions.removeAt(index);
    if (isExecuting) {
      if (index < currentIndex) {
        currentIndex--;
      } else if (index == currentIndex) {
        _currentDispatched = false;
        waitingSeconds = 0.0;
      }
      if (currentIndex >= actions.length) {
        cancelAll();
      }
    }
    notifyListeners();
  }

  /// Remove the action at [index] and all actions below it (including repeats).
  void removeFrom(int index) {
    if (index < 0 || index >= actions.length) return;
    actions.removeRange(index, actions.length);
    if (isExecuting) {
      if (currentIndex >= actions.length) {
        cancelAll();
      } else if (currentIndex >= index) {
        _currentDispatched = false;
        waitingSeconds = 0.0;
      }
    }
    notifyListeners();
  }

  void reorder(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) newIndex--;
    final item = actions.removeAt(oldIndex);
    actions.insert(newIndex, item);
    if (isExecuting) {
      if (oldIndex == currentIndex) {
        currentIndex = newIndex;
      } else if (oldIndex < currentIndex && newIndex >= currentIndex) {
        currentIndex--;
      } else if (oldIndex > currentIndex && newIndex <= currentIndex) {
        currentIndex++;
      }
    }
    notifyListeners();
  }

  void clear() {
    actions.clear();
    currentIndex = -1;
    isExecuting = false;
    sequenceStartPosition = null;
    _currentDispatched = false;
    waitingSeconds = 0.0;
    notifyListeners();
  }

  /// Start execution. [initialPosition] is the friend's position when execution
  /// starts; used for static path preview geometry.
  void startExecution({IsoCoordinate? initialPosition}) {
    if (actions.isEmpty) return;
    currentIndex = 0;
    isExecuting = true;
    sequenceStartPosition = initialPosition;
    _currentDispatched = false;
    waitingSeconds = 0.0;
    notifyListeners();
  }

  /// Advance to the next action. In repeat mode the green arrow slides down
  /// and actions stay in place. Without a repeat block, completed actions are
  /// removed from the list so they visually dismiss from the panel.
  void advance() {
    if (!isExecuting) return;
    _currentDispatched = false;
    waitingSeconds = 0.0;
    _lastRetryAt = 0.0;

    if (hasRepeat) {
      // --- Repeat mode: keep actions, slide the pointer ---
      currentIndex++;
      if (currentIndex >= actions.length) {
        cancelAll();
        return;
      }
      final action = actions[currentIndex];
      if (action.isRepeat) {
        if (action.repeatCount > 0) {
          action.repeatCount--;
          if (action.repeatCount <= 0) {
            cancelAll();
            return;
          }
        }
        // Update start position for next loop iteration (friend is at end of loop)
        sequenceStartPosition = _lastMoveTargetBeforeRepeat();
        currentIndex = 0;
        _currentDispatched = false;
      }
    } else {
      // --- No repeat: remove completed action from the top ---
      if (currentIndex >= 0 && currentIndex < actions.length) {
        actions.removeAt(currentIndex);
      }
      // currentIndex stays at 0 (the next action is now at position 0)
      currentIndex = 0;
      if (actions.isEmpty) {
        cancelAll();
        return;
      }
    }

    notifyListeners();
  }

  void markDispatched() {
    _currentDispatched = true;
  }

  void startWaiting() {
    if (waitingSeconds <= 0.0) {
      waitingSeconds = 0.001;
      _lastRetryAt = 0.0;
      notifyListeners();
    }
  }

  /// Returns true if the wait timed out and all actions were cleared.
  bool tickWaiting(double dt) {
    if (waitingSeconds <= 0.0) return false;
    waitingSeconds += dt;
    if (waitingSeconds >= waitTimeout) {
      clear();
      return true;
    }
    notifyListeners();
    return false;
  }

  void cancelAll() {
    isExecuting = false;
    currentIndex = -1;
    sequenceStartPosition = null;
    _currentDispatched = false;
    waitingSeconds = 0.0;
    notifyListeners();
  }

  /// Target of the last move action before the repeat (position at end of loop).
  IsoCoordinate? _lastMoveTargetBeforeRepeat() {
    for (var i = actions.length - 1; i >= 0; i--) {
      final a = actions[i];
      if (a.isRepeat) continue;
      if (a.type == SequencedActionType.move && a.targetTile != null) {
        return a.targetTile;
      }
    }
    return sequenceStartPosition;
  }
}
