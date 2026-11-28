part of 'controller.dart';

extension SurfaceConstruction on ProtoplaneController {
  Set<ConstructionTool> toolsFor(String? id) {
    final p = planes[id];
    return p == null
        ? const {}
        : surfaceTools(
            p,
            objects[p.owner],
            landscape: landscape.terrain.tiles.containsKey(id),
          );
  }

  String get startingTile => landscape.terrain.tiles.values
      .firstWhere(
        (t) =>
            t.x == 0 &&
            t.y == 0 &&
            t.sheet.island == 'starter' &&
            t.sheet.material == PaperMaterial.paperWhite,
      )
      .id;
  List<ArchitecturalWall> get walls =>
      _architecturalWalls ??= architecturalWalls(objects, objectPlane);

  /// Merge the actual source grids into the drawing frame. Do not synthesize
  /// missing connections, and never expose a grid node outside intact support.
  CraftGrid surfaceGrid(String id) {
    final surface = drawingSurfaceFor(id)!;
    final gridKey =
        '$id/$openingComplete/${Object.hashAll(surface.sources.map((id) => planes[id]))}';
    final cached = _surfaceGrids[gridKey];
    if (cached != null) return cached;
    if (!landscape.terrain.tiles.containsKey(id)) {
      return _surfaceGrids[gridKey] = surface.grid(
        DrawingImplement.pencil,
        spacing: drawingSpacingFor(id),
      );
    }
    final nodes = <Offset>[], edges = <GridEdge>[], keys = <String, int>{};
    final sources = !openingComplete ? [startingTile] : surface.sources;
    for (final sourceId in sources) {
      final p = planes[sourceId];
      if (p == null || !ownsTerrainTile(sourceId)) continue;
      final grid = p.grids.first, mapping = <int, int>{};
      for (final (i, point) in grid.nodes.indexed) {
        final at = surface.frame.local(p.point(point));
        if (!surface.regions.any((r) => r.contains(at))) continue;
        mapping[i] = keys.putIfAbsent(drawingPointKey(at), () {
          nodes.add(at);
          return nodes.length - 1;
        });
      }
      for (final edge in grid.edges) {
        final a = mapping[edge.a], b = mapping[edge.b];
        if (a == null || b == null || a == b || edge.control != null) continue;
        final d = grid.nodes[edge.b] - grid.nodes[edge.a];
        if (d.dx.abs() > geometryEpsilon && d.dy.abs() > geometryEpsilon) {
          continue;
        }
        final segment = PencilSegment(nodes[a], nodes[b]);
        if (surface
                .clip([segment])
                .fold<double>(0, (sum, e) => sum + e.length) <
            segment.length - geometryEpsilon) {
          continue;
        }
        if (!edges.any(
          (e) => (e.a == a && e.b == b) || (e.a == b && e.b == a),
        )) {
          edges.add(GridEdge(a, b));
        }
      }
    }
    return _surfaceGrids[gridKey] = CraftGrid(
      id: 'surface-grid-$id',
      name: 'Paper',
      nodes: nodes,
      edges: edges,
      recipes: const [],
      connectionStyle: GridConnections.orthogonal,
    );
  }

  bool _validSurfaceStroke(
    String id,
    List<Offset> path, {
    bool closed = false,
  }) {
    if (path.length < 2 ||
        (closed && (path.length < 5 || !near(path.first, path.last)))) {
      return false;
    }
    final grid = surfaceGrid(id);
    final indices = path
        .map((p) => grid.nodes.indexWhere((n) => near(n, p)))
        .toList();
    if (indices.any((n) => n < 0)) return false;
    for (var i = 1; i < indices.length; i++) {
      if (grid.collinearRoute(indices[i - 1], indices[i]) == null) return false;
    }
    return true;
  }

