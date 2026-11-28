part of 'protoplane_concept_view.dart';

class _SurfacePick {
  _SurfacePick(this.id, this.planes, this.object);
  final String id;
  final List<String> planes;
  final bool object;
}

class _SurfaceFocus {
  _SurfaceFocus(
    this.picks,
    this.before,
    this.selection,
    this.pinned,
    this.tool,
    this.room,
    this.inspect,
    this.distance,
  );
  final List<_SurfacePick> picks, selection;
  final _Pose before;
  final String? pinned, room;
  final ConstructionTool? tool;
  final bool inspect;
  final double distance;
}

extension _SurfaceView on _ProtoplaneConceptViewState {
  void _paintDoorSwing() {
    for (final room in model.objects.values.where(
      (o) => o.kind == CraftKind.room,
    )) {
      for (final opening in room.openings.where(
        (o) => o.isFlap && o.kind == 'door' && _swingingDoorIds.contains(o.id),
      )) {
        final panel = roomPanels(
          room,
          model.objectPlane(room),
        ).firstWhere((p) => p.key == opening.wall);
        final frame = doorLeafFrame(
          panel.frame,
          opening,
          Curves.easeInOut.transform(_doorSwing.value),
        );
        for (final mesh in scene.meshes.where(
          (m) => m.id.startsWith('${room.id}-leaf-${opening.id}-'),
        )) {
          mesh.geometry = regionGeometry(
            mesh.id,
            frame,
            doorLeafRegion(opening),
            roomThickness,
          );
        }
      }
    }
    scene.markNeedsPaint();
  }

  void _replaceSharedWallMeshes(List<Mesh> meshes) {
    _sharedMeshRooms.clear();
    if (_opening) return;
    final walls = model.walls;
    for (final wall in walls.where((w) => w.shared)) {
      // Replace only shared intervals; keep unshared portions of a long panel.
      for (final side in wall.sides) {
        meshes.removeWhere(
          (m) => m.id.startsWith('${side.room}-${side.panel.key}-'),
        );
      }
    }
    final affected = {
      for (final wall in walls.where((w) => w.shared))
        for (final s in wall.sides) '${s.room}/${s.panel.key}',
    };
    for (final wall in walls.where(
      (w) => w.sides.any((s) => affected.contains('${s.room}/${s.panel.key}')),
    )) {
      final side = wall.sides.first;
      final strip = rectangle(
        side.end - side.start,
        side.panel.frame.region.bounds.height,
        origin: Offset(side.start, 0),
      );
      for (final (i, region)
          in side.panel.regions.expand((r) => r.clipTo([strip])).indexed) {
        final id = '${side.room}-${side.panel.key}-shared-${wall.id}-$i';
        final mesh = Mesh(
          id: id,
          name: 'Wall',
          geometry: regionGeometry(id, side.panel.frame, region, roomThickness),
          material: const MaterialModel(
            color: Color(0xfff1f0e9),
            doubleSided: true,
          ),
        );
        meshes.add(mesh);
        _sharedMeshRooms[id] = wall.sides.map((s) => s.room).toSet();
      }
    }
    final leaves = <String, List<String>>{};
    for (final room in model.objects.values.where(
      (o) => o.kind == CraftKind.room,
    )) {
      for (final o in room.openings.where(
        (o) => o.isFlap && o.kind == 'door',
      )) {
        (leaves[o.id!] ??= []).add(room.id);
      }
    }
    for (final entry in leaves.entries.where((e) => e.value.length > 1)) {
      final owners = entry.value;
      meshes.removeWhere(
        (m) => owners
            .skip(1)
            .any((id) => m.id.startsWith('$id-leaf-${entry.key}-')),
      );
      for (final mesh in meshes.where(
        (m) => m.id.startsWith('${owners.first}-leaf-${entry.key}-'),
      )) {
        _sharedMeshRooms[mesh.id] = owners.toSet();
      }
    }
  }

