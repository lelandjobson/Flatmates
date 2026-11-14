part of 'controller.dart';

extension RegionPrograms on ProtoplaneController {
  bool commitRegionPath(
    RegionSurface surface,
    List<Offset> path, {
    required bool place,
  }) {
    if (path.length < 2) return false;
    final staged = ProtoplaneController(unlimitedPaper: unlimitedPaper)
      .._load(toJson());
    try {
      final supports = <String>{
        for (final id in surface.sources)
          ...surfaceFusion.members[id] ?? [?planes[id]?.owner],
      };
      if (place) {
        final material = _programSupport(surface);
        final simplified = <Offset>[];
        for (final point in path) {
          while (simplified.length > 1 &&
              onSegment(
                simplified.last,
                simplified[simplified.length - 2],
                point,
              )) {
            simplified.removeLast();
          }
          simplified.add(point);
        }
        final sourceId = 'program-frame-source-${staged.nextId}';
        final source = CraftPlane(
          id: sourceId,
          origin: surface.frame.origin + surface.frame.normal * .002,
          u: surface.frame.u,
          v: surface.frame.v,
          region: surface.region,
          grids: [lattice(sourceId, surface.region)],
          supports: supports.toList(),
        );
        staged.planes[sourceId] = source;
        final members = <String, String>{};
        var cost = 0.0;
        for (var i = 1; i < simplified.length; i++) {
          final segment = PencilSegment(simplified[i - 1], simplified[i]);
          final covered = newPencilCoverage([
            for (final r in material) ...clipPencil([segment], r),
          ], const []);
          if (covered.fold<double>(0, (v, s) => v + s.length) <
              segment.length - geometryEpsilon) {
            programIssue = ProgramIssue.support;
            _notifyPencil();
            return false;
          }
          final id = 'object-${staged.nextId++}', planeId = 'program-frame-$id';
          final horizontal = surface.frame.normal.y.abs() > .5;
          final attachment = LinearAttachment(
            sourcePlaneId: sourceId,
            a: segment.a,
            b: segment.b,
            supports: supports.toList(),
            side: horizontal
                ? (surface.frame.normal.y < 0 ? -1 : 1)
                : placementSide,
          );
          final basis = attachment.frame(planeId, source);
          final object = CraftObject(
            id: id,
            planeId: planeId,
            kind: horizontal ? CraftKind.wall : CraftKind.floor,
            region: basis.region,
            material: paper,
            depth: horizontal ? .02 : 0,
            linear: attachment,
          );
          for (final other in staged.objects.values) {
            if (supports.contains(other.id) ||
                members.containsValue(other.id)) {
              continue;
            }
            if (solidsOverlap(
              object,
              basis,
              other,
              staged.objectPlane(other),
            )) {
              programIssue = ProgramIssue.collision;
              _notifyPencil();
              return false;
            }
          }
          staged.planes[planeId] = basis;
          staged.objects[id] = object;
          members['panel-$i'] = id;
          cost += object.materialArea;
        }
        final quote = (cost * 128 - 1e-8).ceil();
        if (!canSpend(paper, quote)) {
          programIssue = ProgramIssue.paper;
          _notifyPencil();
          return false;
        }
        staged.spendPaper(paper, quote);
        final id = 'assembly-${members.values.first}';
        staged.assemblies[id] = ProgramAssembly(
          id: id,
          program: ProgramKind.place,
          frame: surface.frame,
          footprint: surface.region,
          components: members,
          supports: [...surface.sources, ...supports],
        );
      } else {
        var changed = false;
        for (final id in supports) {
          final object = staged.objects[id]!;
          final frame = staged.objectPlane(object);
          final points = path
              .map((p) => frame.local(surface.frame.point(p)))
              .toList();
          bool boundary(Offset p) => object.region.rings.any(
            (r) => edges(r).any((e) => onSegment(p, e.$1, e.$2)),
          );
          if (!boundary(points.first) || !boundary(points.last)) continue;
          final pieces = splitPaperByCuts(object.region.outer, [
            for (var i = 1; i < points.length; i++) (points[i - 1], points[i]),
          ], holes: object.region.holes);
          if (pieces.length < 2) continue;
          if (staged._hasDependents(id)) {
            programIssue = ProgramIssue.support;
            _notifyPencil();
            return false;
          }
          final marks = staged.pencilMarks.remove(id) ?? <PencilStroke>[];
          for (final (i, p) in pieces.indexed) {
            final key = i == 0 ? id : 'object-${staged.nextId++}',
                region = Region(p.$1, p.$2);
            staged.objects[key] = object.copyWith(id: key, region: region);
            staged.pencilMarks[key] = staged._clipStrokes(marks, region);
          }
          changed = true;
        }
        if (!changed) return false;
      }
      staged._derivePlanes();
      staged._validateLoaded();
      final before = _snapshot(), active = activePlaneId, editing = editId;
      final session = workspace.toJson();
      _load(staged.toJson());
      workspace.restore(session);
      activePlaneId = active;
      editId = editing;
      programIssue = null;
      _record(before, committed: true);
      _notifyPencil();
      return true;
    } finally {
      staged.dispose();
    }
  }