  ConstructionEvaluation evaluateVolumeStroke(String id, List<Offset> path) {
    ConstructionEvaluation fail(String issue) => ConstructionEvaluation(
      ConstructionTool.volume,
      null,
      issue: issue,
      stroke: List.of(path),
    );
    if (!toolsFor(id).contains(ConstructionTool.volume) ||
        !_validSurfaceStroke(id, path, closed: true)) {
      return fail('Close the loop along connected pips');
    }
    final region = Region(simplifyRing(path.sublist(0, path.length - 1)));
    if (!region.valid || region.area < 1 - geometryEpsilon) {
      return fail('Draw a closed region of at least one tile');
    }
    final surface = drawingSurfaceFor(id)!;
    if (!drawingSupported(surface, region)) {
      return fail('The room needs owned, intact ground');
    }
    final cost = (region.area * 16 - geometryEpsilon).ceil();
    if ((balances[PaperMaterial.paperWhite] ?? 0) < cost) {
      return fail('Buy more building paper');
    }
    final frame = CraftPlane(
      id: 'sticker-frame-room-$nextId',
      origin: surface.frame.origin,
      u: surface.frame.u,
      v: surface.frame.v,
      region: region,
      grids: [lattice('room-$nextId', region, count: 2)],
    );
    final count = objects.values.where((o) => o.kind == CraftKind.room).length;
    final object = CraftObject(
      id: 'object-$nextId',
      planeId: frame.id,
      kind: CraftKind.room,
      region: region,
      depth: 1,
      drawingSpacing: .25,
      roomName: 'Room ${count + 1}',
      roomColor: Color.fromARGB(
        255,
        160 + (count * 37) % 65,
        163 + (count * 53) % 65,
        164 + (count * 29) % 65,
      ).toARGB32(),
    );
    for (final old in objects.values) {
      if (solidsOverlap(
        object.copyWith(kind: CraftKind.solidVolume),
        frame,
        old,
        objectPlane(old),
      )) {
        return fail('Another object occupies this space');
      }
    }
    final staged = ProtoplaneController._constructionStage(this);
    try {
      staged.planes[frame.id] = frame;
      staged.objects[object.id] = object;
      staged.nextId++;
      staged.openingComplete = true;
      staged._derivePlanes();
      staged._validateLoaded();
    } on FormatException catch (error) {
      return fail(error.message.toString());
    } finally {
      staged.dispose();
    }
    return ConstructionEvaluation(
      ConstructionTool.volume,
      ConstructionTarget(id, surface, path.first, region, 1),
      object: object,
      frame: frame,
      stroke: List.unmodifiable(path),
    );
  }

  bool applyVolumeStroke(String id, List<Offset> path) {
    final e = evaluateVolumeStroke(id, path);
    if (!e.valid) {
      report(e.issue!);
      return false;
    }
    final before = _snapshot();
    planes[e.frame!.id] = e.frame!;
    objects[e.object!.id] = e.object!;
    balances[PaperMaterial.paperWhite] =
        balances[PaperMaterial.paperWhite]! -
        (e.target!.region.area * 16 - geometryEpsilon).ceil();
    nextId++;
    openingComplete = true;
    _derivePlanes();
    _record(before, committed: true);
    _notifyPencil();
    return true;
  }

  Map<String, CraftObject>? _wallChange(
    CraftObject room,
    RoomOpening opening, {
    bool replace = false,
  }) {
    final panel = roomPanels(
      room,
      objectPlane(room),
    ).firstWhere((p) => p.key == opening.wall);
    final b = opening.region.bounds;
    if (!panel.frame.region.containsRegion(opening.region)) return null;
    final touched = walls
        .where(
          (w) => w.sides.any(
            (s) =>
                s.room == room.id &&
                s.panel.key == panel.key &&
                b.left < s.end - geometryEpsilon &&
                b.right > s.start + geometryEpsilon,
          ),
        )
        .toList();
    if (touched.length != 1 || touched.single.sides.length > 2) return null;
    final changes = <String, CraftObject>{};
    for (final side in touched.single.sides) {
      final old = objects[side.room]!;
      final mapped = _inFrame(opening.region, panel.frame, side.panel.frame);
      final hinge = opening.hinge == null
          ? null
          : side.panel.frame
                .local(panel.frame.point(Offset(opening.hinge!, 0)))
                .dx;
      final cut = RoomOpening(
        side.panel.key,
        mapped,
        opening.kind,
        id: opening.id,
        hinge: hinge,
        swingSide: side.panel.frame.normal.dot(panel.frame.normal) > 0
            ? opening.swingSide
            : -opening.swingSide,
      );
      if (old.openings.any(
        (o) =>
            o.wall == cut.wall &&
            (!replace || o.id != cut.id) &&
            o.region.overlaps(cut.region),
      )) {
        return null;
      }
      if (side.panel.frame.region.area - cut.region.area < geometryEpsilon) {
        return null;
      }
      for (final child in objects.values) {
        final support = objectPlane(child);
        if (support.roomId == old.id &&
            support.roomFace == cut.wall &&
            _inFrame(
              child.region,
              support,
              side.panel.frame,
            ).overlaps(cut.region)) {
          return null;
        }
      }
      changes[old.id] = old.copyWith(
        openings: [
          ...old.openings.where((o) => !replace || o.id != cut.id),
          cut,
        ],
      );
    }
    return changes;
  }

