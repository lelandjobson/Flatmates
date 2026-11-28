part of 'protoplane_concept_view.dart';

extension _FocusTools on _ProtoplaneConceptViewState {
  bool _handleRoomBackgroundTap(Offset point) {
    if ((_roomFocus == null && _surfaceFocus.isEmpty) ||
        _drawingFocused ||
        devToolsOpen ||
        _parcelShopping) {
      return false;
    }
    final hits =
        SceneHitTester(
          scene: scene,
          camera: camera,
          viewportSize: viewport,
        ).hitTestAll(
          point,
          includeMesh: (mesh) =>
              mesh.visible &&
              mesh.material.opacity > .05 &&
              !mesh.id.startsWith('sticker-preview-'),
        );
    if (hits.isNotEmpty) {
      _backgroundTapTimer?.cancel();
      _backgroundTapPoint = null;
      return false;
    }
    if (_backgroundTapTimer?.isActive == true &&
        _backgroundTapPoint != null &&
        (point - _backgroundTapPoint!).distance < 28) {
      _backgroundTapTimer!.cancel();
      _backgroundTapPoint = null;
      _exitRoom();
      return true;
    }
    _backgroundTapTimer?.cancel();
    _backgroundTapPoint = point;
    final pose = _Pose(camera);
    final tool = model.constructionTool;
    final room = _roomFocus;
    _backgroundTapTimer = Timer(const Duration(milliseconds: 300), () {
      _backgroundTapPoint = null;
      if (!mounted ||
          _roomFocus != room ||
          pointers.isNotEmpty ||
          model.constructionTool != tool ||
          devToolsOpen ||
          _parcelShopping ||
          (camera.position - pose.position).length > .0001 ||
          (camera.target - pose.target).length > .0001) {
        return;
      }
      if (_placingConstruction) _placeConstruction();
    });
    return true;
  }

  Future<void> _exitRoom() async {
    if (_surfaceFocus.isNotEmpty) {
      _popSurfaceFocus();
      return;
    }
    if (_roomFocus == null || _exitingRoom) return;
    _exitingRoom = true;
    _backgroundTapTimer?.cancel();
    _backgroundTapPoint = null;
    controls.cancel();
    pointers.clear();
    mapCamera.pauseForHandoff();
    _cancelFocusStroke();
    model.constructionTool = null;
    if (model.activePlane != null) model.leave();
    _constructionEvaluation = null;
    _constructionPreviewKey = null;
    await _roomReveal.reverse();
    if (!mounted) return;
    final pose = _beforeRoom, map = _roomMapPose;
    _roomFocus = null;
    _exitingRoom = false;
    if (map != null) {
      mapCamera.restorePose(
        lookAt: map.lookAt,
        distance: map.distance,
        yaw: map.yaw,
      );
    }
    if (pose != null) {
      camera.setPosition(pose.position);
      camera.setTarget(pose.target);
      camera.setUp(pose.up);
      camera.fovDegrees = pose.fov;
    }
    _refreshScene();
    _updateFocusUi(() {});
  }

