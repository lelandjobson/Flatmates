part of 'protoplane_concept_view.dart';

extension _RegionInteractions on _ProtoplaneConceptViewState {
  void _animateRegionPips({bool pulse = false}) {
    regionDotFrom = regionDotSelection;
    regionDotTo = {for (final node in regionPath) node: 1};
    regionPointGlow.forward(from: 0);
    if (pulse) regionSegmentGlow.forward(from: 0);
  }

  Widget _regionDrawingFeedback() {
    if (!regionDragging &&
        model.tool != CraftTool.pencil &&
        !(model.activePlane == null &&
            [CraftTool.scissors, CraftTool.place].contains(model.tool))) {
      return const SizedBox.shrink();
    }
    final surface = regionDragging
        ? workSurface
        : model.activePlane != null
        ? model.regionSurface(model.activePlane!.id)
        : hoverSurface;
    if (surface == null) return const SizedBox.shrink();
    final grid = regionDragging ? workGrid! : model.drawingGrid(surface);
    final path = regionDragging ? regionPath : const <int>[];
    final tool = regionDragging ? regionGestureTool : model.tool;
    return IgnorePointer(
      child: CustomPaint(
        key: const ValueKey('region-drawing-feedback'),
        painter: _GridPainter(
          model,
          camera,
          preview: false,
          acetate: 1,
          hideOutline: true,
          planeOverride: surface.frame,
          gridOverride: grid,
          pathOverride: path,
          traceOverride: grid.trace(path),
          livePointer: regionDragging ? regionLivePointer : null,
          ready: path.length > 2 && path.first == path.last,
          segmentPulse: 1 - regionSegmentGlow.value,
          dotSelection: surface.id == workSurface?.id
              ? regionDotSelection
              : const {},
          lineColor: tool == CraftTool.pencil
              ? lightPencilColor
              : tool == CraftTool.scissors
              ? devSettings.cutLineColor
              : devSettings.lineColor,
          showGridLines: devSettings.gridLines,
        ),
      ),
    );
  }

