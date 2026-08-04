import '../rendering/iso/iso_coordinate.dart';
import 'crafting_database.dart';

/// Duration of a single turn in seconds
const double turnDurationSeconds = 0.5;

/// Types of tasks a friend can perform
enum TaskType { move, gather, craft }

/// Represents a complete task consisting of one or more actions
class Task {
  final String id;
  final TaskType type;
  final String description;
  final IsoCoordinate? targetCoordinate;
  final String? targetStructureId;
  final CraftingRecipe? recipe;

  /// Total number of turns this task takes
  final int totalTurns;

  /// Number of turns completed so far
  int _completedTurns = 0;

  /// Whether this task should repeat after completion
  bool shouldRepeat = false;

  /// Callback when task completes
  void Function(Task)? onComplete;

  /// Callback when a turn completes
  void Function(Task, int turnsRemaining)? onTurnComplete;

  Task({
    required this.id,
    required this.type,
    required this.description,
    required this.totalTurns,
    this.targetCoordinate,
    this.targetStructureId,
    this.recipe,
    this.shouldRepeat = false,
    this.onComplete,
    this.onTurnComplete,
  });

  /// Create a move task
  factory Task.move({
    required String id,
    required IsoCoordinate destination,
    required int pathLength,
  }) {
    return Task(
      id: id,
      type: TaskType.move,
      description: 'Move to (${destination.x}, ${destination.y})',
      totalTurns: pathLength,
      targetCoordinate: destination,
    );
  }

  /// Default number of turns required to gather material from a tile
  static const int defaultGatherTurns = 3;

  /// Create a gather task (includes movement + gather time + return)
  factory Task.gather({
    required String id,
    required IsoCoordinate target,
    required int pathLength,
    required IsoCoordinate returnTo,
    int gatherTurns = defaultGatherTurns,
  }) {
    // Path to tile + gather turns + path back
    final returnPathLength = pathLength; // Symmetric return
    final total = pathLength + gatherTurns + returnPathLength;
    return Task(
      id: id,
      type: TaskType.gather,
      description: 'Gather at (${target.x}, ${target.y})',
      totalTurns: total,
      targetCoordinate: target,
    );
  }

  /// Create a gather task without return (just go and gather)
  factory Task.gatherNoReturn({
    required String id,
    required IsoCoordinate target,
    required int pathLength,
    int gatherTurns = defaultGatherTurns,
  }) {
    return Task(
      id: id,
      type: TaskType.gather,
      description: 'Gather at (${target.x}, ${target.y})',
      totalTurns: pathLength + gatherTurns, // Path + gather turns
      targetCoordinate: target,
    );
  }

  /// Create a craft task (1 turn per recipe, or recipe-defined)
  factory Task.craft({
    required String id,
    required CraftingRecipe recipe,
    required String structureId,
    required IsoCoordinate structureCoord,
  }) {
    return Task(
      id: id,
      type: TaskType.craft,
      description: 'Craft ${recipe.name}',
      totalTurns: recipe.turnsToComplete,
      targetCoordinate: structureCoord,
      targetStructureId: structureId,
      recipe: recipe,
    );
  }

  /// Number of turns completed
  int get completedTurns => _completedTurns;

  /// Number of turns remaining
  int get remainingTurns => totalTurns - _completedTurns;

  /// Progress from 0.0 to 1.0
  double get progress => totalTurns > 0 ? _completedTurns / totalTurns : 1.0;

  /// Whether this task is complete
  bool get isComplete => _completedTurns >= totalTurns;

  /// Advance the task by one turn
  void advanceTurn() {
    if (isComplete) return;

    _completedTurns++;
    onTurnComplete?.call(this, remainingTurns);

    if (isComplete) {
      onComplete?.call(this);
    }
  }

  /// Advance the task by partial progress (for smooth animation)
  /// [delta] is the elapsed time in seconds
  /// Returns the number of complete turns that occurred
  int advanceTime(double deltaSeconds) {
    if (isComplete) return 0;

    final turnsToAdvance = (deltaSeconds / turnDurationSeconds).floor();
    final actualTurns = turnsToAdvance.clamp(0, remainingTurns);

    for (var i = 0; i < actualTurns; i++) {
      advanceTurn();
    }

    return actualTurns;
  }