  void scrubRegion(RegionSurface surface, Offset from, Offset to) {
    final d = to - from;
    final angle = math.atan2(d.dy, d.dx), radius = .065;
    final ring = [
      for (var i = 0; i <= 8; i++)
        to +
            Offset(
                  math.cos(angle - math.pi / 2 + i * math.pi / 8),
                  math.sin(angle - math.pi / 2 + i * math.pi / 8),
                ) *
                radius,
      for (var i = 0; i <= 8; i++)
        from +
            Offset(
                  math.cos(angle + math.pi / 2 + i * math.pi / 8),
                  math.sin(angle + math.pi / 2 + i * math.pi / 8),
                ) *
                radius,
    ];
    final outline = Region(ring);
    if (!outline.valid) return;
    for (final part in outline.clipTo([surface.region])) {
      if (_removeProgramRegion(surface, part, erase: true) == null) {
        harvestPending = true;
      }
    }
    if (harvestPending) {
      _invalidateNavigation();
      _notifyPencil();
    }
  }

  double get drawingSpacing => 1 / (protoplaneCells ?? 2);

  RegionSurface? regionSurface(String planeId) {
    final picked = planes[planeId];
    if (picked == null) return null;
    final cached = _regionSurfaces[planeId];
    if (cached != null) {
      workspace.surfaces[cached.id] = cached;
      return cached;
    }
    final tile = landscape.terrain.tiles[planeId];
    final candidates = planes.values.where((p) {
      if (p.id == planeId) return true;
      if (!coplanar(picked, p) || !planeAvailable(p)) return false;
      if (tile != null) {
        final t = landscape.terrain.tiles[p.id];
        return t != null && t.sheet.island == tile.sheet.island;
      }
      return p.id.startsWith('surface-') &&
          !surfaceFusion.retired.contains(p.id);
    }).toList()..sort((a, b) => a.id.compareTo(b.id));
    final members = [picked];
    var domain = picked.region;
    candidates.removeWhere((p) => p.id == planeId);
    var changed = true;
    while (changed) {
      changed = false;
      for (final p in candidates.toList()) {
        final mapped = mapRegion(p.region, p, picked);
        if (!domain.overlaps(mapped) && !sharedRegionEdge(domain, mapped)) {
          continue;
        }
        final merged = domain.union(mapped);
        if (merged.length != 1 || !merged.single.valid) continue;
        domain = merged.single;
        members.add(p);
        candidates.remove(p);
        changed = true;
      }
    }
    members.sort((a, b) => a.id.compareTo(b.id));
    final anchor = members.first;
    var id = 'workspace-${anchor.id}';
    var frame = CraftPlane(
      id: id,
      origin: anchor.origin.clone(),
      u: anchor.u.clone(),
      v: anchor.v.clone(),
      region: mapRegion(domain, picked, anchor),
      grids: const [],
    );
    // Keep world-locked coordinates and region IDs as fused aliases change.
    for (final old in workspace.surfaces.values) {
      if (!coplanar(frame, old.frame)) continue;
      final mapped = mapRegion(frame.region, frame, old.frame);
      if (!mapped.overlaps(old.region)) continue;
      id = old.id;
      frame = CraftPlane(
        id: id,
        origin: old.frame.origin,
        u: old.frame.u,
        v: old.frame.v,
        region: mapped,
        grids: const [],
      );
      break;
    }
    final surface = RegionSurface(frame, members.map((p) => p.id).toList());
    workspace.surfaces[id] = surface;
    for (final p in members) {
      _regionSurfaces[p.id] = surface;
    }
    return surface;
  }

