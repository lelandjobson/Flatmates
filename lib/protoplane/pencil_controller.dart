part of 'controller.dart';

extension PencilCrafting on ProtoplaneController {
  bool isLandscapePaper(String id) =>
      landscape.terrain?.tiles[id]?.sheet.material == PaperMaterial.paperWhite;

  List<CraftPlane> get landscapePaperPlanes => terrainColumn
      .where((p) => isLandscapePaper(p.id) && surfaceRegions(p).isNotEmpty)
      .toList();

  bool get paperSurface =>
      preset == WorldPreset.paper &&
      activePlane != null &&
      (landscapePaperPlanes.isNotEmpty ||
          ((editId != null || activePlane!.id.startsWith('surface-')) &&
              objects[editId ?? activePlane!.owner]?.material ==
                  PaperMaterial.paperWhite));

  List<String> paperMembers(CraftPlane plane) {
    if (isLandscapePaper(plane.id)) return [plane.id];
    if (plane.id == activePlaneId && landscapePaperPlanes.isNotEmpty) {
      return landscapePaperPlanes.map((p) => p.id).toList();
    }
    return editId != null && plane.id == activePlaneId
        ? [editId!]
        : surfaceFusion.members[plane.id] ??
              [if (plane.owner != null) plane.owner!];
  }

  CraftPlane? _markFrame(String id) =>
      isLandscapePaper(id) ? planes[id] : planes[objects[id]?.planeId];
  List<Region> _markRegions(String id) => isLandscapePaper(id)
      ? surfaceRegions(planes[id]!)
      : [if (objects[id] != null) objects[id]!.region];

  List<Region> get paperRegions => landscapePaperPlanes.isNotEmpty
      ? [for (final p in landscapePaperPlanes) ...surfaceRegions(p)]
      : [paperRegion];
  bool paperContains(Offset p) => paperRegions.any((r) => r.contains(p));
  List<PencilSegment> clipToPaper(Iterable<PencilSegment> segments) =>
      newPencilCoverage([
        for (final r in paperRegions) ...clipPencil(segments, r),
      ], const []);

  List<CraftKind> get landscapeRecipes => const [
    CraftKind.rug,
    CraftKind.tabletop,
    CraftKind.bench,
    CraftKind.planter,
    CraftKind.screen,
    CraftKind.bedFrame,
    CraftKind.lamp,
    CraftKind.storage,
  ];

  CraftKind? supportKind(CraftPlane plane) =>
      isLandscapePaper(plane.id) ? CraftKind.floor : objects[plane.owner]?.kind;

  /// Stored coordinates belong to each object's original support frame. Fused
  /// aliases are just query frames; no mark is owned by a transient union ID.
  List<PencilSegment> marksOn(CraftPlane plane) {
    final result = <PencilSegment>[];
    for (final id in paperMembers(plane)) {
      final source = _markFrame(id);
      if (source == null) continue;
      for (final stroke in pencilMarks[id] ?? <PencilStroke>[]) {
        for (final region in _markRegions(id)) {
          result.addAll(
            clipPencil(
              stroke.segments,
              region,
            ).map((s) => s.map((p) => plane.local(source.point(p)))),
          );
        }
      }
    }
    return newPencilCoverage(result, const []);
  }

  Region get paperRegion =>
      objects[editId]?.region ??
      (surfaceFusion.members.containsKey(activePlaneId)
          ? activePlane!.region
          : objects[activePlane!.owner]?.region ?? activePlane!.region);

  void _refreshPaperGrids() {
    if (preset != WorldPreset.paper) return;
    pencilMarks.removeWhere(
      (id, _) => !objects.containsKey(id) && !isLandscapePaper(id),
    );
    for (final id in pencilMarks.keys.toList()) {
      pencilMarks[id] = [
        for (final stroke in pencilMarks[id]!)
          PencilStroke(
            stroke.id,
            newPencilCoverage([
              for (final region in _markRegions(id))
                ...clipPencil(stroke.segments, region),
            ], const []),
          ),
      ]..removeWhere((s) => s.segments.isEmpty);
    }
    for (final p in planes.values.toList()) {
      if (!p.id.startsWith('surface-')) continue;
      final object = objects[p.owner];
      if (object == null || object.material != PaperMaterial.paperWhite) {
        continue;
      }
      final region = surfaceFusion.members.containsKey(p.id)
          ? p.region
          : object.region;
      planes[p.id] = p.withGrids([
        paperDrawingGrid(
          p.id,
          region,
          marksOn(p),
          p.grids.expand((g) => g.recipes).toSet().toList(),
        ),
      ]);
    }
    _paperGrids.clear();
  }