  void _moveIsolated(Offset delta, {double scale = 1, bool orbit = false}) {
    if (_surfaceFocus.isEmpty) return;
    if (_surfaceTransition.isAnimating) return;
    final frame = _surfaceFocus.last, center = camera.target;
    var offset = camera.position - center;
    if (orbit && frame.inspect) {
      offset = Quaternion.axisAngle(
        camera.up,
        -delta.dx * .008,
      ).rotated(offset);
      final right = camera.up.cross(offset).normalized();
      final q = Quaternion.axisAngle(right, delta.dy * .008);
      offset = q.rotated(offset);
      camera.setUp(q.rotated(camera.up));
      camera.setPosition(center + offset);
    } else {
      final right = camera.forward.cross(camera.up).normalized();
      final shift =
          (right * (-delta.dx) + camera.up * delta.dy) *
          (offset.length * .9 / viewport.height);
      camera.setPosition(camera.position + shift);
      camera.setTarget(center + shift);
    }
    if (scale != 1) {
      final next = offset.length / scale;
      if (next > frame.distance * 1.35 && !_zoomExitConsumed) {
        _zoomExitConsumed = true;
        _popSurfaceFocus();
        return;
      }
      camera.setPosition(
        camera.target +
            (camera.position - camera.target).normalized() *
                next.clamp(.5, 100),
      );
    }
    _targetCacheKey = null;
    _applyHighlight();
    _previewConstruction();
    scene.markNeedsPaint();
    _updateFocusUi(() {});
  }

  String? get _workingSurface =>
      _pinnedSurface ??
      (_opening ? model.startingTile : _constructionTarget()?.planeId);
  Set<ConstructionTool> get _availableSurfaceTools {
    if (_opening) return const {ConstructionTool.volume};
    if (_parcelShopping) return const {};
    if (_selection.length > 1 ||
        (_surfaceFocus.isNotEmpty && _surfaceFocus.last.inspect)) {
      return const {};
    }
    if (_selection.length == 1 && _selection.single.planes.length != 1) {
      return const {};
    }
    return model.toolsFor(_workingSurface);
  }

  String? get _surfaceContextName {
    if (_surfaceFocus.isEmpty && _roomZoomLevel == 2) return null;
    if (_surfaceFocus.isNotEmpty && _surfaceFocus.last.picks.length > 1) {
      return '${_surfaceFocus.last.picks.length} selected';
    }
    final p = model.planes[_workingSurface];
    final room = model.objects[p?.roomId ?? _roomFocus ?? _currentRoom];
    return room?.roomName ?? (room == null ? null : 'Room');
  }

  List<Widget> _selectionControls() => _opening
      ? const []
      : [
          IconButton(
            key: const ValueKey('surface-select'),
            tooltip: 'Select',
            isSelected: _selecting,
            onPressed: () {
              _cancelSurfaceGesture();
              _cancelFocusStroke();
              _updateFocusUi(() {
                _selecting = !_selecting;
                model.constructionTool = null;
                model.activePlaneId = null;
              });
            },
            icon: const Icon(Icons.select_all, color: Colors.white),
          ),
          if (_selecting)
            IconButton(
              key: const ValueKey('selection-kind'),
              tooltip: _selectObjects ? 'Objects' : 'Faces',
              onPressed: () {
                _updateFocusUi(() {
                  _selectObjects = !_selectObjects;
                  _selection.clear();
                  _pinnedSurface = null;
                });
              },
              icon: Icon(
                _selectObjects ? Icons.view_in_ar : Icons.crop_square,
                color: Colors.white,
              ),
            ),
          if (_selection.isNotEmpty)
            IconButton(
              key: const ValueKey('surface-focus'),
              tooltip: 'Focus',
              onPressed: _focusSelection,
              icon: const Icon(Icons.visibility, color: Colors.white),
            ),
          if (_surfaceFocus.isNotEmpty)
            IconButton(
              key: const ValueKey('surface-back'),
              tooltip: 'Back',
              onPressed: _popSurfaceFocus,
              icon: const Icon(Icons.arrow_back, color: Colors.white),
            ),
        ];
  bool _surfaceMeshVisible(String mesh) {
    if (_surfaceFocus.isEmpty) return true;
    if (_sharedMeshRooms[mesh] != null &&
        _surfaceFocus.last.picks.any(
          (p) => p.object && _sharedMeshRooms[mesh]!.contains(p.id),
        )) {
      return true;
    }
    for (final pick in _surfaceFocus.last.picks) {
      if (pick.object && (mesh == pick.id || mesh.startsWith('${pick.id}-'))) {
        return true;
      }
      for (final id in pick.planes) {
        final p = model.planes[id];
        if (p == null) continue;
        if (_sharedMeshRooms[mesh]?.contains(p.roomId) == true &&
            mesh.contains('-${p.roomFace}-')) {
          return true;
        }
        if (mesh == id || mesh == p.owner && p.roomFace == null) return true;
        if (p.owner != null &&
            p.roomFace != null &&
            mesh.startsWith('${p.owner}-${p.roomFace}-')) {
          return true;
        }
        if (mesh.startsWith('sticker-preview-')) return true;
        final o = model.objects[mesh];
        if (o != null && model.objectPlane(o).id == id) return true;
      }
    }
    return false;
  }