  CraftGrid drawingGrid(RegionSurface surface) => _regionGrids.putIfAbsent(
    '${surface.id}/$drawingSpacing/$protoplaneConnections',
    () => regionDrawingGrid(
      surface,
      drawingSpacing,
      protoplaneConnections ?? GridConnections.orthogonal,
    ),
  );

  void drawLightPath(RegionSurface surface, List<Offset> path) {
    final before = _snapshot();
    workspace.surfaces[surface.id] = surface;
    if (!workspace.draw(surface.id, path)) return;
    _record(before);
    _notifyPencil();
  }

  void clearRegions() {
    if (workspace.regions.isEmpty &&
        workspace.lines.values.every((s) => s.isEmpty)) {
      return;
    }
    final before = _snapshot();
    workspace.clear();
    _regionSurfaces.clear();
    _regionGrids.clear();
    pendingVolume = null;
    combineFirst = null;
    _record(before);
    _notifyPencil();
  }

  bool combineRegion(LightRegion target) {
    final first = combineFirst;
    if (first == null) {
      combineFirst = target;
      _notifyPencil();
      return false;
    }
    final before = _snapshot();
    if (!workspace.combine(first, target)) {
      programIssue = ProgramIssue.outline;
      _notifyPencil();
      return false;
    }
    combineFirst = null;
    programIssue = null;
    _record(before);
    _notifyPencil();
    return true;
  }

  void selectProgram(ProgramKind value) {
    if (_gestureBefore != null) cancelGesture();
    selectedProgram = value;
    pendingVolume = null;
    combineFirst = null;
    programIssue = null;
    tool = value == ProgramKind.combine ? CraftTool.combine : CraftTool.program;
    _notifyPencil();
  }

  List<Region> _programSupport(RegionSurface surface) {
    final result = <Region>[];
    for (final id in surface.sources) {
      final p = planes[id];
      if (p == null) continue;
      for (final r in surfaceRegions(p)) {
        result.add(mapRegion(r, p, surface.frame));
      }
    }
    return result;
  }

  ProgramEvaluation evaluateProgram(
    ProgramKind kind,
    LightRegion target,
    RegionSurface surface,
    Offset drop, {
    double depth = .1,
  }) {
    ProgramEvaluation failure(ProgramIssue issue, [int quote = 0]) =>
        ProgramEvaluation(
          program: kind,
          target: target,
          surface: surface,
          drop: drop,
          revision: programRevision,
          regionRevision: workspace.revision,
          depth: depth,
          issue: issue,
          quote: quote,
        );
    if (!target.geometry.valid ||
        !surface.region.containsRegion(target.geometry)) {
      return failure(ProgramIssue.outline);
    }
    if (!target.implied && !workspace.regions.containsKey(target.id)) {
      return failure(ProgramIssue.stale);
    }
    if (target.id.startsWith('implied:') &&
        workspace
            .on(surface.id)
            .any((r) => r.geometry.overlaps(target.geometry))) {
      return failure(ProgramIssue.stale);
    }
    if (kind == ProgramKind.combine) return failure(ProgramIssue.outline);
    final staged = ProtoplaneController(unlimitedPaper: unlimitedPaper);
    try {
      staged.protoplaneCells = protoplaneCells;
      staged.protoplaneConnections = protoplaneConnections;
      staged._load(toJson());
      final beforeObjects = Map<String, CraftObject>.of(staged.objects);
      final result = staged._buildProgram(kind, target, surface, drop, depth);
      if (result.$1 != null) return failure(result.$1!, result.$2);
      if (!canSpend(paper, result.$2)) {
        return failure(ProgramIssue.paper, result.$2);
      }
      staged.spendPaper(paper, result.$2);
      staged._derivePlanes();
      staged._validateLoaded();
      final created = staged.objects.values
          .where((o) => !identical(beforeObjects[o.id], o))
          .toList();
      final assembly = staged.assemblies.values.lastOrNull;
      return ProgramEvaluation(
        program: kind,
        target: target,
        surface: surface,
        drop: drop,
        revision: programRevision,
        regionRevision: workspace.revision,
        depth: depth,
        quote: result.$2,
        world: staged.toJson(),
        objects: created,
        frames: {for (final o in created) o.id: staged.objectPlane(o)},
        water: kind == ProgramKind.pool ? assembly?.water : null,
      );
    } on FormatException {
      return failure(ProgramIssue.support);
    } finally {
      staged.dispose();
    }
  }

