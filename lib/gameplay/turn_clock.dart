import 'dart:async';
import 'package:flutter/foundation.dart';

/// Global turn clock that synchronizes all game actions.
///
/// A turn is the fundamental unit of game time (default 0.5 seconds).
/// All actions (movement, gathering, crafting) are synchronized to turn boundaries.
class TurnClock extends ChangeNotifier {
  /// Duration of one turn in seconds
  static const double turnDurationSeconds = 0.5;

  /// Timer interval for updates (16ms ≈ 60fps for smooth animations)
  static const int _updateIntervalMs = 16;

  double _elapsedTime = 0.0;
  int _currentTurn = 0;
  double _turnProgress = 0.0; // 0.0 to 1.0 within current turn

  Timer? _timer;
  DateTime? _lastTick;
  bool _isRunning = false;

  /// Callbacks for when a turn completes
  final List<VoidCallback> _turnCallbacks = [];

  /// Get the current turn number (0-indexed)
  int get currentTurn => _currentTurn;

  /// Get progress within current turn (0.0 = start, 1.0 = end)
  double get turnProgress => _turnProgress;

  /// Get total elapsed time in seconds
  double get elapsedTime => _elapsedTime;

  /// Check if the clock is running
  bool get isRunning => _isRunning;

  /// Start the turn clock
  void start() {
    if (_isRunning) return;

    _isRunning = true;
    _lastTick = DateTime.now();

    _timer = Timer.periodic(
      const Duration(milliseconds: _updateIntervalMs),
      (_) => _tick(),
    );
  }

  /// Stop the turn clock
  void stop() {
    _isRunning = false;
    _timer?.cancel();
    _timer = null;
  }

  /// Reset the clock to zero
  void reset() {
    _elapsedTime = 0.0;
    _currentTurn = 0;
    _turnProgress = 0.0;
    _lastTick = DateTime.now();
    notifyListeners();
  }

  /// Register a callback to be called when a turn completes
  void addTurnCallback(VoidCallback callback) {
    _turnCallbacks.add(callback);
  }

  /// Remove a turn completion callback
  void removeTurnCallback(VoidCallback callback) {
    _turnCallbacks.remove(callback);
  }

  /// Internal tick method called by timer
  void _tick() {
    if (!_isRunning) return;

    final now = DateTime.now();
    final delta = now.difference(_lastTick!).inMicroseconds / 1000000.0;
    _lastTick = now;

    _advanceTime(delta);
  }

  /// Advance the clock by a given amount of time (in seconds)
  /// This is also useful for testing or manual time control
  void _advanceTime(double deltaSeconds) {
    final previousTurn = _currentTurn;

    _elapsedTime += deltaSeconds;
    _currentTurn = (_elapsedTime / turnDurationSeconds).floor();
    _turnProgress = (_elapsedTime % turnDurationSeconds) / turnDurationSeconds;

    // Check if we crossed a turn boundary
    if (_currentTurn > previousTurn) {
      // Notify turn callbacks (iterate over copy to allow modifications during iteration)
      for (final callback in List.of(_turnCallbacks)) {
        callback();
      }
    }

    // Always notify listeners for progress updates (for animations)
    notifyListeners();
  }

  /// Get the number of complete turns that have passed
  int getTurnsSince(double startTime) {
    final startTurn = (startTime / turnDurationSeconds).floor();
    return _currentTurn - startTurn;
  }

  @override
  void dispose() {
    stop();
    _turnCallbacks.clear();
    super.dispose();
  }
}
