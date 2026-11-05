part of 'controller.dart';

extension LinearCrafting on ProtoplaneController {
  bool isImpliedPlane(CraftPlane p) =>
      p.wallCandidate || p.id.startsWith('upper-');
  bool planeAvailable(CraftPlane p) =>
      !surfaceFusion.retired.contains(p.id) &&
      !p.id.startsWith('construction-') &&
      (impliedProtoplanes || !isImpliedPlane(p));

  void setImpliedProtoplanes(bool value) {
    if (impliedProtoplanes == value) return;
    impliedProtoplanes = value;
    _invalidateNavigation();
    final active = activePlane;
    if (active != null && !planeAvailable(active)) {
      final source =
          planes['surface-${active.owner}'] ??
          planes[objects[active.owner]?.planeId];
      if (source != null && planeAvailable(source)) {
        enter(surfaceFusion.canonical[source.id] ?? source.id);
      } else {
        leave();
      }
    }
    _notifyPencil();
  }

  CraftPlane? get linearSource =>
      landscapePaperPlanes.firstOrNull ?? activePlane;
  bool get linearPlacement =>
      tool == CraftTool.place &&
      editId == null &&
      !closed &&
      trace.length >= 2 &&
      linearSource != null &&
      (supportKind(linearSource!) == CraftKind.floor ||
          supportKind(linearSource!) == CraftKind.wall);

  CraftPlane objectPlane(CraftObject object) {
    final attachment = object.linear;
    if (attachment != null) {
      final source = planes[attachment.sourcePlaneId];
      if (source != null) return attachment.frame(object.planeId, source);
    }
    return planes[object.planeId]!;
  }

  List<CraftObject> get linearPreviewObjects {
    if (!linearPlacement) return [];
    final source = linearSource!;
    final wall = supportKind(source) == CraftKind.wall;
    final supports = isLandscapePaper(source.id)
        ? <String>[]
        : paperMembers(source);
    // A constituent's surface keeps its basis even while its visible union grows.
    final anchor = supports.isEmpty
        ? source
        : planes['surface-${supports.first}'] ?? source;
    final points = <Offset>[];
    for (final point in trace) {
      while (points.length >= 2 &&
          onSegment(points.last, points[points.length - 2], point)) {
        points.removeLast();
      }
      points.add(point);
    }
    final result = <CraftObject>[];
    for (var i = 1; i < points.length; i++) {
      var a = anchor.local(source.point(points[i - 1]));
      var b = anchor.local(source.point(points[i]));
      if (a.dx > b.dx + geometryEpsilon ||
          ((a.dx - b.dx).abs() < geometryEpsilon && a.dy > b.dy)) {
        final old = a;
        a = b;
        b = old;
      }
      final length = (b - a).distance;
      if (length < geometryEpsilon) continue;
      final attachment = LinearAttachment(
        sourcePlaneId: anchor.id,
        a: a,
        b: b,
        supports: supports,
        side: wall ? placementSide : (source.normal.y < 0 ? -1 : 1),
      );
      result.add(
        CraftObject(
          id: 'preview-linear-$i',
          planeId: 'construction-preview-$i',
          kind: wall ? CraftKind.floor : CraftKind.wall,
          material: paper,
          region: rectangle(length, 1),
          depth: wall ? 0 : recipes[CraftKind.wall]!.defaultDepth,
          linear: attachment,
        ),
      );
    }
    return result;
  }

  bool _harvestBlocked(HarvestResult result) {
    if (objects.values.any(
      (o) => o.planeId == result.planeId && o.region.overlaps(result.outline),
    )) {
      return true;
    }
    for (final object in objects.values) {
      final attachment = object.linear;
      if (attachment == null || attachment.sourcePlaneId != result.planeId) {
        continue;
      }
      final source = planes[result.planeId]!;
      final remaining = surfaceRegions(
        source,
      ).expand((r) => r.subtract(result.outline));
      final edge = PencilSegment(attachment.a, attachment.b);
      final covered = newPencilCoverage([
        for (final r in remaining) ...clipPencil([edge], r),
      ], const []);
      if (covered.fold<double>(0, (n, s) => n + s.length) <
          edge.length - geometryEpsilon) {
        return true;
      }
    }
    return false;
  }

  String? _attachmentError(CraftObject object) {
    final a = object.linear;
    if (a == null) return null;
    final source = planes[a.sourcePlaneId];
    if (source == null || a.supports.any((id) => !objects.containsKey(id))) {
      return 'Missing support plane';
    }
    final edge = PencilSegment(a.a, a.b);
    final material = isLandscapePaper(source.id)
        ? surfaceRegions(source)
        : a.supports.isEmpty
        ? [source.region]
        : [
            for (final id in a.supports)
              Region(
                objects[id]!.region.outer
                    .map(
                      (p) => source.local(
                        objectPlane(
                          objects[id]!,
                        ).point(p, objects[id]!.depth + .002),
                      ),
                    )
                    .toList(),
                objects[id]!.region.holes
                    .map(
                      (ring) => ring
                          .map(
                            (p) => source.local(
                              objectPlane(
                                objects[id]!,
                              ).point(p, objects[id]!.depth + .002),
                            ),
                          )
                          .toList(),
                    )
                    .toList(),
              ),
          ];
    final covered = newPencilCoverage([
      for (final r in material) ...clipPencil([edge], r),
    ], const []);
    if (covered.fold<double>(0, (n, s) => n + s.length) <
        edge.length - geometryEpsilon) {
      return 'Attachment needs paper along its entire edge';
    }
    final worldEdge = source.point(a.b) - source.point(a.a);
    if (object.kind == CraftKind.floor &&
        math.sqrt(worldEdge.x * worldEdge.x + worldEdge.z * worldEdge.z) <
            geometryEpsilon) {
      return 'Draw a horizontal or sloped floor edge';
    }
    return null;
  }