  /// Reset task progress (for repeating tasks)
  void reset() {
    _completedTurns = 0;
  }

  /// Create a copy of this task with a new ID (for repeating)
  Task copyForRepeat() {
    return Task(
      id: '${id}_repeat_${DateTime.now().millisecondsSinceEpoch}',
      type: type,
      description: description,
      totalTurns: totalTurns,
      targetCoordinate: targetCoordinate,
      targetStructureId: targetStructureId,
      recipe: recipe,
      shouldRepeat: shouldRepeat,
      onComplete: onComplete,
      onTurnComplete: onTurnComplete,
    );
  }

  /// Get display label for task type
  String get typeLabel => switch (type) {
    TaskType.move => 'Move',
    TaskType.gather => 'Gather',
    TaskType.craft => 'Craft',
  };

  /// Get short status text (e.g., "Gather 3")
  String get statusText => '$typeLabel $remainingTurns';

  @override
  String toString() =>
      'Task($typeLabel: $description, $completedTurns/$totalTurns turns)';
}

/// Manages a queue of tasks for a friend
class TaskQueue {
  final List<Task> _tasks = [];

  /// Current task being executed
  Task? _currentTask;

  /// Whether current task should repeat
  bool repeatCurrent = false;

  /// Get current task
  Task? get currentTask => _currentTask;

  /// Get queued tasks (not including current)
  List<Task> get queuedTasks => List.unmodifiable(_tasks);

  /// Total number of tasks (current + queued)
  int get totalTasks => (_currentTask != null ? 1 : 0) + _tasks.length;

  /// Whether there are any tasks
  bool get hasTasks => _currentTask != null || _tasks.isNotEmpty;

  /// Whether the friend is idle (no current task)
  bool get isIdle => _currentTask == null;

  /// Add a task to the end of the queue
  void enqueue(Task task) {
    _tasks.add(task);
    _startNextIfIdle();
  }

  /// Add multiple tasks to the queue
  void enqueueAll(Iterable<Task> tasks) {
    _tasks.addAll(tasks);
    _startNextIfIdle();
  }

  /// Insert a task at the front of the queue (will be next after current)
  void insertNext(Task task) {
    _tasks.insert(0, task);
    _startNextIfIdle();
  }

  /// Clear all queued tasks (but not current)
  void clearQueue() {
    _tasks.clear();
  }

  /// Cancel current task and clear queue
  void cancelAll() {
    _currentTask = null;
    _tasks.clear();
    repeatCurrent = false;
  }

  /// Start the next task if idle
  void _startNextIfIdle() {
    if (_currentTask == null && _tasks.isNotEmpty) {
      _currentTask = _tasks.removeAt(0);
    }
  }

  /// Called when current task completes
  void completeCurrentTask() {
    if (_currentTask == null) return;

    final completed = _currentTask!;
    _currentTask = null;

    // Handle repeating tasks
    if (completed.shouldRepeat || repeatCurrent) {
      final repeat = completed.copyForRepeat();
      enqueue(repeat);
    }

    // Start next task
    _startNextIfIdle();
  }

  /// Advance current task by time
  /// Returns true if a task was completed
  bool advanceTime(double deltaSeconds) {
    if (_currentTask == null) return false;

    _currentTask!.advanceTime(deltaSeconds);

    if (_currentTask!.isComplete) {
      completeCurrentTask();
      return true;
    }

    return false;
  }

  /// Get summary of task queue
  String get summary {
    if (_currentTask == null) return 'Idle';

    final parts = <String>[_currentTask!.statusText];
    if (_tasks.isNotEmpty) {
      parts.add('+${_tasks.length} queued');
    }
    return parts.join(', ');
  }
}

/// Unique ID generator for tasks
class TaskIdGenerator {
  static int _counter = 0;

  static String generate() {
    _counter++;
    return 'task_${DateTime.now().millisecondsSinceEpoch}_$_counter';
  }
}