  bool applyProgram(
    ProgramEvaluation evaluation, {
    bool confirmVolume = false,
  }) {
    // Always evaluate against current material, inventory, and dependencies.
    if (!evaluation.target.implied &&
        !workspace.regions.containsKey(evaluation.target.id)) {
      programIssue = ProgramIssue.stale;
      _notifyPencil();
      return false;
    }
    final fresh = evaluateProgram(
      evaluation.program,
      evaluation.target,
      evaluation.surface,
      evaluation.drop,
      depth: evaluation.depth,
    );
    if (!fresh.valid) {
      programIssue = fresh.issue;
      _notifyPencil();
      return false;
    }
    if (fresh.program == ProgramKind.volume && !confirmVolume) {
      pendingVolume = fresh;
      programIssue = null;
      _notifyPencil();
      return true;
    }
    final before = _snapshot();
    final active = activePlaneId, editing = editId;
    final session = workspace.toJson();
    _load(fresh.world!);
    workspace.restore(session);
    workspace.consume(fresh.target);
    activePlaneId = planes.containsKey(active) ? active : null;
    editId = objects.containsKey(editing) ? editing : null;
    pendingVolume = null;
    programIssue = null;
    _gestureBefore = null;
    _record(before, committed: true);
    _notifyPencil();
    return true;
  }

  void setProgramDepth(double value) {
    final p = pendingVolume;
    if (p == null) return;
    pendingVolume = evaluateProgram(
      p.program,
      p.target,
      p.surface,
      p.drop,
      depth: value.clamp(.01, 1),
    );
    programIssue = pendingVolume!.issue;
    _notifyPencil();
  }

  void cancelProgramVolume() {
    pendingVolume = null;
    programIssue = null;
    _notifyPencil();
  }

  /// Water is derived from the saved basin and its current editable panels.
  /// A removed or shortened lining, or a hole in the bottom, drains the basin.
  Region? poolWater(ProgramAssembly assembly) {
    final water = assembly.water;
    if (water == null || assembly.program != ProgramKind.pool) return null;
    final level = assembly.parameters['waterLevel'] ?? -.05;
    final bottoms = <Region>[], liners = <Region>[];
    for (final entry in assembly.components.entries) {
      final object = objects[entry.value];
      if (object == null) continue;
      final plane = objectPlane(object);
      if (plane.normal.dot(assembly.frame.normal) < .999) continue;
      final base = (plane.origin - assembly.frame.origin).dot(
        assembly.frame.normal,
      );
      final shape = mapRegion(object.region, plane, assembly.frame);
      if (entry.key.startsWith('bottom') && base + object.depth < level) {
        bottoms.add(shape);
      } else if (entry.key.startsWith('lining-') &&
          base <= level &&
          base + object.depth >= level) {
        liners.add(shape);
      }
    }
    List<Region> uncovered(List<Region> regions, List<Region> covers) {
      for (final cover in covers) {
        regions = regions.expand((r) => r.subtract(cover)).toList();
      }
      return regions;
    }

    if (uncovered([water], bottoms).fold<double>(0, (sum, r) => sum + r.area) >
            geometryEpsilon ||
        uncovered(
              assembly.footprint.subtract(water),
              liners,
            ).fold<double>(0, (sum, r) => sum + r.area) >
            geometryEpsilon) {
      return null;
    }
    return water;
  }

