part of 'controller.dart';

extension Construction on ProtoplaneController {
  double drawingSpacingFor(String planeId) {
    final plane = planes[planeId];
    final object = objects[plane?.owner];
    if (object != null) return object.drawingSpacing ?? .25;
    return 1;
  }

  ConstructionTarget? constructionTarget(String planeId, Offset point) {
    final plane = planes[planeId], surface = drawingSurfaceFor(planeId);
    if (plane == null || surface == null) return null;
    final face = drawingFaceAt(point, surface: surface);
    final fallback = _inFrame(plane.region, plane, surface.frame);
    if (!fallback.contains(point)) return null;
    return ConstructionTarget(
      planeId,
      surface,
      point,
      face?.region ?? fallback,
      drawingSpacingFor(planeId),
      context: contextFor(planeId),
      roomId: plane.roomId,
    );
  }

  ConstructionEvaluation evaluateConstruction(
    ConstructionTool tool,
    String planeId,
    Offset point, {
    ConstructionPaper? paper,
  }) {
    final selectedPaper = paper ?? constructionPaper;
    var target = constructionTarget(planeId, point);
    ConstructionEvaluation fail(String issue) => ConstructionEvaluation(
      tool,
      target,
      issue: issue,
      paper: selectedPaper,
    );
    if (target == null || tool == ConstructionTool.pencil) {
      return fail('Aim at a paper surface');
    }
    final plane = planes[planeId]!;
    final owner = objects[plane.owner];
    CraftPlane frame;
    CraftObject object;
    String? replacement;
    if (tool == ConstructionTool.scissors) {
      if (owner?.kind != CraftKind.room ||
          plane.roomFace?.startsWith('wall-') != true) {
        return fail('Aim at a drawn wall region');
      }
      final face = drawingFaceAt(point, surface: target.surface);
      if (face == null) return fail('Draw a closed wall boundary first');
      final panel = roomPanels(
        owner!,
        objectPlane(owner),
      ).firstWhere((p) => p.key == plane.roomFace);
      final cut = _inFrame(face.region, target.surface.frame, panel.frame);
      if (!panel.frame.region.containsRegion(cut) ||
          owner.openings.any(
            (o) => o.wall == panel.key && o.region.overlaps(cut),
          )) {
        return fail('Keep the cut within intact wall paper');
      }
      final remains = panel.regions.expand((r) => r.subtract(cut)).toList();
      if (remains.isEmpty) return fail('Keep part of the wall intact');
      for (final child in objects.values) {
        final p = objectPlane(child);
        if (p.roomId == owner.id &&
            p.roomFace == panel.key &&
            _inFrame(child.region, p, panel.frame).overlaps(cut)) {
          return fail('Remove attached objects before cutting');
        }
      }
      final b = cut.bounds, extent = panel.frame.region.bounds;
      final door = doorwayCenter(cut) != null;
      final enclosed =
          b.left > geometryEpsilon &&
          b.top > geometryEpsilon &&
          b.right < extent.right - geometryEpsilon &&
          b.bottom < extent.bottom - geometryEpsilon;
      object = owner.copyWith(
        openings: [
          ...owner.openings,
          RoomOpening(
            panel.key,
            cut,
            door
                ? 'door'
                : enclosed
                ? 'window'
                : 'opening',
          ),
        ],
      );
      return ConstructionEvaluation(
        tool,
        target,
        object: object,
        frame: objectPlane(owner),
        replacementId: owner.id,
        paper: selectedPaper,
      );
    }
    final material = tool == ConstructionTool.volume
        ? owner?.material
        : selectedPaper.material;
    if (material != null && !material.allows(target.context)) {
      return fail(
        material == PaperMaterial.paperWhite
            ? 'Building paper requires an outdoor surface'
            : 'Cloth requires an indoor surface',
      );
    }
    if (tool == ConstructionTool.volume) {
      if (owner == null || owner.kind != CraftKind.paperSheet) {
        return fail('Aim at a building mat or cloth sheet');
      }
      if (objects.values.any(
        (o) => o.id != owner.id && objectPlane(o).owner == owner.id,
      )) {
        return fail('Remove attached objects before inflating');
      }
      final cloth = owner.material == PaperMaterial.paperGreen;
      replacement = owner.id;
      frame = objectPlane(owner);
      target = ConstructionTarget(
        planeId,
        target.surface,
        point,
        _inFrame(owner.region, frame, target.surface.frame),
        target.spacing,
        context: target.context,
        roomId: target.roomId,
      );
      object = owner.copyWith(
        kind: cloth ? CraftKind.inflatedCloth : CraftKind.room,
        depth: cloth ? .05 : 1,
        drawingSpacing: .25,
      );
    } else {
      if (plane.owner == null &&
          drawingFaceAt(point, surface: target.surface) == null) {
        return fail('Draw a closed boundary before placing paper');
      }
      if (!drawingSupported(target.surface, target.region)) {
        return fail('The region needs intact support');
      }
      if (plane.owner == null && target.region.area < 1 - geometryEpsilon) {
        return fail('Draw a boundary of at least one tile');
      }
      final cost =
          (target.region.area * HousingBalance.unitsPerTile - geometryEpsilon)
              .ceil();
      if (balances[selectedPaper.material]! < cost) {
        return fail('Buy more ${selectedPaper.name} paper');
      }
      final basis = target.surface.frame;
      final frameId = 'sticker-frame-construction-$nextId';
      frame = CraftPlane(
        id: frameId,
        origin: basis.origin,
        u: basis.u,
        v: basis.v,
        region: target.region,
        owner: plane.owner,
        roomId: plane.roomId,
        roomFace: plane.roomFace,
        interior: plane.interior,
        grids: [lattice(frameId, target.region)],
      );
      object = CraftObject(
        id: 'object-$nextId',
        planeId: frameId,
        kind: CraftKind.paperSheet,
        region: target.region,
        depth: .01,
        material: selectedPaper.material,
        drawingSpacing: target.spacing,
      );
    }
    // Both new sheets and inflation must stay on owned, intact support.
    if (!drawingSupported(target.surface, target.region)) {
      return fail('The region needs intact support');
    }
    for (final old in objects.values) {
      if (old.id == replacement) continue;
      final occupied = object.kind == CraftKind.room
          ? object.copyWith(kind: CraftKind.solidVolume)
          : object;
      if (solidsOverlap(occupied, frame, old, objectPlane(old))) {
        return fail('Another object occupies this space');
      }
    }
    final staged = ProtoplaneController._constructionStage(this);
    try {
      staged.planes[frame.id] = frame;
      staged.objects[object.id] = object;
      if (replacement == null) staged.nextId++;
      staged._derivePlanes();
      staged._validateLoaded();
    } on FormatException catch (error) {
      return fail(error.message.toString());
    } finally {
      staged.dispose();
    }
    return ConstructionEvaluation(
      tool,
      target,
      object: object,
      frame: frame,
      replacementId: replacement,
      paper: selectedPaper,
    );
  }