  CraftGrid get paperGrid {
    final plane = activePlane!;
    final key =
        '${plane.id}/$editId/${tool == CraftTool.pencil}/${terrainColumn.map((p) => landscape.revision(p.id)).join(',')}';
    return _paperGrids.putIfAbsent(
      key,
      () => paperDrawingGrid(
        plane.id,
        paperRegion,
        marksOn(plane),
        landscapePaperPlanes.isNotEmpty
            ? landscapeRecipes
            : plane.grids.expand((g) => g.recipes).toSet().toList(),
        pencil: tool == CraftTool.pencil,
        material: landscapePaperPlanes.isNotEmpty && tool != CraftTool.pencil
            ? [for (final p in terrainColumn) ...surfaceRegions(p)]
            : paperRegions,
      ),
    );
  }

  void _marksChanged({Set<String>? affected}) {
    markingRevision++;
    if (affected == null) {
      _paperGrids.clear();
    } else {
      _paperGrids.removeWhere((key, _) {
        final p = planes[key.split('/').first];
        return p == null || paperMembers(p).any(affected.contains);
      });
    }
    // Existing scissors drafts refer to indices in the previous drawing graph.
    drafts.removeWhere((key, _) => key.contains('-paper/'));
  }

  void cancelPencil() {
    pencilPreview.clear();
    motifTile = null;
  }

  void beginPencil(Offset p) {
    if (!paperSurface) return;
    cancelPencil();
    error = null;
    extendPencil(p);
  }

  void extendPencil(Offset p) {
    if (!paperSurface || !paperContains(p)) {
      cancelPencil();
      _notifyPencil(previewOnly: true);
      return;
    }
    final snapped = Offset((p.dx * 4).round() / 4, (p.dy * 4).round() / 4);
    if (!paperContains(snapped)) return;
    if (selectedMotif != null) {
      motifTile = Offset(p.dx.floorToDouble(), p.dy.floorToDouble());
    } else if (pencilPreview.isEmpty || !near(pencilPreview.last, snapped)) {
      // Include every quarter-lattice dot lying on the chosen segment.
      if (pencilPreview.isNotEmpty) {
        final from = pencilPreview.last;
        final between =
            paperGrid.nodes
                .where(
                  (n) =>
                      !near(n, from) &&
                      !near(n, snapped) &&
                      onSegment(n, from, snapped),
                )
                .toList()
              ..sort(
                (a, b) => (a - from).distanceSquared.compareTo(
                  (b - from).distanceSquared,
                ),
              );
        pencilPreview.addAll(between);
      }
      pencilPreview.add(snapped);
    }
    _notifyPencil(previewOnly: true);
  }

  List<PencilSegment> get previewMarks =>
      selectedMotif != null && motifTile != null
      ? clipToPaper(
          selectedMotif!.segments(tile: motifTile!, turns: motifTurns),
        )
      : pencilPreview.isEmpty
      ? []
      : clipToPaper([
          for (var i = 1; i < pencilPreview.length; i++)
            PencilSegment(pencilPreview[i - 1], pencilPreview[i]),
        ]);

  void selectMotif(PencilMotif motif) {
    if (!discoveredMotifs.contains(motif)) return;
    cancelPencil();
    selectedMotif = motif;
    motifTurns = 0;
    final center = paperRegion.bounds.center;
    motifTile = Offset(center.dx.floorToDouble(), center.dy.floorToDouble());
    _notifyPencil(previewOnly: true);
  }

