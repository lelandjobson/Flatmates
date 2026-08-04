import 'dart:async';
import 'package:flutter/material.dart';

import '../rendering/iso/iso_coordinate.dart';
import '../rendering/iso/iso_hit_tester.dart';
import '../ui/hud/hud_action.dart';
import '../ui/hud/circular_drag_hud.dart';
import 'drag_origin.dart';

enum GesturePhase {
  idle,
  dragIntent,
  holdSelect,
  panning,
  radialHold,
  radialShown,
  pathDrag,
  painting,
}

abstract class MapGestureDelegate {
  IsoHitResult hitTest(Offset screenPos);
  IsoCoordinate? screenToTile(Offset screenPos);

  bool isPointerOnSelection(Offset screenPos);
  bool isPointerOnFriendTile(Offset screenPos, String friendId);
  bool canDragSelection();
  DragOrigin? originFromHit(IsoHitResult result);

  bool isPainting();
  bool isEditMode();

  void onPaintBegin();
  void onPaintStroke(Offset pos);
  void onPaintTap(Offset pos);
  void onPaintEnd();

  void onSelect(IsoHitResult result);
  void onClick(Offset pos);
  void onDoubleClick(Offset pos);

  void onRadialShow(DragOrigin origin, List<HudAction> actions);
  void onRadialUpdate(int? selectedIndex, Offset screenPos);
  void onRadialDismiss();
  void onRadialExecute(int actionIndex);

  void onPathDragBegin(DragOrigin origin);
  void onPathDragUpdate(List<IsoCoordinate> path, Offset screenPos);
  void onPathDragEnd(DragOrigin origin, List<IsoCoordinate> path, Offset screenPos);

  void onPan(Offset delta);
  void onPanEnd(Offset velocity);
  void onZoom(double scaleDelta);

  void onDismissHud();
  void onStopInertia();

  List<HudAction> buildRadialActions(DragOrigin origin);

  Offset originScreenCenter(DragOrigin origin);

  double get tileScreenSize;
}

class MapGestureHandler {
  MapGestureHandler({required this.delegate});

  final MapGestureDelegate delegate;

  GesturePhase get phase => _phase;
  GesturePhase _phase = GesturePhase.idle;

  DragOrigin? get activeOrigin => _origin;
  List<IsoCoordinate> get activePath => List.unmodifiable(_path);
  int? get radialSelectedIndex => _radialSelectedIndex;

  static const Duration _dragMinHoldDuration = Duration(milliseconds: 72);   // 60% of 120ms
  static const Duration _radialHoldDuration = Duration(milliseconds: 300);   // 60% of 500ms
  static const double _radialHoldTileTolerance = 0.4;
  static const Duration _holdSelectDuration = Duration(milliseconds: 750);
  static const double _holdSelectMoveTolerance = 15.0;
  static const double _radialDismissTileThreshold = 1.5;
  static const int _doubleTapThresholdMs = 400;
  static const double _doubleTapDistanceSq = 100.0;
  static const double _dragIntentMoveTolerance = 8.0;

  Offset? _downPosition;
  Offset? _dragStartPosition;
  double _dragDistance = 0.0;
  Timer? _phaseTimer;
  DragOrigin? _origin;
  final List<IsoCoordinate> _path = [];
  int? _radialSelectedIndex;
  List<HudAction> _radialActions = [];

  DateTime? _lastClickTime;
  Offset? _lastClickPosition;

  Offset _panVelocity = Offset.zero;
  DateTime? _lastPanSampleTime;

  IsoHitResult? _holdSelectHitResult;

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  void handlePointerDown(Offset position) {
    _downPosition = position;
    _dragStartPosition = position;
    _dragDistance = 0.0;

    if (delegate.isPainting()) {
      _phase = GesturePhase.painting;
      delegate.onPaintBegin();
      return;
    }

    if (delegate.isEditMode()) {
      delegate.onStopInertia();
      return;
    }

    delegate.onStopInertia();

    if (delegate.isPointerOnSelection(position) && delegate.canDragSelection()) {
      _transitionToDragIntent(position);
      // Plain tile selections have no draggable origin (no friend/structure).
      // Fall back to holdSelect so panning and double-tap still work.
      if (_origin == null) {
        _cancelTimer();
        _transitionToHoldSelect(position);
      }
    } else {
      _transitionToHoldSelect(position);
    }
  }

  void handlePointerMove(Offset position, Offset delta) {
    _dragDistance += delta.distance;

    switch (_phase) {
      case GesturePhase.painting:
        delegate.onPaintStroke(position);

      case GesturePhase.dragIntent:
        if (_dragDistance > _dragIntentMoveTolerance) {
          _cancelTimer();
          delegate.onDismissHud();
          final allowPathDrag = _isDragStartOnFriendTile();
          if (allowPathDrag) {
            _transitionToPathDrag(position);
          } else {
            _phase = GesturePhase.panning;
            _trackPanVelocity(delta);
            delegate.onPan(delta);
          }
        }

      case GesturePhase.radialHold:
        _handleRadialHoldMove(position, delta);

      case GesturePhase.radialShown:
        _handleRadialShownMove(position);

      case GesturePhase.pathDrag:
        _handlePathDragMove(position);

      case GesturePhase.holdSelect:
        _handleHoldSelectMove(position, delta);

      case GesturePhase.panning:
        _trackPanVelocity(delta);
        delegate.onPan(delta);

      case GesturePhase.idle:
        break;
    }
  }

