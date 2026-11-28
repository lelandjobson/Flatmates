part of 'controller.dart';

extension FocusDrawing on ProtoplaneController {
  DrawingSurface? get drawingSurface => drawingSurfaceFor(activePlaneId);

  DrawingSurface? drawingSurfaceFor(String? planeId) {
    final p = planes[planeId];
    if (p == null) return null;
    final terrainIds = p.id.startsWith('landscape-drawing-')
        ? p.supports.where(landscape.terrain.tiles.containsKey).toList()
        : landscape.terrain.tiles.containsKey(p.id)
        ? [
            for (final tile in landscape.terrain.tiles.values)
              if (ownsTerrainTile(tile.id) &&
                  tile.sheet.island ==
                      landscape.terrain.tiles[p.id]!.sheet.island &&
                  (tile.sheet.elevation -
                              landscape.terrain.tiles[p.id]!.sheet.elevation)
                          .abs() <
                      geometryEpsilon)
                tile.id,
          ]
        : <String>[];
    final signature =
        '${p.id}/${identityHashCode(p)}/${terrainIds.map((id) => landscape.revision(id)).join(',')}';
    if (_drawingSurfaceKey == signature) return _drawingSurfaceCache;
    _drawingSurfaceKey = signature;
    _drawingGrids.clear();
    if (terrainIds.isNotEmpty) {
      final tile = landscape.terrain.tiles[terrainIds.first]!;
      final id = 'terrain-${tile.sheet.island}-${tile.sheet.elevation}';
      final basis = CraftPlane(
        id: id,
        origin: Vector3(0, p.origin.y, 0),
        u: Vector3(1, 0, 0),
        v: Vector3(0, 0, -1),
        region: p.region,
        grids: const [],
      );
      final region = _inFrame(p.region, p, basis);
      return _drawingSurfaceCache = DrawingSurface(
        id,
        CraftPlane(
          id: id,
          origin: basis.origin,
          u: basis.u,
          v: basis.v,
          region: region,
          grids: const [],
        ),
        terrainIds,
        regions: [
          for (final id in terrainIds)
            for (final r in surfaceRegions(planes[id]!))
              _inFrame(r, planes[id]!, basis),
        ],
      );
    }
    final canonical = surfaceFusion.canonical[p.id] ?? p.id;
    final basis = planes[canonical] ?? p;
    final region = _inFrame(p.region, p, basis);
    final sources = [
      for (final id in surfaceFusion.members[p.id] ?? <String>[]) 'surface-$id',
      if (!surfaceFusion.members.containsKey(p.id)) p.id,
    ];
    return _drawingSurfaceCache = DrawingSurface(
      canonical,
      CraftPlane(
        id: canonical,
        origin: basis.origin,
        u: basis.u,
        v: basis.v,
        region: region,
        grids: const [],
        owner: basis.owner,
      ),
      sources,
      regions: [
        for (final id in sources)
          if (planes[id] != null)
            _inFrame(planes[id]!.region, planes[id]!, basis),
      ],
    );
  }

  CraftGrid? get focusDrawingGrid {
    final surface = drawingSurface;
    if (surface == null) return null;
    return _drawingGrids.putIfAbsent(
      drawingImplement,
      () => surface.grid(
        drawingImplement,
        spacing: constructionTool == ConstructionTool.pencil
            ? drawingSpacingFor(activePlaneId!)
            : null,
      ),
    );
  }

  Iterable<DrawingGraph> get surfaceGraphs {
    final id = drawingSurface?.id;
    return drawingGraphs.values.where((g) => g.surfaceId == id);
  }

  void selectDrawingImplement(DrawingImplement value) {
    drawingImplement = value;
    if (value != DrawingImplement.eraser) lastDrawingImplement = value;
    error = null;
    _notifyPencil(previewOnly: true);
  }

  void selectFocusCard(FocusToolCard value) {
    focusCard = value;
    error = null;
    _notifyPencil(previewOnly: true);
  }