  bool _surfaceAllowed(CraftPlane p) {
    if (_opening) return p.id == model.startingTile;
    if (p.roomFace == 'roof') return false;
    if (_surfaceFocus.isEmpty) return true;
    return _surfaceFocus.last.picks.any(
      (pick) =>
          pick.planes.contains(p.id) ||
          (pick.object && (p.owner == pick.id || p.roomId == pick.id)),
    );
  }

  Map<String, Path> _visibleSurfacePaths() {
    final key =
        '${camera.position}/${camera.target}/${camera.up}/$viewport/${Object.hashAll(model.planes.values)}/${_surfaceFocus.map((f) => f.picks.map((p) => p.id).join(",")).join("/")}/$_roomFocus/${_roomReveal.value}';
    if (_visiblePathsKey == key) return _visiblePathsCache;
    final result = <String, Path>{};
    for (final p in model.planes.values) {
      if (!_surfaceAllowed(p) ||
          (!p.id.startsWith('surface-') &&
              !model.landscape.terrain.tiles.containsKey(p.id))) {
        continue;
      }
      if (p.normal.dot(camera.position - p.origin) <= geometryEpsilon) continue;
      if (model.landscape.terrain.tiles.containsKey(p.id) &&
          !model.ownsTerrainTile(p.id)) {
        continue;
      }
      final path = Path()..fillType = PathFillType.evenOdd;
      for (final ring in p.region.rings) {
        final points = ring
            .map((v) => camera.projectToScreen(p.point(v, .009), viewport))
            .toList();
        if (points.any((v) => v == null)) continue;
        path.addPolygon(points.cast<Offset>(), true);
      }
      if (!path.getBounds().overlaps(Offset.zero & viewport)) continue;
      final visible = Path.combine(
        PathOperation.difference,
        path,
        drawingOcclusion(scene, camera, viewport, p),
      );
      if (!visible.getBounds().isEmpty) result[p.id] = visible;
    }
    _visiblePathsKey = key;
    return _visiblePathsCache = result;
  }