  bool applyConstruction(ConstructionEvaluation evaluation) {
    final target = evaluation.target;
    if (target == null || !evaluation.valid) return false;
    final fresh = evaluateConstruction(
      evaluation.tool,
      target.planeId,
      target.point,
      paper: evaluation.paper,
    );
    if (!fresh.valid ||
        fresh.replacementId != evaluation.replacementId ||
        jsonEncode(fresh.target!.region.toJson()) !=
            jsonEncode(target.region.toJson()) ||
        jsonEncode(fresh.target!.surface.frame.toJson()) !=
            jsonEncode(target.surface.frame.toJson())) {
      report(fresh.issue ?? 'The target has changed');
      return false;
    }
    final before = _snapshot();
    planes[fresh.frame!.id] = fresh.frame!;
    objects[fresh.object!.id] = fresh.object!;
    if (fresh.replacementId == null) {
      nextId++;
      balances[fresh.paper.material] =
          balances[fresh.paper.material]! -
          (fresh.target!.region.area * HousingBalance.unitsPerTile -
                  geometryEpsilon)
              .ceil();
    }
    _derivePlanes();
    // Inflation keeps the sheet's identity and local drawing coordinates while
    // moving its exposed top surface. Attached objects are rejected above.
    if (fresh.replacementId != null) {
      for (final graph in drawingGraphs.values.toList()) {
        final newFrame =
            planes[graph.surfaceId] ??
            (fresh.object!.kind == CraftKind.room &&
                    graph.surfaceId == 'surface-${fresh.object!.id}'
                ? planes['surface-${fresh.object!.id}-roof-out-0']
                : null);
        if (newFrame?.owner == fresh.replacementId) {
          drawingGraphs.remove(graph.key);
          final moved = DrawingGraph(
            newFrame!.id,
            graph.implement,
            newFrame,
            graph.edges,
          );
          drawingGraphs[moved.key] = moved;
        }
      }
      drawingRevision++;
    }
    if (fresh.tool == ConstructionTool.scissors) {
      for (final graph in drawingGraphs.values.toList()) {
        if (graph.surfaceId == target.surface.id) {
          final cut = _inFrame(
            target.region,
            target.surface.frame,
            graph.frame,
          );
          final kept = graph.edges
              .where((e) => !cut.contains((e.a + e.b) / 2))
              .toList();
          drawingGraphs[graph.key] = DrawingGraph(
            graph.surfaceId,
            graph.implement,
            graph.frame,
            kept,
          );
        }
      }
      drawingRevision++;
    }
    syncHousing();
    error = null;
    _record(before, committed: true);
    _notifyPencil();
    return true;
  }

  void _deriveVolumeSides(CraftObject object, CraftPlane source) {
    for (final (ringIndex, raw) in object.region.rings.indexed) {
      final ring = simplifyRing(raw);
      final area = edges(
        ring,
      ).fold<double>(0, (sum, e) => sum + cross(e.$1, e.$2));
      // For the outside ring the normal points away from its interior; for a
      // hole it points into the opening. Frames keep the ring edge as their U axis.
      for (var i = 0; i < ring.length; i++) {
        final a = ring[i], b = ring[(i + 1) % ring.length];
        final along = (source.point(b) - source.point(a)).normalized();
        final sign = (area > 0 ? 1.0 : -1.0) * (ringIndex == 0 ? 1.0 : -1.0);
        final id = 'surface-${object.id}-side-$ringIndex-$i';
        final origin = source.point(a, sign > 0 ? 0 : object.depth);
        final region = rectangle((b - a).distance, object.depth);
        planes[id] = CraftPlane(
          id: id,
          origin: origin,
          u: along,
          v: source.normal * sign,
          region: region,
          owner: object.id,
          roomId: source.roomId,
          roomFace: source.roomFace,
          interior: source.interior,
          grids: [lattice(id, region)],
        );
      }
    }
  }
}