  Widget _housingHud() => Wrap(
    key: const ValueKey('housing-hud'),
    alignment: WrapAlignment.center,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 8,
    children: [
      DevToolsButton(active: devToolsOpen, onPressed: _toggleDevTools),
      _button('Back', Icons.arrow_back, () {
        if (_roomFocus != null || _surfaceFocus.isNotEmpty) {
          _exitRoom();
        } else if (model.activePlane != null) {
          _selectConstructionTool(ConstructionTool.pencil);
        } else {
          context.goNamed('dev_routes');
        }
      }),
      Text(
        'Day ${model.housing.day} · ${model.housing.phase.name[0].toUpperCase()}${model.housing.phase.name.substring(1)}',
        style: const TextStyle(color: Colors.white),
      ),
      Text(
        '${model.housing.coins} coins',
        style: const TextStyle(color: Colors.white),
      ),
      IconButton(
        key: const ValueKey('advance-phase'),
        tooltip: 'Advance time',
        onPressed: loading || loadFailed
            ? null
            : () {
                _cancelFocusStroke();
                model.advancePhase();
              },
        icon: const Icon(Icons.skip_next, color: Colors.white),
      ),
      IconButton(
        key: const ValueKey('resident-inspection'),
        tooltip: 'Residents',
        onPressed: _inspectResidents,
        icon: const Icon(Icons.people, color: Colors.white),
      ),
      GameViewUndoRedoBar(
        canUndo: model.canUndo && !loading && !loadFailed,
        canRedo: model.canRedo && !loading && !loadFailed,
        onUndo: model.undo,
        onRedo: model.redo,
      ),
      if (saving)
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      if (_roomFocus != null)
        IconButton(
          key: const ValueKey('exit-room'),
          tooltip: 'Exit room',
          onPressed: _exitRoom,
          icon: const Icon(Icons.close_fullscreen, color: Colors.white),
        ),
      if (model.canClaimSupplies)
        TextButton(
          key: const ValueKey('emergency-supplies'),
          onPressed: model.claimSupplies,
          child: const Text('Emergency supplies'),
        ),
      if (model.housing.result != null)
        Text(
          model.housing.result!,
          style: const TextStyle(color: Colors.white70),
        ),
    ],
  );