  ConstructionEvaluation evaluateCutStroke(String id, List<Offset> path) {
    ConstructionEvaluation fail(String message) => ConstructionEvaluation(
      ConstructionTool.scissors,
      null,
      issue: message,
      stroke: List.of(path),
    );
    if (!toolsFor(id).contains(ConstructionTool.scissors) ||
        !_validSurfaceStroke(id, path) ||
        path.length < 4) {
      return fail('Trace a cut along connected wall pips');
    }
    final p = planes[id]!, room = objects[p.owner]!;
    final panel = roomPanels(
      room,
      objectPlane(room),
    ).firstWhere((w) => w.key == p.roomFace);
    final surface = drawingSurfaceFor(id)!;
    final closed = near(path.first, path.last);
    final points = (closed ? path.sublist(0, path.length - 1) : path)
        .map((n) => panel.frame.local(surface.frame.point(n)))
        .toList();
    final region = Region(simplifyRing(points));
    if (!region.valid) return fail('The cut must bound a simple region');
    double? hinge;
    if (!closed) {
      if (region.outer.length != 4 ||
          (points.first.dx - points.last.dx).abs() > geometryEpsilon ||
          doorwayCenter(region) == null ||
          (region.area - region.bounds.width * region.bounds.height).abs() >
              geometryEpsilon) {
        return fail('Leave one vertical hinge on a floor-touching rectangle');
      }
      hinge = points.first.dx;
    }
    final b = region.bounds, extent = panel.frame.region.bounds;
    final kind = hinge != null
        ? 'flap'
        : doorwayCenter(region) != null
        ? 'door'
        : b.left > geometryEpsilon &&
              b.right < extent.right - geometryEpsilon &&
              b.top > geometryEpsilon &&
              b.bottom < extent.bottom - geometryEpsilon
        ? 'window'
        : 'opening';
    final opening = RoomOpening(
      panel.key,
      region,
      kind,
      id: 'cut-$nextId',
      hinge: hinge,
    );
    final changes = _wallChange(room, opening);
    if (changes == null) {
      return fail('Keep the cut within one intact, unsupported wall span');
    }
    return ConstructionEvaluation(
      ConstructionTool.scissors,
      ConstructionTarget(
        id,
        surface,
        path.first,
        _inFrame(region, panel.frame, surface.frame),
        .25,
      ),
      object: changes[room.id],
      frame: objectPlane(room),
      replacementId: room.id,
      stroke: List.of(path),
    );
  }

  bool cutSurfaceStroke(String id, List<Offset> path) {
    final evaluation = evaluateCutStroke(id, path);
    if (!evaluation.valid) {
      report(evaluation.issue!);
      return false;
    }
    final room = objects[evaluation.replacementId]!;
    final opening = evaluation.object!.openings.last;
    final changes = _wallChange(room, opening)!;
    final hinge = opening.hinge;
    final surface = evaluation.target!.surface;
    final before = _snapshot();
    objects.addAll(changes);
    nextId++;
    if (hinge != null) {
      final key = '${surface.id}/pencil';
      final graph = DrawingGraph(
        surface.id,
        DrawingImplement.pencil,
        surface.frame,
        drawingGraphs[key]?.edges ?? [],
      );
      graph.replace([
        ...graph.edges,
        for (var i = 1; i < path.length; i++)
          PencilSegment(path[i - 1], path[i]),
      ]);
      drawingGraphs[key] = graph;
      drawingRevision++;
    }
    _derivePlanes();
    _record(before, committed: true);
    _notifyPencil();
    return true;
  }