  void _focusWorldKeyboard() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) worldKeyboard.requestFocus();
    });
  }

  Offset _regionLocal(Offset global) =>
      (_viewportKey.currentContext!.findRenderObject()! as RenderBox)
          .globalToLocal(global);

  RegionSurface? _surfaceAt(Offset point) {
    final hit = _pick(point);
    if (hit == null) return null;
    final id = hit.object == null ? hit.plane : 'surface-${hit.object}';
    return model.regionSurface(model.surfaceFusion.canonical[id] ?? id);
  }

  void _openBook() {
    _updateRegions(() {
      bookOpen = true;
      programHover = null;
    });
  }

  void _selectSticker(ProgramKind program) {
    model.selectProgram(program);
    _updateRegions(() {
      bookOpen = false;
      programHover = null;
    });
    _focusWorldKeyboard();
  }

  KeyEventResult _programKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || bookOpen) return KeyEventResult.ignored;
    final keys = HardwareKeyboard.instance;
    if (event.logicalKey == LogicalKeyboardKey.slash ||
        (event.logicalKey == LogicalKeyboardKey.keyK &&
            (keys.isControlPressed || keys.isMetaPressed))) {
      _openBook();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _cancelRegionGesture();
      model.cancelProgramVolume();
      model.selectTool(CraftTool.orbit);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _regionHover(Offset point, {ProgramKind? program}) {
    if (_disposed || loading || loadFailed || transition.isAnimating) return;
    final surface = _surfaceAt(point);
    final local = surface == null ? null : _localOn(surface.frame, point);
    var target = surface == null || local == null
        ? null
        : model.workspace.at(surface.id, local);
    final active = model.activePlane;
    if (target != null &&
        target.implied &&
        active != null &&
        coplanar(active, surface!.frame)) {
      final focused = mapRegion(active.region, active, surface.frame);
      for (final part in target.geometry.clipTo([focused])) {
        if (part.contains(local!)) {
          target = LightRegion(
            'implied:focus:${active.id}',
            surface.id,
            part,
            implied: true,
          );
          break;
        }
      }
    }
    final kind = program ?? model.selectedProgram;
    if (kind != null &&
        kind != ProgramKind.combine &&
        surface != null &&
        target != null) {
      final old = programHover;
      if (old == null ||
          old.program != kind ||
          old.target.id != target.id ||
          old.revision != model.programRevision ||
          old.regionRevision != model.workspace.revision ||
          (old.drop - local!).distance > .15) {
        programHover = model.evaluateProgram(kind, target, surface, local!);
        _refreshScene();
      }
    } else {
      if (programHover != null) {
        programHover = null;
        _refreshScene();
      }
    }
    if (mounted) {
      _updateRegions(() {
        regionHover = target;
        hoverSurface = surface;
      });
    }
  }

  void _dropSticker(ProgramKind program, Offset global) {
    final point = _regionLocal(global);
    draggingProgram = null;
    if (!(Offset.zero & viewport).contains(point)) return;
    _regionHover(point, program: program);
    if (program == ProgramKind.combine) {
      if (regionHover != null) model.combineRegion(regionHover!);
    } else if (programHover != null && programHover!.program == program) {
      model.applyProgram(programHover!);
    } else {
      model.programIssue = ProgramIssue.support;
    }
    _updateRegions(() {
      bookOpen = false;
      programHover = null;
    });
    _refreshScene();
    _focusWorldKeyboard();
  }

  int? _regionNode(RegionSurface surface, CraftGrid grid, Offset screen) {
    var distance = 24.0;
    int? result;
    for (final (i, n) in grid.nodes.indexed) {
      final p = camera.projectToScreen(surface.frame.point(n, .009), viewport);
      if (p != null && (p - screen).distance < distance) {
        result = i;
        distance = (p - screen).distance;
      }
    }
    return result;
  }

  bool _regionDown(PointerDownEvent event) {
    if (secondary || pointers.length != 1 || devToolsOpen) return false;
    // Preserve focus rewind, scrub, and release gestures. Strokes entering an
    // adjacent tile are promoted to the shared workspace below.
    if (model.activePlane != null &&
        (model.tool == CraftTool.scissors || model.tool == CraftTool.place)) {
      return false;
    }
    if (model.tool == CraftTool.eraser && model.activePlane == null) {
      final surface = _surfaceAt(event.localPosition);
      final point = surface == null
          ? null
          : _localOn(surface.frame, event.localPosition);
      if (surface != null && point != null) {
        workSurface = surface;
        regionErasing = true;
        regionEraseLast = point;
        model.beginGesture();
        model.scrubRegion(surface, point, point);
      }
      return true;
    }
    if (model.tool == CraftTool.program || model.tool == CraftTool.combine) {
      _regionHover(event.localPosition);
      regionClick = true;
      return true;
    }
    if (![
      CraftTool.pencil,
      CraftTool.scissors,
      CraftTool.place,
    ].contains(model.tool)) {
      return false;
    }
    final surface = _surfaceAt(event.localPosition);
    if (surface == null) {
      regionClick = true;
      return true;
    }
    final grid = model.drawingGrid(surface),
        node = _regionNode(
          surface,
          model.drawingGrid(surface),
          event.localPosition,
        );
    if (node == null) {
      regionClick = true;
      return true;
    }
    regionPointer = event.pointer;
    workSurface = surface;
    hoverSurface = surface;
    workGrid = grid;
    regionPath = [node];
    regionDotFrom = {};
    regionDotTo = {};
    regionLivePointer = event.localPosition;
    regionDragging = true;
    regionGestureTool = model.tool;
    strokeShake.reset();
    strokeShake.update(event.localPosition, event.timeStamp);
    _animateRegionPips();
    _updateRegions(() {});
    return true;
  }

  bool _regionMove(PointerMoveEvent event) {
    if (regionErasing || regionClick || regionDragging) {
      controls.move(event.kind, event.localPosition);
    }
    if (regionErasing) {
      final point = _localOn(workSurface!.frame, event.localPosition);
      if (point != null) {
        model.scrubRegion(workSurface!, regionEraseLast ?? point, point);
        regionEraseLast = point;
      }
      return true;
    }
    if (regionClick) {
      _regionHover(event.localPosition);
      return true;
    }
    if (!regionDragging || event.pointer != regionPointer) return false;
    regionLivePointer = event.localPosition;
    _updateRegions(() {});
    if (regionGestureTool == CraftTool.place &&
        strokeShake.update(event.localPosition, event.timeStamp)) {
      _cancelRegionGesture();
      regionClick = true;
      return true;
    }
    final surface = workSurface!, grid = workGrid!;
    final node = _regionNode(surface, grid, event.localPosition);
    if (regionPath.length > 2 && regionPath.first == regionPath.last) {
      final start = camera.projectToScreen(
        surface.frame.point(grid.nodes[regionPath.first], .009),
        viewport,
      );
      if (start == null || (start - event.localPosition).distance <= 24) {
        return true;
      }
      regionPath.removeLast();
      _animateRegionPips();
    }
    if (node == null || node == regionPath.last) return true;
    if (regionPath.length > 1 && node == regionPath[regionPath.length - 2]) {
      regionPath.removeLast();
      _animateRegionPips();
      _updateRegions(() {});
      return true;
    }
    final route = grid.connection(regionPath.last, node) != null
        ? [node]
        : grid.collinearRoute(regionPath.last, node);
    if (route == null) return true;
    regionPath.addAll(route);
    _animateRegionPips(pulse: true);
    final trace = grid.trace(regionPath);
    if (regionGestureTool != CraftTool.pencil &&
        trace.length >= 4 &&
        near(trace.first, trace.last)) {
      final region = Region(trace.sublist(0, trace.length - 1));
      if (region.valid) {
        programHover = model.evaluateProgram(
          regionGestureTool == CraftTool.scissors
              ? ProgramKind.cut
              : ProgramKind.place,
          LightRegion('drawing', surface.id, region, implied: true),
          surface,
          region.bounds.center,
        );
        _refreshScene();
      }
    }
    _updateRegions(() {});
    return true;
  }

  bool _extendFocusedStroke(PointerMoveEvent event) {
    if (!drawing ||
        model.closed ||
        model.activePlane == null ||
        pointers.length != 1) {
      return false;
    }
    final active = model.activePlane!,
        point = _localOn(model.activePlane, event.localPosition);
    if (point == null ||
        active.region.contains(point) ||
        active.region.rings.any(
          (ring) => edges(
            ring,
          ).any((edge) => _distanceToSegment(point, edge.$1, edge.$2) < .04),
        )) {
      return false;
    }
    final surface = model.regionSurface(active.id);
    if (surface == null ||
        !surface.region.contains(surface.frame.local(active.point(point)))) {
      return false;
    }
    final grid = model.drawingGrid(surface);
    final path = model.trace
        .map((p) => surface.frame.local(active.point(p)))
        .toList();
    final indices = path
        .map((p) => grid.nodes.indexWhere((q) => near(p, q)))
        .toList();
    if (indices.isEmpty || indices.contains(-1)) return false;
    regionGestureTool = model.tool;
    model.cancelGesture();
    drawing = false;
    regionDragging = true;
    regionPointer = event.pointer;
    workSurface = surface;
    workGrid = grid;
    regionPath = indices;
    regionDotFrom = {};
    regionDotTo = {};
    _animateRegionPips();
    return _regionMove(event);
  }

  bool _regionUp(PointerUpEvent event) {
    if (regionErasing) {
      regionErasing = false;
      regionEraseLast = null;
      model.finishGesture();
      return true;
    }
    if (regionClick) {
      regionClick = false;
      _regionHover(event.localPosition);
      if (model.tool == CraftTool.combine && regionHover != null) {
        model.combineRegion(regionHover!);
      }
      if (model.tool == CraftTool.program && programHover != null) {
        model.applyProgram(programHover!);
      }
      programHover = null;
      _refreshScene();
      return true;
    }
    if (!regionDragging || event.pointer != regionPointer) return false;
    final surface = workSurface!,
        path = workGrid!.trace(regionPath),
        tool = regionGestureTool;
    regionDragging = false;
    regionPointer = null;
    regionPath = [];
    regionLivePointer = null;
    _animateRegionPips();
    if (path.length > 1) {
      if (tool == CraftTool.pencil) {
        model.drawLightPath(surface, path);
      } else if (path.length >= 4 && near(path.first, path.last)) {
        final geometry = Region(path.sublist(0, path.length - 1));
        if (geometry.valid) {
          final target = LightRegion(
            'drawing',
            surface.id,
            geometry,
            implied: true,
          );
          final plan = model.evaluateProgram(
            tool == CraftTool.scissors ? ProgramKind.cut : ProgramKind.place,
            target,
            surface,
            geometry.bounds.center,
          );
          model.applyProgram(plan);
        }
      } else {
        model.commitRegionPath(surface, path, place: tool == CraftTool.place);
      }
    }
    programHover = null;
    if (tool != CraftTool.pencil && path.length > 1) {
      fadingRegionLines = {
        surface: [
          for (var i = 1; i < path.length; i++)
            PencilSegment(path[i - 1], path[i]),
        ],
      };
      regionFadeColor = tool == CraftTool.scissors
          ? devSettings.cutLineColor
          : devSettings.lineColor;
      regionFade.forward(from: 0);
    }
    _refreshScene();
    _updateRegions(() {});
    return true;
  }

  void _cancelRegionGesture() {
    if (regionErasing) {
      regionErasing = false;
      regionEraseLast = null;
      model.cancelGesture();
    }
    regionDragging = false;
    regionClick = false;
    regionPointer = null;
    regionPath = [];
    regionLivePointer = null;
    if (regionDotTo.isNotEmpty) _animateRegionPips();
    if (mounted) _updateRegions(() {});
  }

  void _syncRegionFade() {
    final current = model.workspace;
    if (lastRegionRevision == current.revision) return;
    final removed = <RegionSurface, List<PencilSegment>>{};
    for (final e in previousRegionLines.entries) {
      final rest = newPencilCoverage(e.value, current.lines[e.key.id] ?? []);
      if (rest.isNotEmpty) removed[e.key] = rest;
    }
    previousRegionLines = {
      for (final e in current.lines.entries)
        if (current.surfaces[e.key] != null)
          current.surfaces[e.key]!: List.of(e.value),
    };
    lastRegionRevision = current.revision;
    if (removed.isNotEmpty) {
      regionFadeColor = lightPencilColor;
      fadingRegionLines = removed;
      regionFade.duration = Duration(
        milliseconds: MediaQuery.disableAnimationsOf(context) ? 100 : 300,
      );
      regionFade.forward(from: 0);
    }
  }

  void _addProgramMeshes(List<Mesh> meshes) {
    for (final a in model.assemblies.values.where((a) => a.water != null)) {
      // A breached basin no longer has a water surface.
      final water = model.poolWater(a);
      if (water == null) continue;
      final id = 'water-${a.id}';
      meshes.add(
        Mesh(
          id: id,
          name: 'Water',
          geometry: regionGeometry(
            id,
            a.frame,
            water,
            0,
            base: a.parameters['waterLevel'] ?? -.05,
          ),
          material: MaterialModel(
            color: const Color(0xff72c9d9),
            doubleSided: true,
            opacity: .68,
            strokeEdges: false,
          ),
        ),
      );
    }
    final plan = model.pendingVolume ?? programHover;
    if (plan == null || !plan.valid) return;
    for (final o in plan.objects) {
      final frame = plan.frames[o.id]!;
      meshes.addAll(
        objectMeshes(
          o.copyWith(id: 'program-preview-${o.id}'),
          frame,
          opacity: .5,
        ),
      );
    }
    if (plan.water != null) {
      meshes.add(
        Mesh(
          id: 'program-preview-water',
          name: 'Water',
          geometry: regionGeometry(
            'program-preview-water',
            plan.surface.frame,
            plan.water!,
            0,
            base: plan.waterDepth,
          ),
          material: MaterialModel(
            color: const Color(0xff72c9d9),
            doubleSided: true,
            opacity: .5,
            strokeEdges: false,
          ),
        ),
      );
    }
  }

  Widget _programStatus() {
    final plan = model.pendingVolume ?? programHover;
    final issue = model.programIssue ?? plan?.issue;
    if (plan == null && issue == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xe6222222),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (issue != null)
                Semantics(
                  label: issue.label,
                  child: Icon(issueIcon(issue), color: const Color(0xffff5353)),
                ),
              if (plan != null)
                Text(
                  '${plan.program.label} · ${plan.quote}',
                  style: const TextStyle(color: Colors.white),
                ),
              if (model.pendingVolume != null) ...[
                Text(model.pendingVolume!.depth.toStringAsFixed(2)),
                IconButton(
                  tooltip: 'Cancel',
                  onPressed: model.cancelProgramVolume,
                  icon: const Icon(Icons.close),
                ),
                FilledButton(
                  onPressed: model.pendingVolume!.valid
                      ? () => model.applyProgram(
                          model.pendingVolume!,
                          confirmVolume: true,
                        )
                      : null,
                  child: const Text('Apply'),
                ),
              ],
            ],
          ),
          if (model.pendingVolume != null)
            Slider(
              value: model.pendingVolume!.depth,
              min: .01,
              max: 1,
              onChanged: model.setProgramDepth,
            ),
        ],
      ),
    );
  }
}