  (ProgramIssue?, int) _buildProgram(
    ProgramKind kind,
    LightRegion target,
    RegionSurface surface,
    Offset drop,
    double depth,
  ) {
    final frame = surface.frame, region = target.geometry;
    if (kind == ProgramKind.cut || kind == ProgramKind.erase) {
      final issue = _removeProgramRegion(
        surface,
        region,
        erase: kind == ProgramKind.erase,
      );
      return (issue, 0);
    }
    final horizontal = frame.normal.y.abs() > .999;
    if ([
          ProgramKind.house,
          ProgramKind.pool,
          ProgramKind.rug,
          ProgramKind.table,
        ].contains(kind) &&
        !horizontal) {
      return (ProgramIssue.orientation, 0);
    }
    if (kind == ProgramKind.pictureFrame && frame.normal.y.abs() > .001) {
      return (ProgramIssue.orientation, 0);
    }
    final support = _programSupport(surface);
    final supported = region.clipTo(support);
    if (supported.isEmpty) return (ProgramIssue.support, 0);
    final original = Map<String, CraftObject>.of(objects);
    final componentIds = <String, String>{};
    final sourceOwners = <String>{
      for (final id in surface.sources)
        ...surfaceFusion.members[id] ?? [?planes[id]?.owner],
    };
    final assemblyId = 'assembly-$nextId';
    var used = region;
    Region? water;
    double? poolDepth;
    var reusedMaterialArea = 0.0;

    String panel(
      String role,
      CraftKind type,
      Region outline,
      CraftPlane basis,
      double thickness, {
      String? owner,
      List<String>? supports,
    }) {
      final id = 'object-${nextId++}', planeId = 'program-frame-$id';
      planes[planeId] = CraftPlane(
        id: planeId,
        origin: basis.origin.clone(),
        u: basis.u.clone(),
        v: basis.v.clone(),
        region: outline,
        grids: [lattice(planeId, outline)],
        owner: owner,
        supports: supports ?? sourceOwners.toList(),
      );
      objects[id] = CraftObject(
        id: id,
        planeId: planeId,
        kind: type,
        region: outline,
        material: paper,
        depth: thickness,
      );
      componentIds[role] = id;
      return id;
    }

    CraftPlane shifted(double amount) => CraftPlane(
      id: 'basis',
      origin: frame.origin + frame.normal * amount,
      u: frame.u,
      v: frame.v,
      region: region,
      grids: const [],
    );

    if ([
      ProgramKind.house,
      ProgramKind.table,
      ProgramKind.pictureFrame,
    ].contains(kind)) {
      final minimum = switch (kind) {
        ProgramKind.house => 1.0,
        ProgramKind.table => .5,
        _ => .25,
      };
      var free = supported;
      final height = kind == ProgramKind.house
          ? 1.04
          : kind == ProgramKind.table
          ? .35
          : .02;
      for (final o in original.values) {
        if (sourceOwners.contains(o.id)) continue;
        final p = objectPlane(o);
        for (final cell in collisionCells(o, p)) {
          final distances = cell
              .map((v) => (v - frame.origin).dot(frame.normal))
              .toList();
          if (distances.reduce(math.max) <= .001 ||
              distances.reduce(math.min) >= height) {
            continue;
          }
          final projected = Region(convexHull(cell.map(frame.local).toList()));
          if (!projected.valid) continue;
          free = free.expand((r) => r.subtract(projected)).toList();
        }
      }
      Rect? best;
      for (final part in free) {
        final candidate = largestRegionRectangle(
          part,
          spacing: drawingSpacing,
          minimum: minimum,
          nearPoint: drop,
        );
        if (candidate == null) continue;
        if (preferRegionRectangle(candidate, best, drop)) best = candidate;
      }
      if (best == null) {
        bool fits(Region r) =>
            largestRegionRectangle(
              r,
              spacing: drawingSpacing,
              minimum: minimum,
              nearPoint: drop,
            ) !=
            null;
        return (
          !fits(region)
              ? ProgramIssue.tooSmall
              : !supported.any(fits)
              ? ProgramIssue.support
              : ProgramIssue.collision,
          0,
        );
      }
      used = rectangle(best.width, best.height, origin: best.topLeft);
    } else if ((supported.fold<double>(0, (s, r) => s + r.area) - region.area)
                .abs() >
            1e-5 &&
        kind != ProgramKind.place) {
      return (ProgramIssue.support, 0);
    }

    if (kind == ProgramKind.house) {
      final floor = panel('floor', CraftKind.floor, used, shifted(.002), .02);
      final ring = used.outer;
      var doorSide = 0, nearest = double.infinity;
      for (var i = 0; i < ring.length; i++) {
        final a = ring[i], edge = ring[(i + 1) % ring.length] - a;
        final delta = drop - a;
        final t =
            ((delta.dx * edge.dx + delta.dy * edge.dy) / edge.distanceSquared)
                .clamp(0.0, 1.0);
        final d = (a + edge * t - drop).distanceSquared;
        if (d < nearest) {
          nearest = d;
          doorSide = i;
        }
      }
      final walls = <String>[];
      for (var i = 0; i < ring.length; i++) {
        final a = ring[i],
            b = ring[(i + 1) % ring.length],
            length = (b - a).distance;
        final wallFrame = CraftPlane(
          id: 'wall',
          origin: frame.point(b, .022),
          u: (frame.point(a) - frame.point(b)).normalized(),
          v: frame.normal,
          region: rectangle(length, 1),
          grids: const [],
        );
        var shape = wallFrame.region;
        if (i == doorSide) {
          shape = shape
              .subtract(
                rectangle(.25, .7, origin: Offset((length - .25) / 2, 0)),
              )
              .single;
        }
        walls.add(
          panel(
            'wall-$i',
            CraftKind.wall,
            shape,
            wallFrame,
            .02,
            owner: floor,
            supports: [floor],
          ),
        );
      }
      panel(
        'roof',
        CraftKind.floor,
        used,
        shifted(1.022),
        .02,
        owner: floor,
        supports: walls,
      );
    } else if (kind == ProgramKind.pool) {
      if (region.area < .25 - geometryEpsilon) {
        return (ProgramIssue.tooSmall, 0);
      }
      final inset = insetProgramRegion(region, .02);
      if (inset.length != 1 || inset.single.area < geometryEpsilon) {
        return (ProgramIssue.outline, 0);
      }
      water = inset.single;
      poolDepth = .5;
      final excavation = CraftObject(
        id: 'excavation',
        planeId: 'excavation',
        kind: CraftKind.poolLining,
        region: region,
        depth: .5,
      );
      for (final other in original.values) {
        if (sourceOwners.contains(other.id)) continue;
        if (solidsOverlap(
          excavation,
          shifted(-.5),
          other,
          objectPlane(other),
        )) {
          return (ProgramIssue.collision, 0);
        }
      }
      final issue = _removeProgramRegion(surface, region, excavation: .5);
      if (issue != null) return (issue, 0);
      sourceOwners.removeWhere((id) => !objects.containsKey(id));
      final bottom = panel(
        'bottom',
        CraftKind.floor,
        region,
        shifted(-.5),
        .02,
      );
      final lining = region.subtract(water);
      for (final (i, r) in lining.indexed) {
        panel(
          'lining-$i',
          CraftKind.poolLining,
          r,
          shifted(-.48),
          .48,
          owner: bottom,
          supports: sourceOwners.toList(),
        );
      }
    } else if (kind == ProgramKind.table) {
      final b = used.bounds, legs = <String>[];
      final side = math.min(.06, math.min(b.width, b.height) * .12);
      for (final x in [b.left + .03, b.right - .03 - side]) {
        for (final y in [b.top + .03, b.bottom - .03 - side]) {
          legs.add(
            panel(
              'leg-${legs.length}',
              CraftKind.tableLeg,
              rectangle(side, side, origin: Offset(x, y)),
              shifted(.002),
              .32,
            ),
          );
        }
      }
      panel(
        'top',
        CraftKind.tabletop,
        used,
        shifted(.322),
        .03,
        supports: [...sourceOwners, ...legs],
      );
    } else if (kind == ProgramKind.pictureFrame) {
      final b = used.bounds, border = math.min(b.width, b.height) * .1;
      final inner = b.deflate(border);
      panel(
        'frame',
        CraftKind.pictureFrame,
        Region(used.outer, [
          rectangle(inner.width, inner.height, origin: inner.topLeft).outer,
        ]),
        shifted(.002),
        .02,
      );
    } else if (kind == ProgramKind.rug) {
      panel('rug', CraftKind.rug, used, shifted(.002), .005);
    } else if (kind == ProgramKind.place) {
      if (!horizontal && frame.normal.y.abs() > .001) {
        return (ProgramIssue.orientation, 0);
      }
      panel(
        'paper',
        horizontal ? CraftKind.floor : CraftKind.wall,
        region,
        shifted(.002),
        horizontal ? 0 : .02,
      );
    } else if (kind == ProgramKind.volume) {
      // Remove only selected crafted paper, keeping all unrelated pieces intact.
      final selected = sourceOwners
          .where((id) => objects[id]?.material == PaperMaterial.paperWhite)
          .toList();
      if (selected.isEmpty && !surface.sources.any(isLandscapePaper)) {
        return (ProgramIssue.material, 0);
      }
      var baseOffset = 0.0;
      if (selected.isNotEmpty) {
        final depths = selected.map((id) => objects[id]!.depth).toSet();
        if (depths.length != 1) return (ProgramIssue.outline, 0);
        baseOffset = -depths.single - .002;
        for (final id in selected) {
          final object = objects[id]!, source = objectPlane(objects[id]!);
          for (final part in mapRegion(
            region,
            frame,
            source,
          ).clipTo([object.region])) {
            reusedMaterialArea += part.area + part.perimeter * object.depth;
          }
        }
      } else {
        reusedMaterialArea = region.area;
        final tile = surface.sources
            .map((id) => landscape.terrain.tiles[id])
            .where((tile) => tile != null)
            .firstOrNull;
        baseOffset = -(tile?.sheet.thickness ?? 0);
      }
      final issue = _removeProgramRegion(surface, region, onlyPaper: true);
      if (issue != null) return (issue, 0);
      sourceOwners.removeWhere((id) => !objects.containsKey(id));
      panel(
        'volume',
        horizontal ? CraftKind.floor : CraftKind.wall,
        region,
        shifted(baseOffset),
        depth,
      );
    }

    final created = componentIds.values.map((id) => objects[id]!).toList();
    for (final object in created) {
      final basis = planes[object.planeId]!;
      for (final other in objects.values) {
        if (other.id == object.id ||
            sourceOwners.contains(other.id) ||
            basis.supports.contains(other.id) ||
            other.id == basis.owner ||
            _ancestor(other.id, basis.owner)) {
          continue;
        }
        if (solidsOverlap(object, basis, other, objectPlane(other))) {
          // House walls meet at their construction corners. They are one shell.
          if (kind == ProgramKind.house &&
              componentIds.containsValue(other.id) &&
              object.kind == CraftKind.wall &&
              other.kind == CraftKind.wall) {
            continue;
          }
          return (ProgramIssue.collision, 0);
        }
      }
    }
    final cost =
        (math.max(
                      0,
                      created.fold<double>(0, (n, o) => n + o.materialArea) -
                          reusedMaterialArea,
                    ) *
                    128 -
                1e-8)
            .ceil();
    assemblies[assemblyId] = ProgramAssembly(
      id: assemblyId,
      program: kind,
      frame: frame,
      footprint: used,
      components: componentIds,
      supports: [...surface.sources, ...sourceOwners],
      water: water,
      parameters: {
        if (kind == ProgramKind.house) ...{
          'storyHeight': 1,
          'thickness': .02,
          'doorwayWidth': .25,
          'doorwayHeight': .7,
          'dropX': drop.dx,
          'dropY': drop.dy,
        },
        if (kind == ProgramKind.table) ...{'height': .35, 'topThickness': .03},
        if (kind == ProgramKind.pictureFrame) ...{
          'borderFraction': .1,
          'depth': .02,
        },
        if (kind == ProgramKind.rug) 'thickness': .005,
        if (kind == ProgramKind.volume) 'depth': depth,
        'depth': ?poolDepth,
        if (water != null) ...{'waterLevel': -.05, 'lining': .02},
      },
    );
    return (null, cost);
  }