  bool commitDrawingPath(List<Offset> path) {
    final surface = drawingSurface;
    if (surface == null ||
        drawingImplement == DrawingImplement.eraser ||
        path.length < 2) {
      return false;
    }
    for (final point in path) {
      final p =
          drawingImplement.toLattice(point) /
          (constructionTool == ConstructionTool.pencil
              ? drawingSpacingFor(activePlaneId!)
              : drawingImplement.spacing);
      if ((p.dx - p.dx.round()).abs() > 1e-5 ||
          (p.dy - p.dy.round()).abs() > 1e-5) {
        return false;
      }
    }
    final segments = <PencilSegment>[];
    for (var i = 1; i < path.length; i++) {
      final delta = drawingImplement.toLattice(path[i] - path[i - 1]);
      if (delta.dx.abs() > 1e-6 && delta.dy.abs() > 1e-6) return false;
      final edge = PencilSegment(path[i - 1], path[i]);
      final supported = surface.clip([edge]);
      if (supported.fold<double>(0, (sum, part) => sum + part.length) <
          edge.length - geometryEpsilon) {
        return false;
      }
      segments.add(edge);
    }
    final key = '${surface.id}/${drawingImplement.name}';
    final old = drawingGraphs[key];
    if (newPencilCoverage(segments, old?.edges ?? []).isEmpty) return false;
    final before = _snapshot();
    final graph =
        old ?? DrawingGraph(surface.id, drawingImplement, surface.frame);
    graph.replace([...graph.edges, ...segments]);
    drawingGraphs[key] = graph;
    drawingRevision++;
    _record(before, committed: true);
    _notifyPencil();
    return true;
  }

  Map<String, Set<String>> eraserIntersections(Offset a, Offset b) => {
    for (final graph in surfaceGraphs) graph.key: graph.intersections(a, b),
  };
  bool eraseDrawingLine(Offset a, Offset b) {
    final hits = eraserIntersections(a, b);
    if (hits.values.every((v) => v.isEmpty)) return false;
    final before = _snapshot();
    for (final entry in hits.entries) {
      final graph = drawingGraphs[entry.key]!;
      graph.replace(
        graph.edges
            .where((s) => !entry.value.contains(drawingEdgeKey(s)))
            .toList(),
      );
    }
    drawingRevision++;
    _record(before, committed: true);
    _notifyPencil();
    return true;
  }

  DrawingFace? drawingFaceAt(Offset p, {DrawingSurface? surface}) {
    final id = (surface ?? drawingSurface)?.id;
    final faces = [
      for (final graph in drawingGraphs.values.where((g) => g.surfaceId == id))
        ...graph.faces.where((f) => f.region.contains(p)),
    ];
    faces.sort((a, b) {
      final area = a.region.area - b.region.area;
      if (area.abs() > 1e-7) return area < 0 ? -1 : 1;
      final preferred = (a.graph.implement == lastDrawingImplement ? 0 : 1)
          .compareTo(b.graph.implement == lastDrawingImplement ? 0 : 1);
      if (preferred != 0) return preferred;
      return '${a.graph.key}/${a.id}'.compareTo('${b.graph.key}/${b.id}');
    });
    return faces.firstOrNull;
  }

  bool drawingSupported(DrawingSurface surface, Region region) {
    var remainder = [region];
    for (final id in surface.sources) {
      final p = planes[id];
      if (p == null) continue;
      final regions = p.owner != null
          ? [
              (p.id.contains('-side-') ||
                      objects[p.owner]?.kind == CraftKind.room)
                  ? p.region
                  : (objects[p.owner]?.region ?? p.region),
            ]
          : surfaceRegions(p);
      for (final r in regions) {
        final mapped = _inFrame(r, p, surface.frame);
        remainder = remainder.expand((part) => part.subtract(mapped)).toList();
      }
    }
    return remainder.isEmpty;
  }
}