  void handlePointerUp(Offset position) {
    switch (_phase) {
      case GesturePhase.painting:
        if (_dragDistance < 50.0 && _downPosition != null) {
          delegate.onPaintTap(_downPosition!);
        }
        delegate.onPaintEnd();

      case GesturePhase.dragIntent:
        _cancelTimer();
        _fireClickOrDoubleClick(_downPosition ?? position);

      case GesturePhase.radialHold:
        _cancelTimer();
        if (_dragDistance < 50.0 && _downPosition != null) {
          _fireClickOrDoubleClick(_downPosition!);
        } else {
          delegate.onDismissHud();
        }

      case GesturePhase.radialShown:
        if (_radialSelectedIndex != null) {
          delegate.onRadialExecute(_radialSelectedIndex!);
        } else {
          delegate.onDismissHud();
        }

      case GesturePhase.pathDrag:
        if (_origin != null && _path.length >= 2) {
          delegate.onPathDragEnd(_origin!, List.from(_path), position);
        } else {
          delegate.onDismissHud();
        }

      case GesturePhase.holdSelect:
        _cancelTimer();
        if (_dragDistance < 50.0 && _downPosition != null) {
          _fireClickOrDoubleClick(_downPosition!);
        }

      case GesturePhase.panning:
        // If the finger barely moved from its down position, treat as a tap
        // so that touch-jitter-induced panning doesn't break double-tap.
        if (_downPosition != null &&
            (position - _downPosition!).distanceSquared < _doubleTapDistanceSq) {
          _fireClickOrDoubleClick(_downPosition!);
        } else {
          delegate.onPanEnd(_panVelocity);
        }

      case GesturePhase.idle:
        break;
    }

    _resetToIdle();
  }

  void handleScaleChange(double scaleDelta) {
    if (_phase != GesturePhase.panning && _phase != GesturePhase.idle) {
      delegate.onDismissHud();
      _cancelTimer();
    }
    _phase = GesturePhase.panning;
    delegate.onZoom(scaleDelta);
  }

  void handleCancel() {
    _cancelTimer();
    delegate.onDismissHud();
    _resetToIdle();
  }

  void showPersistentRadial(DragOrigin origin) {
    _origin = origin;
    _radialActions = delegate.buildRadialActions(origin);
    _radialSelectedIndex = null;
    delegate.onRadialShow(origin, _radialActions);
    _phase = GesturePhase.radialShown;
  }

  void dispose() {
    _cancelTimer();
  }

  // -------------------------------------------------------------------------
  // Phase transitions
  // -------------------------------------------------------------------------

  void _transitionToDragIntent(Offset position) {
    _phase = GesturePhase.dragIntent;
    _downPosition = position;

    final hitResult = delegate.hitTest(position);
    _origin = delegate.originFromHit(hitResult);

    _cancelTimer();
    _phaseTimer = Timer(_dragMinHoldDuration, () {
      _phaseTimer = null;
      if (_phase != GesturePhase.dragIntent) return;
      _transitionToRadialHold();
    });
  }

  void _transitionToHoldSelect(Offset position) {
    _phase = GesturePhase.holdSelect;
    _downPosition = position;

    final hitResult = delegate.hitTest(position);
    _holdSelectHitResult = hitResult;
    _origin = delegate.originFromHit(hitResult);

    _cancelTimer();
    _phaseTimer = Timer(_holdSelectDuration, () {
      _phaseTimer = null;
      if (_phase != GesturePhase.holdSelect) return;
      if (_holdSelectHitResult != null) {
        delegate.onSelect(_holdSelectHitResult!);
      }
    });
  }

  void _transitionToRadialHold() {
    final pos = _downPosition;
    if (pos == null) return;

    delegate.onDismissHud();

    if (_origin == null) {
      _resetToIdle();
      return;
    }

    _phase = GesturePhase.radialHold;

    _cancelTimer();
    _phaseTimer = Timer(_radialHoldDuration, () {
      _phaseTimer = null;
      if (_phase != GesturePhase.radialHold) return;
      _transitionToRadialShown();
    });
  }

  void _transitionToRadialShown() {
    if (_origin == null) return;

    final pos = _downPosition;
    if (pos != null) {
      final center = delegate.originScreenCenter(_origin!);
      final tileDist = (pos - center).distance / delegate.tileScreenSize;
      if (tileDist > _radialHoldTileTolerance) {
        if (_origin!.isFriend && _isDragStartOnFriendTile()) {
          _transitionToPathDrag(pos);
        } else {
          _phase = GesturePhase.panning;
        }
        return;
      }
    }

    _radialActions = delegate.buildRadialActions(_origin!);
    _radialSelectedIndex = null;
    _phase = GesturePhase.radialShown;
    delegate.onRadialShow(_origin!, _radialActions);
  }