  ProgramIssue? _removeProgramRegion(
    RegionSurface surface,
    Region region, {
    bool erase = false,
    double? excavation,
    bool onlyPaper = false,
  }) {
    var changed = false;
    final members = <String>{};
    for (final id in surface.sources) {
      final p = planes[id];
      if (p == null) continue;
      if (p.owner != null) {
        members.addAll(surfaceFusion.members[id] ?? [p.owner!]);
      }
    }
    for (final id in members) {
      final object = objects[id];
      if (object == null) continue;
      final p = objectPlane(object),
          cut = mapRegion(region, surface.frame, objectPlane(object));
      if (!object.region.overlaps(cut)) continue;
      if (erase) {
        final old = pencilMarks[id] ?? [];
        final boundary = [
          for (final ring in cut.rings)
            for (final e in edges(ring)) PencilSegment(e.$1, e.$2),
        ];
        final next = [
          for (final s in old)
            PencilStroke(s.id, [
              for (final line in s.segments)
                for (final part in splitPencil(line, boundary))
                  if (!cut.contains((part.a + part.b) / 2)) part,
            ]),
        ];
        if (jsonEncode(old.map((s) => s.toJson()).toList()) !=
            jsonEncode(next.map((s) => s.toJson()).toList())) {
          pencilMarks[id] = next;
          changed = true;
        }
        continue;
      }
      if (_hasDependents(id)) return ProgramIssue.support;
      final remaining = object.region.subtract(cut);
      final marks = pencilMarks.remove(id) ?? <PencilStroke>[];
      objects.remove(id);
      for (final (i, r) in remaining.indexed) {
        final key = i == 0 ? id : 'object-${nextId++}';
        objects[key] = object.copyWith(id: key, region: r);
        pencilMarks[key] = _clipStrokes(marks, r);
      }
      changed = true;
      // Preserve the support frame until derived surfaces have been rebuilt.
      planes[p.id] = p;
    }
    final terrainTargets = excavation == null
        ? surface.sources.where(landscape.terrain.tiles.containsKey).toList()
        : landscape.terrain.tiles.values
              .where((t) {
                final top = t.sheet.elevation;
                final relative = top - surface.frame.origin.y;
                return relative <= geometryEpsilon &&
                    relative > -excavation - geometryEpsilon;
              })
              .map((t) => t.id)
              .toList();
    for (final id in terrainTargets) {
      final p = planes[id]!;
      final cut = mapRegion(region, surface.frame, p);
      final tile = landscape.terrain.tiles[id]!;
      if (onlyPaper && tile.sheet.material != PaperMaterial.paperWhite) {
        continue;
      }
      if (erase) {
        if (tile.sheet.material != PaperMaterial.graphite) {
          final old = pencilMarks[id] ?? [];
          final keep = surfaceRegions(
            p,
          ).expand((r) => r.subtract(cut)).toList();
          final next = [
            for (final s in old)
              PencilStroke(s.id, [
                for (final r in keep) ...clipPencil(s.segments, r),
              ]),
          ];
          if (jsonEncode(old.map((s) => s.toJson()).toList()) !=
              jsonEncode(next.map((s) => s.toJson()).toList())) {
            pencilMarks[id] = next;
            changed = true;
          }
          continue;
        }
        final brush = GraphiteBrush(
          landscape.terrain.remainingInTile(id),
          landscape.terrain.exposed(id),
          [
            for (final o in objects.values.where((o) => o.planeId == id))
              ...occupancy(o),
          ],
        );
        final cells = [
          for (var i = 0; i < GraphiteMask.count; i++)
            if (brush.areas[i] > 0 &&
                brush.regions(i).every(cut.containsRegion))
              i,
        ];
        if (cells.isEmpty) continue;
        final credit = landscape.eraseGraphite(
          id,
          cells,
          cells.fold<double>(0, (s, i) => s + brush.areas[i]),
        );
        balances[PaperMaterial.graphite] =
            balances[PaperMaterial.graphite]! + credit;
        changed = true;
        continue;
      }
      final harvest = landscape.preview(p, cut);
      if (harvest == null) continue;
      if (excavation == null && tile.sheet.material == PaperMaterial.graphite) {
        return ProgramIssue.material;
      }
      if (_harvestBlocked(harvest)) return ProgramIssue.support;
      if (onlyPaper) {
        for (final patch in harvest.patches) {
          landscape.deplete(id, patch.region);
        }
      } else {
        for (final e in landscape.collect(harvest).entries) {
          balances[e.key] = balances[e.key]! + e.value;
        }
      }
      changed = true;
    }
    if (changed) {
      _marksChanged();
      return null;
    }
    return ProgramIssue.empty;
  }
}
