part of 'protoplane_concept_view.dart';

extension _FocusTools on _ProtoplaneConceptViewState {
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
    _focusTouches[e.pointer] = e.localPosition;
    _focusLiveScreen = e.localPosition;
    _updateFocusUi(() {});
    controls.move(e.kind, e.localPosition);
    if (_focusTouches.length > 1) {
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
    if (loading || loadFailed || devToolsOpen) return;
    final next = model.constructionTool == requested ? null : requested;
    final target = next == ConstructionTool.pencil && !_parcelShopping
        ? _constructionTarget()
        : null;
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
    }
    _previewConstruction();
    _refreshScene();
    _updateFocusUi(() {});
  }

  ({String planeId, DrawingSurface surface, Offset point})?
  _constructionTarget() {
    if (viewport.isEmpty) return null;
    final aim = viewport.center(Offset.zero);
    final ray = camera.unprojectRay(aim, viewport);
    if (ray == null) return null;
    CraftPlane? best;
    var distance = double.infinity;
    for (final plane in model.planes.values) {
      final terrain = model.landscape.terrain.tiles.containsKey(plane.id);
      if (!terrain && !plane.id.startsWith('surface-')) continue;
      if (terrain && !model.ownsTerrainTile(plane.id)) continue;
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
    final target = _placingConstruction && !_parcelShopping && !devToolsOpen
        ? _constructionTarget()
        : null;
    if (target == null || tool == null) {
      if (_constructionEvaluation != null) {
        _constructionEvaluation = null;
        _constructionPreviewKey = null;
        _refreshScene();
      }
      return;
    }
    final face = model.drawingFaceAt(target.point, surface: target.surface);
    final key =
        '$tool/${model.constructionPaper}/${target.planeId}/${face?.id}/${model.drawingRevision}/${model.nextId}';
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
    if (_parcelShopping || _drawingFocused || viewport.isEmpty) {
      _aimedEntityName = null;
      return;
    }
    final target = _constructionTarget();
    _aimedEntityName =
        model.objects[model.planes[target?.planeId]?.owner]?.constructionName;
  }

  void _placeConstruction() {
    if (!_placingConstruction || _parcelShopping) return;
    final target = _constructionTarget();
    if (target == null) {
      model.report('Aim at a paper surface');
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
  );
  final ProtoplaneController model;
  final Camera camera;
  final Scene scene;
  final List<int> path;
  final Offset? eraseA, eraseB, liveScreen;
  final ConstructionEvaluation? evaluation;
  @override
  void paint(Canvas canvas, Size size) {
    final surface = model.drawingSurface;
    final visibility = <CraftPlane, Path>{};
    void clip(CraftPlane frame) => canvas.clipPath(
      visibility.putIfAbsent(
        frame,
        () => drawingVisibility(scene, camera, size, frame),
      ),
    );
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
      canvas.save();
      clip(lineFrame);
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
      canvas.restore();
    }

    final hits = eraseA != null && eraseB != null
        ? model.eraserIntersections(eraseA!, eraseB!)
        : <String, Set<String>>{};
    for (final graph in model.drawingGraphs.values) {
      lineFrame = graph.frame;
      final color = switch (graph.implement) {
        DrawingImplement.pencil => const Color(0xffff9b32),
        DrawingImplement.pen => const Color(0xff83d5ef),
        DrawingImplement.marker => const Color(0xffb3d294),
        DrawingImplement.crookedPencil => const Color(0xffd9b6ec),
        DrawingImplement.eraser => Colors.red,
      };
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
            glow: true,
          );
        }
      }
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
      canvas.save();
      clip(targetSurface.frame);
      canvas.drawPath(p, Paint()..color = Colors.yellow.withValues(alpha: .22));
      canvas.restore();
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
      canvas.save();
      clip(surface.frame);
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
      canvas.restore();
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
  }

  @override
  bool shouldRepaint(_DrawingGraphPainter old) => true;
}