  void _inspectResidents() {
    final reviews = {for (final r in model.roomReviews) r.room.id: r};
    Widget details(Tenant tenant) {
      final review = reviews[tenant.roomId];
      final count = model.housing.tenants.values
          .where((t) => t.roomId == tenant.roomId)
          .length;
      final name =
          model.objects[tenant.blanketId]?.constructionName ?? 'No blanket';
      final space =
          review != null &&
          review.reachable.length * RoomReview.step * RoomReview.step >=
              count * .5;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cube Boy · ${tenant.id}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              '${tenant.rating}/100 · ${tenant.usable ? HousingBalance.rent(tenant.rating) : 0} coins/day',
            ),
            Text('$name · Sleeping place +${tenant.usable ? 40 : 0}'),
            Text(
              'Blanket +${tenant.usable && name == "large blanket" ? 20 : 0} · Window +${tenant.usable && review?.hasWindow == true ? 20 : 0} · Space +${tenant.usable && space ? 20 : 0}',
            ),
            Text(
              'Departure risk ${tenant.usable ? (HousingBalance.departure(tenant.rating) * 100).round() : 100}%',
            ),
          ],
        ),
      );
    }

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Residents · ${model.housing.tenants.length}'),
        content: SizedBox(
          width: 320,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .55,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final tenant in model.housing.tenants.values)
                    details(tenant),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _cancelFocusStroke() {
    _focusPath.clear();
    _focusLiveScreen = null;
    _eraseStart = _eraseEnd = null;
    _focusGestureSurface = null;
  }

  int? _focusNode(Offset screen) {
    final surface = model.drawingSurface, grid = model.focusDrawingGrid;
    if (surface == null || grid == null) return null;
    var best = 20.0;
    int? result;
    for (final (i, p) in grid.nodes.indexed) {
      final at = camera.projectToScreen(surface.frame.point(p, .009), viewport);
      if (at != null && (at - screen).distance < best) {
        best = (at - screen).distance;
        result = i;
      }
    }
    return result;
  }

  bool _focusPointerDown(PointerDownEvent e) {
    if (!_drawingFocused || devToolsOpen || loading || loadFailed) {
      return false;
    }
    _focusTouches[e.pointer] = e.localPosition;
    _focusLiveScreen = e.localPosition;
    _updateFocusUi(() {});
    controls.move(e.kind, e.localPosition);
    if (_focusTouches.length > 1) {
      _cancelFocusStroke();
      _focusHadMultiple = true;
      _roomPinch = 1;
      _roomZoomConsumed = false;
      planeSwipe.start(_focusTouches.values);
      multiMoved.clear();
      lastSpan =
          (_focusTouches.values.first - _focusTouches.values.last).distance;
      _updateFocusUi(() {});
      return true;
    }
    controls.begin(e.kind, e.localPosition);
    _focusHadMultiple = false;
    if (e.buttons & (kSecondaryMouseButton | kMiddleMouseButton) != 0) {
      return true;
    }

    final surface = model.drawingSurface;
    if (surface == null) return true;
    _focusGestureSurface = surface.id;
    if (model.drawingImplement == DrawingImplement.eraser) {
      _eraseStart = _eraseEnd = _localOn(surface.frame, e.localPosition, .009);
    } else {
      final node = _focusNode(e.localPosition);
      if (node != null) _focusPath.add(node);
    }
    _updateFocusUi(() {});
    return true;
  }

  bool _focusPointerMove(PointerMoveEvent e) {
    if (!_focusTouches.containsKey(e.pointer)) return false;
    final prior = _focusTouches[e.pointer]!;
    final oldSpan = _focusTouches.length > 1
        ? (_focusTouches.values.first - _focusTouches.values.last).distance
        : 0.0;
    _focusTouches[e.pointer] = e.localPosition;
    _focusLiveScreen = e.localPosition;
    _updateFocusUi(() {});
    controls.move(e.kind, e.localPosition);
    if (_focusTouches.length > 1) {
      final span =
          (_focusTouches.values.first - _focusTouches.values.last).distance;
      final scale = oldSpan > 0 ? span / oldSpan : 1.0;
      if (_surfaceFocus.isNotEmpty) {
        _moveIsolated((e.localPosition - prior) / 2, scale: scale);
      } else if (_currentRoom != null) {
        multiMoved.add(e.pointer);
        if (multiMoved.length < 2) return true;
        multiMoved.clear();
        final swipe = planeSwipe.update(
          _focusTouches.values,
          PlaneSwipe.threshold(viewport),
        );
        if (swipe != null) _swipeRoom(swipe);
        if (lastSpan > 0) _roomPinch *= span / lastSpan;
        lastSpan = span;
        _stepRoomZoom(_roomPinch);
      } else {
        mapCamera.pan((e.localPosition - prior) / 2);
        mapCamera.zoomByScale(scale);
      }
      return true;
    }
    if (_focusHadMultiple || _focusGestureSurface != model.drawingSurface?.id) {
      return true;
    }
    if (_eraseStart != null) {
      _eraseEnd = _localOn(model.drawingSurface!.frame, e.localPosition, .009);
      _updateFocusUi(() {});
      return true;
    }
    if (_focusPath.isEmpty) return true;
    final next = _focusNode(e.localPosition), grid = model.focusDrawingGrid!;
    if (next == null || next == _focusPath.last) return true;
    final a = grid.nodes[_focusPath.last], b = grid.nodes[next];
    final d = model.drawingImplement.toLattice(b - a);
    if (d.dx.abs() > 1e-6 && d.dy.abs() > 1e-6) return true;
    final route =
        grid.nodes.indexed
            .where((n) => n.$1 != _focusPath.last && onSegment(n.$2, a, b))
            .toList()
          ..sort((x, y) => (x.$2 - a).distance.compareTo((y.$2 - a).distance));
    var previous = _focusPath.last;
    for (final node in route) {
      if (grid.connection(previous, node.$1) == null) return true;
      previous = node.$1;
    }
    // Walk each pip, including skipped pointer samples, so retracing removes
    // the pending tail rather than drawing a second edge over it.
    for (final node in route) {
      if (_focusPath.length > 1 &&
          node.$1 == _focusPath[_focusPath.length - 2]) {
        _focusPath.removeLast();
      } else {
        _focusPath.add(node.$1);
      }
    }
    _updateFocusUi(() {});
    return true;
  }

  bool _focusPointerUp(PointerUpEvent e) {
    if (!_focusTouches.containsKey(e.pointer)) return false;
    _focusTouches.remove(e.pointer);
    if (_focusTouches.isNotEmpty) return true;
    controls.end();
    if (!_focusHadMultiple &&
        _focusGestureSurface == model.drawingSurface?.id) {
      if (_eraseStart != null && _eraseEnd != null) {
        model.eraseDrawingLine(_eraseStart!, _eraseEnd!);
      } else if (_focusPath.length > 1) {
        final grid = model.focusDrawingGrid!;
        model.commitDrawingPath(_focusPath.map((n) => grid.nodes[n]).toList());
      }
    }
    _cancelFocusStroke();
    _updateFocusUi(() {});
    return true;
  }

  bool _focusPointerCancel(PointerCancelEvent e) {
    if (!_focusTouches.containsKey(e.pointer)) return false;
    _focusTouches.remove(e.pointer);
    controls.cancel();
    _cancelFocusStroke();
    _focusHadMultiple = true;
    _updateFocusUi(() {});
    return true;
  }

  void _selectConstructionTool(ConstructionTool requested) {
    _backgroundTapTimer?.cancel();
    if (loading || loadFailed || devToolsOpen) return;
    final next = model.constructionTool == requested ? null : requested;
    final target = next == ConstructionTool.pencil && !_parcelShopping
        ? (_pinnedSurface != null && model.planes.containsKey(_pinnedSurface)
              ? (
                  planeId: _pinnedSurface!,
                  surface: model.drawingSurfaceFor(_pinnedSurface!)!,
                  point: Offset.zero,
                )
              : _constructionTarget())
        : null;
    if (next != null && !_availableSurfaceTools.contains(next)) return;
    _selecting = false;
    if (next == null && _selection.isEmpty) _pinnedSurface = null;
    if (next != null) {
      _pinnedSurface ??= target?.planeId ?? _constructionTarget()?.planeId;
    }
    if (next == ConstructionTool.paper) {
      model.constructionPaper = ConstructionPaper.cloth;
    }
    _cancelSurfaceGesture();
    _cancelFocusStroke();
    _focusTouches.clear();
    pointers.clear();
    controls.cancel();
    drawing = pulling = pencilDragging = false;
    trackpadActive = false;
    mapCamera.pauseForHandoff();
    focusZoom.stop();
    transition.stop();
    _constructionEvaluation = null;
    _constructionPreviewKey = null;
    model.constructionTool = null;
    if (model.activePlane != null) {
      worldPose = _Pose(camera);
      model.leave();
      transition.stop();
    }
    if (next == ConstructionTool.pencil) {
      if (target == null) {
        model.report('Aim at a drawable paper surface');
      } else {
        model.constructionTool = next;
        model.drawingImplement = model.lastDrawingImplement =
            DrawingImplement.pencil;
        model.enter(target.planeId);
        if (model.activePlane == null) model.constructionTool = null;
      }
    } else {
      model.constructionTool = next;
      if (_surfaceDrawing) model.activePlaneId = _pinnedSurface;
    }
    _previewConstruction();
    _refreshScene();
    _updateFocusUi(() {});
  }

  ({String planeId, DrawingSurface surface, Offset point})?
  _constructionTarget({bool fresh = false}) {
    final key =
        '${controls.worldAim(viewport)}/$viewport/${camera.position}/${camera.target}/${camera.up}/${camera.fovDegrees}/${camera.projection}/${camera.orthographicScale}/$_roomFocus/${_roomReveal.value}';
    if (!fresh && _targetCacheKey == key) return _targetCache;
    _targetCacheKey = key;
    return _targetCache = _resolveConstructionTarget();
  }

  ({String planeId, DrawingSurface surface, Offset point})?
  _resolveConstructionTarget({Offset? aim}) {
    if (viewport.isEmpty) return null;
    aim ??= controls.worldAim(viewport);
    final ray = camera.unprojectRay(aim, viewport);
    if (ray == null) return null;
    CraftPlane? best;
    var distance = double.infinity;
    for (final plane in model.planes.values) {
      if (!_surfaceAllowed(plane)) continue;
      final terrain = model.landscape.terrain.tiles.containsKey(plane.id);
      if (!terrain && !plane.id.startsWith('surface-')) continue;
      if (terrain && !model.ownsTerrainTile(plane.id)) continue;
      if (_roomFocus != null) {
        if (plane.roomId != _roomFocus) continue;
        if (plane.roomFace == 'roof') continue;
      }
      if (plane.normal.dot(camera.position - plane.origin) <= 0) continue;
      final world = Camera.intersectPlane(
        ray: ray,
        point: plane.origin,
        normal: plane.normal,
      );
      if (world == null || !plane.region.contains(plane.local(world))) continue;
      if (!model.parcels.owns(Offset(world.x, -world.z))) continue;
      if (terrain &&
          !model
              .surfaceRegions(plane)
              .any((r) => r.contains(plane.local(world)))) {
        continue;
      }
      final d = (world - ray.origin).length;
      if (d < distance) {
        distance = d;
        best = plane;
      }
    }
    if (best == null) return null;
    // Actual scene faces block targeting, including legacy shapes that do not
    // expose a drawable side. Ignore construction ghosts and implied guides.
    final hits =
        SceneHitTester(
          scene: scene,
          camera: camera,
          viewportSize: viewport,
        ).hitTestAll(
          aim,
          includeMesh: (mesh) =>
              mesh.visible &&
              mesh.material.opacity >= .35 &&
              !mesh.id.startsWith('sticker-preview-') &&
              (model.landscape.terrain.tiles.containsKey(mesh.id) ||
                  mesh.id.startsWith('terrain-wall-') ||
                  model.objects.keys.any(
                    (id) => mesh.id == id || mesh.id.startsWith('$id-'),
                  )),
        );
    if (hits.isNotEmpty) {
      final hit = hits.first;
      final world = Camera.intersectPlane(
        ray: ray,
        point: hit.center,
        normal: hit.normal,
      );
      if (world != null && (world - ray.origin).length < distance - .015) {
        return null;
      }
    }
    final surface = model.drawingSurfaceFor(best.id);
    if (surface == null) return null;
    final point = _localOn(surface.frame, aim);
    return point == null
        ? null
        : (planeId: best.id, surface: surface, point: point);
  }

  void _previewConstruction() {
    final tool = model.constructionTool;
    final target =
        _placingConstruction &&
            controls.showReticle &&
            !_parcelShopping &&
            !devToolsOpen
        ? _constructionTarget()
        : null;
    if (target == null ||
        tool == null ||
        !model.toolsFor(target.planeId).contains(tool) ||
        (_pinnedSurface != null && target.planeId != _pinnedSurface)) {
      if (_constructionEvaluation != null) {
        _constructionEvaluation = null;
        _constructionPreviewKey = null;
        _refreshScene();
      }
      return;
    }
    final face = model.drawingFaceAt(target.point, surface: target.surface);
    final key =
        '$tool/${model.constructionPaper}/${target.planeId}/${face?.id}/${model.drawingRevision}/${model.nextId}/${target.point}';
    if (key == _constructionPreviewKey) return;
    _constructionPreviewKey = key;
    _constructionEvaluation = model.evaluateConstruction(
      tool,
      target.planeId,
      target.point,
    );
    _refreshScene();
  }

  void _updateEntityHover() {
    if (_parcelShopping ||
        _drawingFocused ||
        !controls.showReticle ||
        viewport.isEmpty) {
      _aimedEntityName = null;
      return;
    }
    final target = _constructionTarget();
    _aimedEntityName =
        model.objects[model.planes[target?.planeId]?.owner]?.constructionName;
  }

  void _placeConstruction() {
    if (!_placingConstruction || _parcelShopping) return;
    final target = _constructionTarget(fresh: true);
    if (target == null) {
      model.report('Aim at a paper surface');
      return;
    }
    if (!model.toolsFor(target.planeId).contains(model.constructionTool) ||
        (_pinnedSurface != null && target.planeId != _pinnedSurface)) {
      model.report('Select the working surface');
      return;
    }
    final evaluation = model.evaluateConstruction(
      model.constructionTool!,
      target.planeId,
      target.point,
    );
    if (evaluation.valid) {
      if (model.applyConstruction(evaluation)) {
        _entityNameTimer?.cancel();
        _createdEntityId = evaluation.object!.id;
        _entityNameTimer = Timer(const Duration(seconds: 2), () {
          if (mounted) _updateFocusUi(() => _createdEntityId = null);
        });
        _updateFocusUi(() {});
      }
    } else {
      model.report(evaluation.issue!);
    }
  }
}