  void _chooseSurface(Offset a, Offset b, {bool tap = false}) {
    final paths = _visibleSurfacePaths(), hits = <String>[];
    final objectPaths = <String, Path>{};
    if (_selectObjects) {
      for (final e in paths.entries) {
        final owner = model.planes[e.key]!.owner ?? e.key;
        objectPaths[owner] = objectPaths[owner] == null
            ? e.value
            : Path.combine(PathOperation.union, objectPaths[owner]!, e.value);
      }
    }
    final rect = Rect.fromPoints(a, b), box = Path()..addRect(rect);
    final contain = marqueePick(a, b).name == 'contain';
    for (final e in paths.entries) {
      final path = _selectObjects
          ? objectPaths[model.planes[e.key]!.owner ?? e.key]!
          : e.value;
      final bounds = path.getBounds();
      final hit = tap
          ? path.contains(b)
          : contain
          ? rect.contains(bounds.topLeft) && rect.contains(bounds.bottomRight)
          : !Path.combine(
              PathOperation.intersect,
              path,
              box,
            ).getBounds().isEmpty;
      if (hit) hits.add(e.key);
    }
    if (tap && hits.length > 1) {
      hits.sort(
        (a, b) => (model.planes[a]!.origin - camera.position).length.compareTo(
          (model.planes[b]!.origin - camera.position).length,
        ),
      );
      hits.removeRange(1, hits.length);
    }
    final groups = <String, List<String>>{};
    for (final id in hits) {
      final p = model.planes[id]!;
      final key = _selectObjects ? p.owner ?? id : id;
      (groups[key] ??= []).add(id);
    }
    _selection.clear();
    _selectedPaths = {for (final id in hits) id: paths[id]!};
    for (final e in groups.entries) {
      final ids = _selectObjects && model.objects.containsKey(e.key)
          ? model.planes.values
                .where((p) => p.owner == e.key && p.roomFace != 'roof')
                .map((p) => p.id)
                .toList()
          : e.value;
      _selection.add(_SurfacePick(e.key, ids, _selectObjects));
    }
    _pinnedSurface =
        _selection.length == 1 && _selection.single.planes.length == 1
        ? _selection.single.planes.single
        : null;
    final rebuild =
        model.activePlaneId != null || _constructionEvaluation != null;
    model.constructionTool = null;
    model.activePlaneId = null;
    _constructionEvaluation = null;
    _constructionPreviewKey = null;
    if (rebuild) {
      _refreshScene();
    } else {
      _applyHighlight();
    }
    _updateFocusUi(() {});
  }

  void _focusSelection() {
    if (_selection.isEmpty) return;
    final picks = List<_SurfacePick>.of(_selection);
    if (_surfaceFocus.isNotEmpty &&
        _surfaceFocus.last.picks.map((p) => p.id).join('|') ==
            picks.map((p) => p.id).join('|')) {
      return;
    }
    final planes = picks
        .expand((p) => p.planes)
        .map((id) => model.planes[id])
        .whereType<CraftPlane>()
        .toList();
    if (planes.isEmpty) return;
    final normal = planes.first.normal;
    final inspect = planes.any(
      (p) => normal.dot(p.normal) < math.cos(5 * math.pi / 180),
    );
    final points = [
      for (final p in planes)
        for (final node in p.region.outer) p.point(node),
    ];
    final center = points.reduce((a, b) => a + b) / points.length.toDouble();
    final radius = points.map((p) => (p - center).length).reduce(math.max);
    final distance = math.max(
      1.5,
      radius /
          math.sin(camera.fovDegrees * math.pi / 360) /
          math.min(1.0, viewport.aspectRatio) *
          1.25,
    );
    _surfaceFocus.add(
      _SurfaceFocus(
        picks,
        _Pose(camera),
        List.of(_selection),
        _pinnedSurface,
        model.constructionTool,
        _roomFocus,
        inspect,
        distance,
      ),
    );
    _cancelSurfaceGesture();
    _cancelFocusStroke();
    model.constructionTool = null;
    model.activePlaneId = null;
    _roomFocus = null;
    _pinnedSurface = planes.length == 1 ? planes.single.id : null;
    _selecting = false;
    final direction = inspect
        ? (camera.position - camera.target).normalized()
        : normal;
    final up = inspect ? camera.up : planes.first.v;
    _animateSurfacePose(center + direction * distance, center, up);
    _roomReveal.forward();
  }