  void _transitionToPathDrag(Offset fromPos) {
    _phase = GesturePhase.pathDrag;
    _path.clear();
    if (_origin != null) {
      _path.add(_origin!.coordinate);
      final coord = delegate.screenToTile(fromPos);
      if (coord != null && !coord.samePosition(_origin!.coordinate)) {
        _path.add(coord);
      }
    }
    delegate.onPathDragBegin(_origin!);
    delegate.onPathDragUpdate(List.from(_path), fromPos);
  }

  void _resetToIdle() {
    _cancelTimer();
    _phase = GesturePhase.idle;
    _downPosition = null;
    _dragStartPosition = null;
    _dragDistance = 0.0;
    _origin = null;
    _path.clear();
    _radialSelectedIndex = null;
    _radialActions = [];
    _holdSelectHitResult = null;
    _panVelocity = Offset.zero;
    _lastPanSampleTime = null;
  }

  void _cancelTimer() {
    _phaseTimer?.cancel();
    _phaseTimer = null;
  }

  // -------------------------------------------------------------------------
  // Move handlers per phase
  // -------------------------------------------------------------------------

  bool _isDragStartOnFriendTile() {
    final start = _dragStartPosition;
    return _origin != null &&
        _origin!.isFriend &&
        _origin!.friendId != null &&
        start != null &&
        delegate.isPointerOnFriendTile(start, _origin!.friendId!);
  }

  void _handleRadialHoldMove(Offset position, Offset delta) {
    _downPosition = position;
    if (_origin == null) return;

    final center = delegate.originScreenCenter(_origin!);
    final tileDist = (position - center).distance / delegate.tileScreenSize;

    if (tileDist > _radialHoldTileTolerance) {
      _cancelTimer();
      if (_origin!.isFriend && _isDragStartOnFriendTile()) {
        _transitionToPathDrag(position);
      } else {
        _phase = GesturePhase.panning;
        _trackPanVelocity(delta);
        delegate.onPan(delta);
      }
    }
  }

  void _handleRadialShownMove(Offset position) {
    if (_origin == null) return;

    final center = delegate.originScreenCenter(_origin!);
    final tileSize = delegate.tileScreenSize;
    final tileDist = (position - center).distance / tileSize;

    if (tileDist >= _radialDismissTileThreshold && _origin!.isFriend && _isDragStartOnFriendTile()) {
      delegate.onRadialDismiss();
      _transitionToPathDrag(position);
      return;
    }

    if (tileDist < _radialDismissTileThreshold) {
      final dragVector = position - center;
      final angles = CircularDragHud.anglesForCount(_radialActions.length);
      _radialSelectedIndex = CircularDragHud.indexForDragVector(dragVector, angles);
      delegate.onRadialUpdate(_radialSelectedIndex, position);
    } else {
      _radialSelectedIndex = null;
      delegate.onRadialUpdate(null, position);
    }
  }

  void _handlePathDragMove(Offset position) {
    final coord = delegate.screenToTile(position);
    if (coord != null) {
      if (_path.isEmpty) {
        if (_origin != null) _path.add(_origin!.coordinate);
      }
      if (_path.isEmpty || !coord.samePosition(_path.last)) {
        _path.add(coord);
      }
    }
    delegate.onPathDragUpdate(List.from(_path), position);
  }

  void _handleHoldSelectMove(Offset position, Offset delta) {
    if (_downPosition == null) return;
    final dist = (position - _downPosition!).distance;

    if (_origin != null && _origin!.isFriend && _isDragStartOnFriendTile()) {
      final center = delegate.originScreenCenter(_origin!);
      final tileDist = (position - center).distance / delegate.tileScreenSize;

      if (tileDist > _radialHoldTileTolerance && delegate.canDragSelection()) {
        _cancelTimer();
        _transitionToPathDrag(position);
        return;
      }
    }

    if (dist > _holdSelectMoveTolerance) {
      _cancelTimer();
      _phase = GesturePhase.panning;
      _trackPanVelocity(delta);
      delegate.onPan(delta);
    }
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  void _trackPanVelocity(Offset delta) {
    final now = DateTime.now();
    final last = _lastPanSampleTime;
    if (last != null) {
      final dt = now.difference(last).inMicroseconds / 1e6;
      if (dt > 0 && dt < 0.1) {
        _panVelocity = delta / dt;
      } else if (dt >= 0.1) {
        _panVelocity = Offset.zero;
      }
    }
    _lastPanSampleTime = now;
  }

  void _fireClickOrDoubleClick(Offset position) {
    delegate.onStopInertia();
    delegate.onDismissHud();

    final now = DateTime.now();
    if (_lastClickTime != null &&
        _lastClickPosition != null &&
        now.difference(_lastClickTime!).inMilliseconds < _doubleTapThresholdMs &&
        (position - _lastClickPosition!).distanceSquared < _doubleTapDistanceSq) {
      _lastClickTime = null;
      _lastClickPosition = null;
      delegate.onDoubleClick(position);
    } else {
      _lastClickTime = now;
      _lastClickPosition = position;
      delegate.onClick(position);
    }
  }
}