class _DrawingGraphPainter extends CustomPainter {
  _DrawingGraphPainter(
    this.model,
    this.camera,
    this.scene,
    this.path,
    this.eraseA,
    this.eraseB,
    this.evaluation,
    this.liveScreen,
    this.roomFocus,
  );
  final ProtoplaneController model;
  final String? roomFocus;
  final Camera camera;
  final Scene scene;
  final List<int> path;
  final Offset? eraseA, eraseB, liveScreen;
  final ConstructionEvaluation? evaluation;
  @override
  void paint(Canvas canvas, Size size) {
    final watch = Stopwatch()..start();
    try {
      _paint(canvas, size);
    } finally {
      scene.overlayPaintMs = watch.elapsedMicroseconds / 1000;
    }
  }

  void _paint(Canvas canvas, Size size) {
    final surface = model.drawingSurface;
    final occlusion = <CraftPlane, Path>{};
    void beginInk() => canvas.saveLayer(Offset.zero & size, Paint());
    void endInk(CraftPlane frame) {
      canvas.drawPath(
        occlusion.putIfAbsent(
          frame,
          () => drawingOcclusion(scene, camera, size, frame),
        ),
        Paint()..blendMode = BlendMode.clear,
      );
      canvas.restore();
    }

    Offset? screen(Offset p) => surface == null
        ? null
        : camera.projectToScreen(surface.frame.point(p, .009), size);
    CraftPlane? lineFrame = surface?.frame;
    void line(
      Offset a,
      Offset b,
      Color color,
      double width, {
      bool glow = false,
    }) {
      final x = camera.projectToScreen(lineFrame!.point(a, .009), size),
          y = camera.projectToScreen(lineFrame.point(b, .009), size);
      if (x == null || y == null) return;
      if (glow) {
        canvas.drawLine(
          x,
          y,
          Paint()
            ..color = color.withValues(alpha: .5)
            ..strokeWidth = width + 7
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
      }
      canvas.drawLine(
        x,
        y,
        Paint()
          ..color = color
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round,
      );
    }

    final hits = eraseA != null && eraseB != null
        ? model.eraserIntersections(eraseA!, eraseB!)
        : <String, Set<String>>{};
    for (final graph in model.drawingGraphs.values) {
      if (roomFocus != null) {
        final p = model.planes[graph.surfaceId];
        if (p?.roomId != roomFocus || p?.roomFace == 'roof') continue;
      }
      lineFrame = graph.frame;
      final color = switch (graph.implement) {
        DrawingImplement.pencil => const Color(0xffff9b32),
        DrawingImplement.pen => const Color(0xff83d5ef),
        DrawingImplement.marker => const Color(0xffb3d294),
        DrawingImplement.crookedPencil => const Color(0xffd9b6ec),
        DrawingImplement.eraser => Colors.red,
      };
      beginInk();
      for (final edge in graph.edges) {
        for (final part
            in surface != null && graph.surfaceId == surface.id
                ? surface.clip([edge])
                : [edge]) {
          final selected =
              hits[graph.key]?.contains(drawingEdgeKey(edge)) ?? false;
          line(
            part.a,
            part.b,
            selected ? Colors.orangeAccent : color,
            graph.implement == DrawingImplement.marker ? 8 : 6,
            glow:
                selected ||
                (model.constructionTool == ConstructionTool.pencil &&
                    graph.surfaceId == surface?.id),
          );
        }
      }
      endInk(graph.frame);
    }
    final region = evaluation?.target?.region;
    final targetSurface = evaluation?.target?.surface;
    if (evaluation?.valid == true && region != null && targetSurface != null) {
      final p = Path()..fillType = PathFillType.evenOdd;
      for (final ring in region.rings) {
        var first = true;
        for (final node in ring) {
          final at = camera.projectToScreen(
            targetSurface.frame.point(node, .009),
            size,
          );
          if (at == null) continue;
          if (first) {
            p.moveTo(at.dx, at.dy);
            first = false;
          } else {
            p.lineTo(at.dx, at.dy);
          }
        }
        p.close();
      }
      beginInk();
      canvas.drawPath(p, Paint()..color = Colors.yellow.withValues(alpha: .22));
      endInk(targetSurface.frame);
    }
    if (surface == null || model.constructionTool != ConstructionTool.pencil) {
      return;
    }
    final strokeColor = switch (model.drawingImplement) {
      DrawingImplement.pencil => const Color(0xffff9b32),
      DrawingImplement.pen => const Color(0xff83d5ef),
      DrawingImplement.marker => const Color(0xffb3d294),
      DrawingImplement.crookedPencil => const Color(0xffd9b6ec),
      DrawingImplement.eraser => Colors.redAccent,
    };
    final strokeWidth = model.drawingImplement == DrawingImplement.marker
        ? 8.0
        : 6.0;
    lineFrame = surface.frame;
    beginInk();
    if (model.constructionTool == ConstructionTool.pencil) {
      final grid = model.focusDrawingGrid!;
      final preview = liveScreen == null
          ? <Offset>[]
          : liveStrokePreview(
              grid: grid,
              path: path,
              pointer: liveScreen!,
              project: screen,
              allowBacktracking: true,
            );
      final reversing =
          path.length > 1 &&
          preview.length > 1 &&
          !near(preview.last, grid.nodes[path.last]) &&
          onSegment(
            preview.last,
            grid.nodes[path[path.length - 2]],
            grid.nodes[path.last],
          );
      final selected = path.take(path.length - (reversing ? 1 : 0)).toSet();
      for (final (i, node) in grid.nodes.indexed) {
        final p = screen(node);
        if (p != null) {
          canvas.drawCircle(
            p,
            selected.contains(i) ? 6.5 : 3.5,
            Paint()..color = const Color(0xff181818),
          );
          canvas.drawCircle(
            p,
            selected.contains(i) ? 5 : 1.75,
            Paint()
              ..color = selected.contains(i)
                  ? strokeColor
                  : const Color(0xffd2d2d2),
          );
        }
      }
      for (var i = 1; i < path.length - (reversing ? 1 : 0); i++) {
        line(
          grid.nodes[path[i - 1]],
          grid.nodes[path[i]],
          strokeColor,
          strokeWidth,
          glow: true,
        );
      }
      if (reversing) {
        line(
          grid.nodes[path[path.length - 2]],
          preview.last,
          strokeColor,
          strokeWidth,
          glow: true,
        );
      } else {
        for (var i = 1; i < preview.length; i++) {
          line(
            preview[i - 1],
            preview[i],
            strokeColor,
            strokeWidth,
            glow: true,
          );
        }
      }
    }
    if (eraseA != null && eraseB != null) {
      line(eraseA!, eraseB!, Colors.redAccent, 2.5);
    }
    endInk(surface.frame);
  }

  @override
  bool shouldRepaint(_DrawingGraphPainter old) => true;
}