  void _animateSurfacePose(Vector3 position, Vector3 target, Vector3 up) {
    mapCamera.pauseForHandoff();
    final before = _Pose(camera);
    _selectedPaths = {};
    _surfaceTransition.stop();
    _surfaceTransition.duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 350);
    void tick() {
      final t = Curves.easeInOut.transform(_surfaceTransition.value);
      final center = before.target * (1 - t) + target * t;
      final from = (before.position - before.target).normalized(),
          to = (position - target).normalized();
      var direction = from * (1 - t) + to * t;
      if (direction.length < .001) direction = up.cross(to);
      direction.normalize();
      final d =
          (before.position - before.target).length * (1 - t) +
          (position - target).length * t;
      camera.setPosition(center + direction * d);
      camera.setTarget(center);
      var u = before.up * (1 - t) + up * t;
      if (u.length < .001) u = up.clone();
      if (u.normalized().dot(direction).abs() > .999) u = up.clone();
      camera.setUp(u.normalized());
      _targetCacheKey = null;
      _applyHighlight();
      scene.markNeedsPaint();
      if (mounted) _updateFocusUi(() {});
    }

    _surfaceTransition.addListener(tick);
    _surfaceTransition
        .forward(from: 0)
        .whenCompleteOrCancel(() => _surfaceTransition.removeListener(tick));
    _updateFocusUi(() {});
  }

  void _popSurfaceFocus() {
    if (_surfaceFocus.isEmpty) return;
    final frame = _surfaceFocus.removeLast();
    _cancelSurfaceGesture();
    _cancelFocusStroke();
    _selection
      ..clear()
      ..addAll(
        frame.selection.where((p) => p.planes.any(model.planes.containsKey)),
      );
    _pinnedSurface = model.planes.containsKey(frame.pinned)
        ? frame.pinned
        : null;
    model.constructionTool = model.toolsFor(_pinnedSurface).contains(frame.tool)
        ? frame.tool
        : null;
    model.activePlaneId = model.constructionTool == null
        ? null
        : _pinnedSurface;
    _roomFocus = frame.room;
    final current = _Pose(camera);
    if (_surfaceFocus.isEmpty) {
      mapCamera.restorePose(
        lookAt: frame.before.target,
        distance: (frame.before.position - frame.before.target).length,
        yaw: math.pi / 2,
      );
    }
    camera.setPosition(current.position);
    camera.setTarget(current.target);
    camera.setUp(current.up);
    _animateSurfacePose(
      frame.before.position,
      frame.before.target,
      frame.before.up,
    );
    if (_surfaceFocus.isEmpty && _roomFocus == null) _roomReveal.reverse();
    _refreshScene();
  }

  void _validateSurfaceContext() {
    while (_surfaceFocus.isNotEmpty &&
        _surfaceFocus.last.picks.any(
          (p) => !p.planes.any(model.planes.containsKey),
        )) {
      final frame = _surfaceFocus.removeLast();
      camera.setPosition(frame.before.position);
      camera.setTarget(frame.before.target);
      camera.setUp(frame.before.up);
      _roomFocus = frame.room;
    }
    _selection.removeWhere((p) => !p.planes.any(model.planes.containsKey));
    if (!model.planes.containsKey(_pinnedSurface)) _pinnedSurface = null;
    if (_pinnedSurface != null &&
        model.constructionTool != null &&
        !model.toolsFor(_pinnedSurface).contains(model.constructionTool)) {
      model.constructionTool = null;
      model.activePlaneId = null;
      _cancelSurfaceGesture();
    }
    if (_opening) {
      if (_roomFocus != null || _pinnedSurface != model.startingTile) {
        _roomFocus = null;
        _surfaceFocus.clear();
        _selection.clear();
        _roomReveal.value = 0;
        mapCamera.restorePose(
          lookAt: Vector3(.5, 0, -.5),
          distance: 2.5,
          yaw: math.pi / 2,
        );
        camera.setUp(Vector3(0, 0, -1));
      }
      model.constructionTool = ConstructionTool.volume;
      model.activePlaneId = model.startingTile;
      _pinnedSurface = model.startingTile;
    }
  }

  bool _surfaceScroll(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return false;
    if (_zoomExitConsumed) {
      _zoomExitTimer?.cancel();
      _zoomExitTimer = Timer(
        const Duration(milliseconds: 350),
        () => _zoomExitConsumed = false,
      );
      return true;
    }
    if (_surfaceFocus.isEmpty) return false;
    final d = (camera.position - camera.target).length;
    final next = d * math.exp(event.scrollDelta.dy * .002);
    if (next > _surfaceFocus.last.distance * 1.35) {
      _zoomExitConsumed = true;
      _popSurfaceFocus();
      _zoomExitTimer?.cancel();
      _zoomExitTimer = Timer(
        const Duration(milliseconds: 350),
        () => _zoomExitConsumed = false,
      );
    } else {
      camera.setPosition(
        camera.target +
            (camera.position - camera.target).normalized() *
                next.clamp(.5, 100),
      );
      _targetCacheKey = null;
      _applyHighlight();
      _previewConstruction();
      scene.markNeedsPaint();
      _updateFocusUi(() {});
    }
    return true;
  }

  void _cancelSurfaceGesture() {
    _surfacePath = [];
    _strokeSurface = null;
    _marqueeStart = _marqueeEnd = null;
    _constructionEvaluation = null;
    _constructionPreviewKey = null;
  }

  bool _surfaceDown(PointerDownEvent e) {
    if (loading ||
        loadFailed ||
        devToolsOpen ||
        _surfaceTransition.isAnimating) {
      return false;
    }
    if (_drawingFocused) return false;
    if (_surfaceFocus.isNotEmpty &&
        (e.buttons & (kSecondaryMouseButton | kMiddleMouseButton) != 0 ||
            pointers.isNotEmpty)) {
      _cancelSurfaceGesture();
      _isolateNavigation = true;
      pointers[e.pointer] = e.localPosition;
      down = previous = e.localPosition;
      moved = true;
      lastSpan = pointers.length > 1
          ? (pointers.values.first - pointers.values.last).distance
          : 0;
      controls.begin(e.kind, e.localPosition);
      return true;
    }
    if (!_selecting && !_surfaceDrawing) {
      if (_surfaceFocus.isEmpty) return false;
      pointers[e.pointer] = e.localPosition;
      down = previous = e.localPosition;
      moved = false;
      lastSpan = pointers.length > 1
          ? (pointers.values.first - pointers.values.last).distance
          : 0;
      controls.begin(e.kind, e.localPosition);
      return true;
    }
    if (e.buttons & (kSecondaryMouseButton | kMiddleMouseButton) != 0) {
      return false;
    }
    if (pointers.isNotEmpty) {
      _surfaceMulti = true;
      _cancelSurfaceGesture();
      return false;
    }
    _surfaceMulti = false;
    pointers[e.pointer] = e.localPosition;
    down = previous = e.localPosition;
    moved = false;
    multi = false;
    controls.begin(e.kind, e.localPosition);
    if (_selecting) {
      _marqueeStart = _marqueeEnd = e.localPosition;
      _updateFocusUi(() {});
      return true;
    }
    final target = _opening
        ? (
            planeId: model.startingTile,
            surface: model.drawingSurfaceFor(model.startingTile)!,
            point: Offset.zero,
          )
        : _resolveConstructionTarget(aim: e.localPosition);
    final id = _pinnedSurface ?? target?.planeId;
    if (id == null || !model.toolsFor(id).contains(model.constructionTool)) {
      return true;
    }
    _strokeSurface = id;
    _pinnedSurface = id;
    model.activePlaneId = id;
    final node = _surfaceNode(e.localPosition, id);
    if (node != null) _surfacePath = [node];
    _updateFocusUi(() {});
    return true;
  }

  Offset? _surfaceNode(Offset screen, String id) {
    final surface = model.drawingSurfaceFor(id)!, grid = model.surfaceGrid(id);
    final mask = drawingOcclusion(scene, camera, viewport, surface.frame);
    var distance = 24.0;
    Offset? best;
    for (final node in grid.nodes) {
      final at = camera.projectToScreen(
        surface.frame.point(node, .009),
        viewport,
      );
      if (at != null &&
          !mask.contains(at) &&
          (at - screen).distance < distance) {
        distance = (at - screen).distance;
        best = node;
      }
    }
    return best;
  }

  bool _surfaceMove(PointerMoveEvent e) {
    if (!_drawingFocused &&
        _surfaceFocus.isNotEmpty &&
        (_isolateNavigation || (!_selecting && !_surfaceDrawing)) &&
        pointers.containsKey(e.pointer)) {
      final prior = pointers[e.pointer]!;
      pointers[e.pointer] = e.localPosition;
      if ((e.localPosition - (down ?? e.localPosition)).distance > 6) {
        moved = true;
      }
      var ratio = 1.0;
      if (pointers.length > 1) {
        final span = (pointers.values.first - pointers.values.last).distance;
        ratio = lastSpan == 0 ? 1 : span / lastSpan;
        lastSpan = span;
      }
      _moveIsolated(
        e.localPosition - prior,
        scale: ratio,
        orbit:
            !_isolateNavigation &&
            pointers.length == 1 &&
            e.buttons & (kSecondaryMouseButton | kMiddleMouseButton) == 0,
      );
      return true;
    }
    if (_surfaceMulti) return false;
    if (_marqueeStart != null) {
      _marqueeEnd = e.localPosition;
      _updateFocusUi(() {});
      return true;
    }
    final id = _strokeSurface;
    if (id == null) return false;
    if (_surfacePath.isEmpty) return true;
    final next = _surfaceNode(e.localPosition, id),
        grid = model.surfaceGrid(id);
    if (next == null || near(next, _surfacePath.last)) return true;
    final a = grid.nodes.indexWhere((n) => near(n, _surfacePath.last)),
        b = grid.nodes.indexWhere((n) => near(n, next));
    final route = grid.collinearRoute(a, b);
    if (route == null) return true;
    for (final index in route) {
      final n = grid.nodes[index];
      if (near(n, _surfacePath.last)) continue;
      if (_surfacePath.length > 1 &&
          near(n, _surfacePath[_surfacePath.length - 2])) {
        _surfacePath.removeLast();
      } else {
        _surfacePath.add(n);
      }
    }
    if (model.constructionTool == ConstructionTool.volume &&
        _surfacePath.length > 3 &&
        near(_surfacePath.first, _surfacePath.last)) {
      _constructionEvaluation = model.evaluateVolumeStroke(id, _surfacePath);
      _refreshScene();
    } else if (model.constructionTool == ConstructionTool.scissors &&
        _surfacePath.length >= 4) {
      _constructionEvaluation = model.evaluateCutStroke(id, _surfacePath);
      _refreshScene();
    } else if (_constructionEvaluation != null) {
      _constructionEvaluation = null;
      _refreshScene();
    }
    _updateFocusUi(() {});
    return true;
  }

  bool _surfaceUp(PointerUpEvent e) {
    if (!_drawingFocused &&
        _surfaceFocus.isNotEmpty &&
        (_isolateNavigation || (!_selecting && !_surfaceDrawing)) &&
        pointers.containsKey(e.pointer)) {
      pointers.remove(e.pointer);
      controls.end();
      if (pointers.isEmpty) {
        _zoomExitConsumed = false;
        _isolateNavigation = false;
        _surfaceMulti = false;
        if (!moved) {
          if (!_handleRoomBackgroundTap(e.localPosition)) {
            if (_placingConstruction) {
              _placeConstruction();
            } else {
              _chooseSurface(e.localPosition, e.localPosition, tap: true);
            }
          }
        }
      }
      return true;
    }
    if (_surfaceMulti) {
      if (pointers.length <= 1) _surfaceMulti = false;
      return false;
    }
    if (_marqueeStart != null) {
      final a = _marqueeStart!;
      _chooseSurface(
        a,
        e.localPosition,
        tap: (a - e.localPosition).distance < 6,
      );
      _marqueeStart = _marqueeEnd = null;
      pointers.remove(e.pointer);
      controls.end();
      _updateFocusUi(() {});
      return true;
    }
    final id = _strokeSurface;
    if (id == null) return false;
    final path = List<Offset>.of(_surfacePath), tool = model.constructionTool;
    pointers.remove(e.pointer);
    controls.end();
    _surfacePath = [];
    _strokeSurface = null;
    final opening = _opening;
    var applied = false;
    if (tool == ConstructionTool.volume &&
        path.length > 3 &&
        near(path.first, path.last)) {
      applied = model.applyVolumeStroke(id, path);
    }
    if (tool == ConstructionTool.scissors) {
      applied = model.cutSurfaceStroke(id, path);
    }
    if (applied) {
      if (tool == ConstructionTool.volume) {
        final room = model.objects.values.last;
        model.constructionTool = null;
        model.activePlaneId = null;
        _pinnedSurface = 'surface-${room.id}-floor-in-0';
        _frameRoom(room, animate: !opening);
      }
    } else if (path.isNotEmpty) {
      _fadingSurfacePath = path;
      _strokeFade.value = 1;
      _strokeFade.reverse();
      _strokeFadeTimer?.cancel();
      _strokeFadeTimer = Timer(
        MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 180),
        () {
          if (mounted) _updateFocusUi(() => _fadingSurfacePath = []);
        },
      );
    }
    _constructionEvaluation = null;
    _constructionPreviewKey = null;
    _refreshScene();
    _updateFocusUi(() {});
    return true;
  }
}