  bool _sharedSheetEdge(CraftObject a, CraftObject b) {
    final ap = objectPlane(a), bp = objectPlane(b);
    if (ap.normal.dot(bp.normal).abs() > 1 - geometryEpsilon &&
        (ap.origin - bp.origin).dot(ap.normal).abs() < geometryEpsilon) {
      final mapped = Region(
        b.region.outer.map((p) => ap.local(bp.point(p))).toList(),
      );
      if (a.region.overlaps(mapped)) return false;
    }
    for (final ae in edges(a.region.outer)) {
      for (final be in edges(b.region.outer)) {
        final a0 = ap.point(ae.$1), a1 = ap.point(ae.$2);
        final b0 = bp.point(be.$1), b1 = bp.point(be.$2);
        if ((a0.distanceTo(b0) < geometryEpsilon &&
                a1.distanceTo(b1) < geometryEpsilon) ||
            (a0.distanceTo(b1) < geometryEpsilon &&
                a1.distanceTo(b0) < geometryEpsilon)) {
          return true;
        }
      }
    }
    return false;
  }

  String? _linearError(List<CraftObject> parts) {
    if (parts.isEmpty) return 'Complete a drawing';
    for (var i = 0; i < parts.length; i++) {
      final error = validateObject(parts[i]);
      if (error != null) return error;
      for (final other in parts.take(i)) {
        if (!_sharedSheetEdge(parts[i], other) &&
            solidsOverlap(
              parts[i],
              objectPlane(parts[i]),
              other,
              objectPlane(other),
            )) {
          return 'Intersects another sheet';
        }
      }
    }
    return null;
  }

  bool _createLinear() {
    final parts = linearPreviewObjects;
    final error = _linearError(parts);
    final cost = quote;
    if (error != null || balances[paper]! < cost) {
      report(error ?? 'Not enough ${paper.label} paper');
      return false;
    }
    final before = _gestureBefore ?? _snapshot(), key = draftKey;
    for (final part in parts) {
      final id = 'object-${nextId++}';
      objects[id] = part.copyWith(id: id, planeId: 'construction-$id');
    }
    balances[paper] = balances[paper]! - cost;
    drafts.remove(key);
    _derivePlanes();
    _gestureBefore = null;
    _record(before, committed: true);
    _notifyPencil();
    return true;
  }

  bool _applyFusedCut() {
    final before = _gestureBefore ?? _snapshot();
    final cuts = cutObjects!, frame = activePlane!;
    final members = List<String>.of(editingMembers), key = draftKey;
    for (final id in members) {
      final object = objects[id]!, source = objectPlane(objects[id]!);
      final retained = object.region.clipTo([
        for (final cut in cuts)
          Region(
            cut.region.outer.map((p) => source.local(frame.point(p))).toList(),
            cut.region.holes
                .map(
                  (ring) =>
                      ring.map((p) => source.local(frame.point(p))).toList(),
                )
                .toList(),
          ),
      ]);
      final marks = pencilMarks.remove(id) ?? <PencilStroke>[];
      if (retained.isEmpty) {
        objects.remove(id);
        continue;
      }
      for (var i = 0; i < retained.length; i++) {
        final pieceId = i == 0 ? id : 'object-${nextId++}';
        objects[pieceId] = object.copyWith(
          id: pieceId,
          region: retained[i],
          planeId: object.linear == null || i == 0
              ? null
              : 'construction-$pieceId',
        );
        pencilMarks[pieceId] = _clipStrokes(marks, retained[i]);
      }
    }
    drafts.remove(key);
    _gestureBefore = null;
    _derivePlanes();
    _record(before, committed: true);
    _notifyPencil();
    return true;
  }

  bool resizeLinear(String id, {double? extent, bool flip = false}) {
    final ids = surfaceFusion.members['surface-$id'] ?? [id];
    final replacements = <CraftObject>[];
    var addedArea = 0.0;
    for (final member in ids) {
      final original = objects[member], attachment = objects[member]?.linear;
      if (original == null || attachment == null) return false;
      if (_hasDependents(member)) {
        report('Attached objects need this support');
        return false;
      }
      final value = extent ?? attachment.extent;
      if (!value.isFinite ||
          value < .25 ||
          (value * 4 - (value * 4).round()).abs() > geometryEpsilon) {
        return false;
      }
      if ((original.region.area -
                  (attachment.b - attachment.a).distance * attachment.extent)
              .abs() >
          geometryEpsilon) {
        report('Resize before cutting this surface');
        return false;
      }
      final next = original.copyWith(
        linear: attachment.copyWith(
          extent: value,
          side: flip ? -attachment.side : attachment.side,
        ),
        region: rectangle((attachment.b - attachment.a).distance, value),
      );
      final message = validateObject(next, replacing: member);
      if (message != null) {
        report(message);
        return false;
      }
      addedArea += math.max(0, next.materialArea - original.materialArea);
      replacements.add(next);
    }
    final material = replacements.first.material;
    final cost = (addedArea * 128 - 1e-8).ceil();
    if (balances[material]! < cost) {
      report('Not enough paper');
      return false;
    }
    final before = _snapshot();
    for (final next in replacements) {
      objects[next.id] = next;
    }
    balances[material] = balances[material]! - cost;
    _derivePlanes();
    _record(before, committed: true);
    _notifyPencil();
    return true;
  }
}