  void rotateMotif() {
    motifTurns = (motifTurns + 1) % 4;
    _notifyPencil();
  }

  bool commitPencil() => commitMarks(previewMarks);

  bool commitMarks(List<PencilSegment> segments) {
    if (!paperSurface) return false;
    final plane = activePlane!;
    final fresh = newPencilCoverage(clipToPaper(segments), marksOn(plane));
    final cost = (fresh.fold<double>(0, (sum, s) => sum + s.length) * 4000)
        .round();
    final balance =
        (balances[PaperMaterial.graphite] ?? 0) * 1000 + graphiteMilli;
    if (cost > balance) {
      report('Not enough graphite. Harvest graphite or shorten the stroke.');
      return false;
    }
    if (fresh.isEmpty) {
      cancelPencil();
      _notifyPencil();
      return true;
    }
    final before = _snapshot();
    final strokeId = 'pencil-${nextStrokeId++}';
    for (final id in paperMembers(plane)) {
      final source = _markFrame(id)!;
      final local = newPencilCoverage([
        for (final region in _markRegions(id))
          ...clipPencil(
            fresh.map((s) => s.map((p) => source.local(plane.point(p)))),
            region,
          ),
      ], const []);
      if (local.isNotEmpty) {
        (pencilMarks[id] ??= []).add(PencilStroke(strokeId, local));
      }
    }
    balances[PaperMaterial.graphite] = (balance - cost) ~/ 1000;
    graphiteMilli = (balance - cost) % 1000;
    _marksChanged(affected: paperMembers(plane).toSet());
    final marks = marksOn(plane), bounds = paperRegion.bounds;
    for (var x = bounds.left.floor(); x < bounds.right.ceil(); x++) {
      for (var y = bounds.top.floor(); y < bounds.bottom.ceil(); y++) {
        final tile = Offset(x.toDouble(), y.toDouble());
        final tileRegion = Region([
          tile,
          tile + const Offset(1, 0),
          tile + const Offset(1, 1),
          tile + const Offset(0, 1),
        ]);
        if (!paperRegions.any((r) => r.containsRegion(tileRegion))) continue;
        for (final motif in PencilMotif.values) {
          if (!discoveredMotifs.contains(motif) && motif.covered(marks, tile)) {
            discoveredMotifs.add(motif);
            motifNotices.add(motif);
          }
        }
      }
    }
    cancelPencil();
    _record(before, committed: true);
    _notifyPencil();
    return true;
  }

  void eraseMarks(Offset a, Offset b, {double radius = .035}) {
    if (!paperSurface) return;
    final plane = activePlane!;
    double distance(Offset p, Offset a, Offset b) {
      final d = b - a;
      final t = d.distanceSquared == 0
          ? 0.0
          : (((p - a).dx * d.dx + (p - a).dy * d.dy) / d.distanceSquared).clamp(
              0.0,
              1.0,
            );
      return (p - a - d * t).distance;
    }

    var changed = false;
    for (final id in paperMembers(plane)) {
      final source = _markFrame(id)!;
      pencilMarks[id] = [
        for (final stroke in pencilMarks[id] ?? <PencilStroke>[])
          PencilStroke(
            stroke.id,
            stroke.segments.where((s) {
              final p = plane.local(source.point(s.a)),
                  q = plane.local(source.point(s.b));
              final touched =
                  segmentsTouch(a, b, p, q) ||
                  distance(p, a, b) <= radius ||
                  distance(q, a, b) <= radius ||
                  distance(a, p, q) <= radius ||
                  distance(b, p, q) <= radius;
              changed |= touched;
              return !touched;
            }).toList(),
          ),
      ]..removeWhere((s) => s.segments.isEmpty);
    }
    if (changed) {
      _marksChanged(affected: paperMembers(plane).toSet());
      harvestPending = true;
      _notifyPencil();
    }
  }

  List<PencilStroke> _clipStrokes(List<PencilStroke> strokes, Region region) =>
      [
        for (final s in strokes)
          PencilStroke(s.id, clipPencil(s.segments, region)),
      ]..removeWhere((s) => s.segments.isEmpty);
}
