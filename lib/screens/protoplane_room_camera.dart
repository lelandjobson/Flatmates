part of 'protoplane_concept_view.dart';

extension _RoomCamera on _ProtoplaneConceptViewState {
  void _scheduleRoomFrame({bool force = false}) {
    if (_opening ||
        viewport.isEmpty ||
        _surfaceFocus.isNotEmpty ||
        (!force && _currentRoom != null) ||
        _roomFrameScheduled) {
      return;
    }
    final room =
        model.objects[_currentRoom] ??
        model.objects.values.where((o) => o.kind == CraftKind.room).firstOrNull;
    if (room == null) return;
    _roomFrameScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _roomFrameScheduled = false;
      if (mounted && model.objects.containsKey(room.id)) {
        _frameRoom(room, animate: false);
      }
    });
  }

  void _frameRoom(CraftObject room, {bool animate = true}) {
    _currentRoom = room.id;
    final neighbors = {room.id};
    if (_roomZoomLevel == 1) {
      for (final wall in model.walls.where(
        (w) => w.shared && w.sides.any((s) => s.room == room.id),
      )) {
        neighbors.addAll(wall.sides.map((s) => s.room));
      }
    }
    final points = [
      for (final id in neighbors)
        for (final p in model.objects[id]!.region.outer)
          model.objectPlane(model.objects[id]!).point(p),
    ];
    final xs = points.map((p) => p.x), zs = points.map((p) => p.z);
    final bounds = Rect.fromLTRB(
      xs.reduce(math.min),
      zs.reduce(math.min),
      xs.reduce(math.max),
      zs.reduce(math.max),
    );
    final center = Vector3(bounds.center.dx, points.first.y, bounds.center.dy);
    final usable = Size(
      math.max(100, viewport.width - 48),
      math.max(100, viewport.height - 190),
    );
    final tan = math.tan(camera.fovDegrees * math.pi / 360);
    final distance = _roomZoomLevel == 2
        ? (devSettings.parcelZoomNear + devSettings.parcelZoomFar) / 2
        : 1 +
              math.max(
                    bounds.width * viewport.height / (2 * tan * usable.width),
                    bounds.height * viewport.height / (2 * tan * usable.height),
                  ) *
                  1.12 *
                  (_roomZoomLevel == 1 ? 1.4 : 1);
    _cancelSurfaceGesture();
    _cancelFocusStroke();
    model.constructionTool = null;
    model.activePlaneId = null;
    _selection.clear();
    _selectedPaths.clear();
    _selecting = false;
    _pinnedSurface = null;
    _roomFocus = null;
    _roomReveal.value = 0;
    camera.setUp(Vector3(0, 0, -1));
    if (animate && !MediaQuery.disableAnimationsOf(context)) {
      mapCamera.animateLookAt(center);
      mapCamera.animateDistance(distance);
    } else {
      mapCamera.restorePose(
        lookAt: center,
        distance: distance,
        yaw: math.pi / 2,
      );
    }
    _constructionPreviewKey = null;
    _targetCacheKey = null;
    _refreshScene();
    _updateFocusUi(() {});
  }

  void _stepRoomZoom(double scale) {
    if (_roomZoomConsumed || _surfaceFocus.isNotEmpty || _currentRoom == null) {
      return;
    }
    if (scale > .85 && scale < 1.18) return;
    final next = (_roomZoomLevel + (scale < 1 ? 1 : -1)).clamp(0, 2);
    _roomZoomConsumed = true;
    if (next == _roomZoomLevel) return;
    _roomZoomLevel = next;
    _frameRoom(model.objects[_currentRoom]!);
  }

  void _swipeRoom(Offset swipe) {
    if (_roomZoomConsumed ||
        _surfaceFocus.isNotEmpty ||
        _currentRoom == null ||
        swipe.distance < 1) {
      return;
    }
    if (_roomZoomLevel == 2) {
      _roomZoomConsumed = true;
      final step = model.parcels.size.toDouble();
      final shift = swipe.dx.abs() > swipe.dy.abs()
          ? Vector3(-swipe.dx.sign * step, 0, 0)
          : Vector3(0, 0, -swipe.dy.sign * step);
      mapCamera.animateLookAt(camera.target + shift);
      return;
    }
    final current = model.objects[_currentRoom]!;
    final origin = model
        .objectPlane(current)
        .point(current.region.bounds.center);
    final right = camera.forward.cross(camera.up).normalized();
    final direction = (right * (-swipe.dx) + camera.up * swipe.dy).normalized();
    final candidates = <String>{};
    for (final wall in model.walls.where(
      (w) => w.shared && w.sides.any((s) => s.room == current.id),
    )) {
      candidates.addAll(wall.sides.map((s) => s.room));
    }
    CraftObject? best;
    var score = .5;
    for (final id in candidates.where((id) => id != current.id)) {
      final room = model.objects[id]!;
      final delta =
          model.objectPlane(room).point(room.region.bounds.center) - origin;
      final dot = delta.normalized().dot(direction);
      if (dot > score) {
        score = dot;
        best = room;
      }
    }
    _roomZoomConsumed = true;
    if (best != null) _frameRoom(best);
  }
}