class _SurfaceGesturePainter extends CustomPainter {
  _SurfaceGesturePainter(this.state);
  final _ProtoplaneConceptViewState state;
  @override
  void paint(Canvas canvas, Size size) {
    final s = state;
    for (final path in s._selectedPaths.values) {
      canvas.drawPath(
        path,
        Paint()..color = Colors.lightBlueAccent.withValues(alpha: .18),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.lightBlueAccent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    if (s._marqueeStart != null && s._marqueeEnd != null) {
      AsmrMarqueePainter(
        start: s._marqueeStart!,
        end: s._marqueeEnd!,
      ).paint(canvas, size);
    }
    final id = s._strokeSurface ?? s._workingSurface;
    if (id == null || !s.model.planes.containsKey(id)) return;
    if (!s._surfaceDrawing &&
        s._fadingSurfacePath.isEmpty &&
        (s._selecting ||
            !s.model.toolsFor(id).contains(ConstructionTool.volume))) {
      return;
    }
    final surface = s.model.drawingSurfaceFor(id)!;
    Offset? project(Offset p) =>
        s.camera.projectToScreen(surface.frame.point(p, .009), size);
    final mask = drawingOcclusion(s.scene, s.camera, size, surface.frame);
    for (final node in s.model.surfaceGrid(id).nodes) {
      final p = project(node);
      if (p == null || mask.contains(p)) continue;
      canvas.drawCircle(p, 5, Paint()..color = const Color(0xffece8dd));
      canvas.drawCircle(p, 2.5, Paint()..color = const Color(0xff333333));
    }
    final points = s._surfacePath.isNotEmpty
        ? s._surfacePath
        : s._fadingSurfacePath;
    for (var i = 1; i < points.length; i++) {
      final a = project(points[i - 1]), b = project(points[i]);
      if (a == null || b == null) continue;
      canvas.drawLine(
        a,
        b,
        Paint()
          ..color = Colors.orange.withValues(
            alpha: s._surfacePath.isNotEmpty ? 1 : s._strokeFade.value,
          )
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SurfaceGesturePainter old) => true;
}