  ConstructionEvaluation _evaluateDoorFold(String id, Offset point) {
    final target = constructionTarget(id, point), p = planes[id]!;
    ConstructionEvaluation fail(String issue) =>
        ConstructionEvaluation(ConstructionTool.fold, target, issue: issue);
    final room = objects[p.owner];
    if (room?.kind != CraftKind.room) {
      return fail('Select an attached wall flap');
    }
    final panel = roomPanels(
      room!,
      objectPlane(room),
    ).where((w) => w.key == p.roomFace).firstOrNull;
    if (panel == null) return fail('Select an attached wall flap');
    final local = panel.frame.local(target!.surface.frame.point(point));
    final flap = room.openings
        .where(
          (o) =>
              o.wall == p.roomFace &&
              o.kind == 'flap' &&
              o.region.contains(local),
        )
        .firstOrNull;
    if (flap == null) return fail('Cut three sides of a door first');
    final folded = flap.folded(p.normal.dot(panel.frame.normal) < 0 ? -1 : 1),
        changes = _wallChange(room, folded, replace: true);
    if (changes == null) return fail('The flap no longer has intact support');
    final obstacles = <CollisionSolid>[];
    for (final old in objects.values) {
      var obstacle = changes[old.id] ?? old;
      if (changes.containsKey(old.id)) {
        obstacle = obstacle.copyWith(
          openings: obstacle.openings
              .map(
                (o) => o.id == flap.id
                    ? RoomOpening(o.wall, o.region, 'opening', id: o.id)
                    : o,
              )
              .toList(),
        );
      }
      obstacles.add(CollisionSolid(obstacle, objectPlane(old)));
    }
    // Check the swept leaf against other objects and the remaining room shell.
    for (var i = 1; i <= 18; i++) {
      final frame = doorLeafFrame(panel.frame, folded, i / 18);
      final leaf = CraftObject(
        id: 'swing',
        planeId: frame.id,
        kind: CraftKind.paperSheet,
        region: doorLeafRegion(flap),
        depth: roomThickness,
      );
      final body = CollisionSolid(leaf, frame);
      if (obstacles.any(body.overlaps)) return fail('Clear the door swing');
    }
    return ConstructionEvaluation(
      ConstructionTool.fold,
      ConstructionTarget(
        id,
        target.surface,
        point,
        _inFrame(flap.region, panel.frame, target.surface.frame),
        .25,
        context: target.context,
        roomId: target.roomId,
      ),
      object: changes[room.id],
      frame: objectPlane(room),
      replacementId: room.id,
    );
  }

  void _deriveSharedSurfaces() {
    final architecture = walls;
    for (final p in planes.values.toList()) {
      if (p.roomFace?.startsWith('wall-') != true || p.interior) continue;
      final spans = architecture
          .where(
            (w) => w.sides.any(
              (s) => s.room == p.owner && s.panel.key == p.roomFace,
            ),
          )
          .toList();
      if (!spans.any((w) => w.shared)) continue;
      final pieces = <({ArchitecturalWall wall, Region region})>[];
      for (final wall in spans) {
        final side = wall.sides.firstWhere((s) => s.room == p.owner);
        final local = _inFrame(
          rectangle(
            side.end - side.start,
            side.panel.frame.region.bounds.height,
            origin: Offset(side.start, 0),
          ),
          side.panel.frame,
          p,
        );
        for (final region in p.region.clipTo([local])) {
          pieces.add((wall: wall, region: region));
        }
      }
      for (final (index, piece) in pieces.indexed) {
        final other = piece.wall.sides
            .where((s) => s.room != p.owner)
            .firstOrNull;
        final id = index == 0 ? p.id : '${p.id}-span-${piece.wall.id}-$index';
        planes[id] = CraftPlane(
          id: id,
          origin: p.origin,
          u: p.u,
          v: p.v,
          region: piece.region,
          grids: p.grids,
          owner: p.owner,
          roomId: other?.room ?? p.roomId,
          roomFace: p.roomFace,
          interior: piece.wall.shared,
        );
      }
    }
  }
}
