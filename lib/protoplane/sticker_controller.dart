part of 'controller.dart';

extension StickerCrafting on ProtoplaneController {
  ProgramEvaluation evaluateSticker(
    StickerKind kind,
    Offset drop, {
    String? targetPlaneId,
  }) {
    final target = targetPlaneId ?? activePlaneId;
    final surface = drawingSurfaceFor(target);
    final face = surface == null ? null : drawingFaceAt(drop, surface: surface);
    ProgramEvaluation fail(String issue) => ProgramEvaluation(
      kind,
      surface?.id ?? '',
      face?.graph.key ?? '',
      face?.id ?? '',
      drop,
      targetPlaneId: target,
      issue: issue,
      region: face?.region,
    );
    if (surface == null || face == null) {
      return fail('Aim inside a drawn closed region');
    }
    if (!drawingSupported(surface, face.region)) {
      return fail('The region needs intact support');
    }
    final staged = ProtoplaneController().._load(toJson());
    try {
      final program = staged._buildSticker(kind, surface, face);
      final generated = program.operations
          .whereType<CreateStickerPanel>()
          .toList();
      final owners = {
        for (final id in surface.sources)
          if (planes[id]?.owner != null) planes[id]!.owner!,
      };
      for (final panel in generated) {
        for (final old in objects.values) {
          if (owners.contains(old.id)) continue;
          if (solidsOverlap(panel.object, panel.frame, old, objectPlane(old))) {
            return fail('Another object occupies this space');
          }
        }
      }
      for (final op in program.operations) {
        if (op is CreateStickerPanel) {
          staged.planes[op.frame.id] = op.frame;
          staged.objects[op.object.id] = op.object;
        } else if (op is CutStickerOpening) {
          final old = staged.objects[op.objectId]!;
          for (final dependent in staged.objects.values) {
            final basis = staged.objectPlane(dependent);
            if (basis.owner != old.id && !basis.supports.contains(old.id)) {
              continue;
            }
            final wallFrame = staged.objectPlane(old);
            if (basis.normal.dot(wallFrame.normal).abs() < .999 ||
                staged
                    ._inFrame(dependent.region, basis, wallFrame)
                    .overlaps(op.region)) {
              return fail('Attached objects need this wall');
            }
          }
          final remaining = old.region.subtract(op.region);
          if (remaining.length != 1 || !remaining.single.valid) {
            return fail('Opening must leave one connected wall');
          }
          staged.objects[old.id] = old.copyWith(region: remaining.single);
        }
      }
      final assemblyId = 'assembly-${staged.nextId++}';
      staged.assemblies[assemblyId] = ProgramAssembly(
        assemblyId,
        kind,
        surface.frame,
        face.region,
        {
          for (final p in generated) p.component: p.object.id,
          for (final cut in program.operations.whereType<CutStickerOpening>())
            'opening': cut.objectId,
        },
        surface.sources,
        face.graph.key,
        face.id,
        {
          if (kind == StickerKind.house) 'height': 1,
          if (kind == StickerKind.hill) 'stepHeight': .25,
        },
      );
      staged._derivePlanes();
      staged._validateLoaded();
      final quote =
          (generated.fold<double>(0, (n, p) => n + p.object.materialArea) * 128)
              .ceil();
      return ProgramEvaluation(
        kind,
        surface.id,
        face.graph.key,
        face.id,
        drop,
        targetPlaneId: target,
        world: staged.toJson(),
        program: program,
        objects: [for (final p in generated) p.object],
        frames: {for (final p in generated) p.frame.id: p.frame},
        region: face.region,
        quote: quote,
      );
    } on FormatException catch (e) {
      return fail(e.message.toString());
    } finally {
      staged.dispose();
    }
  }

  bool applySticker(ProgramEvaluation evaluation) {
    final surface = drawingSurfaceFor(
      evaluation.targetPlaneId ?? activePlaneId,
    );
    final face = surface == null
        ? null
        : drawingFaceAt(evaluation.drop, surface: surface);
    if (surface?.id != evaluation.surfaceId ||
        face?.graph.key != evaluation.graphKey ||
        face?.id != evaluation.faceId) {
      report('The target has changed');
      return false;
    }
    final fresh = evaluateSticker(
      evaluation.kind,
      evaluation.drop,
      targetPlaneId: evaluation.targetPlaneId,
    );
    if (!fresh.valid) {
      report(fresh.issue!);
      return false;
    }
    final before = _snapshot(), active = activePlaneId;
    _load(fresh.world!);
    activePlaneId = planes.containsKey(active) ? active : null;
    error = null;
    _record(before, committed: true);
    _notifyPencil();
    return true;
  }

  StickerProgram _buildSticker(
    StickerKind kind,
    DrawingSurface surface,
    DrawingFace face,
  ) {
    final frame = surface.frame,
        region = face.region,
        implement = face.graph.implement;
    final oriented = Region(
      region.outer.map(implement.toLattice).toList(),
      region.holes.map((h) => h.map(implement.toLattice).toList()).toList(),
    );
    final box = oriented.bounds;
    final definition = stickerDefinitions[kind.index];
    final short = math.min(box.width, box.height),
        long = math.max(box.width, box.height);
    final rectangular =
        region.holes.isEmpty &&
        (oriented.area - box.width * box.height).abs() < 1e-6;
    final horizontal = frame.normal.y.abs() > .999;
    if ([StickerKind.house, StickerKind.hill, StickerKind.bed].contains(kind) &&
        !horizontal) {
      throw const FormatException('Needs a horizontal surface');
    }
    final ops = <StickerOperation>[];
    CraftObject panel(
      String component,
      CraftKind type,
      Region shape,
      CraftPlane basis,
      double depth, {
      String? owner,
    }) {
      final id = 'object-${nextId++}';
      final p = CraftPlane(
        id: 'sticker-frame-$id',
        origin: basis.origin,
        u: basis.u,
        v: basis.v,
        region: shape,
        owner: owner,
        grids: [lattice('sticker-grid-$id', shape, count: 2)],
      );
      final object = CraftObject(
        id: id,
        planeId: p.id,
        kind: type,
        region: shape,
        color: PaperMaterial.paperWhite,
        depth: depth,
      );
      ops.add(CreateStickerPanel(component, object, p));
      return object;
    }

    CraftPlane elevated(double height) => CraftPlane(
      id: 'basis',
      origin: frame.origin + frame.normal * height,
      u: frame.u,
      v: frame.v,
      region: region,
      grids: const [],
    );
    Region mappedRect(Rect rect) => Region(
      [
        rect.topLeft,
        rect.topRight,
        rect.bottomRight,
        rect.bottomLeft,
      ].map(implement.toSurface).toList(),
    );
    if (kind == StickerKind.house) {
      if (!surface.id.startsWith('terrain-')) {
        throw const FormatException('House needs ground');
      }
      if (box.width < 1 - 1e-6 || box.height < 1 - 1e-6) {
        throw const FormatException(
          'House footprint must be at least 1 × 1 tiles',
        );
      }
      if (box.width > definition.maximumWidth + 1e-6 ||
          box.height > definition.maximumHeight + 1e-6) {
        throw const FormatException('House footprint exceeds 8 × 8 tiles');
      }
      final floor = panel(
        'floor',
        CraftKind.floor,
        region,
        elevated(.002),
        .02,
      );
      var i = 0;
      for (final ring in region.rings) {
        for (final (a, b) in edges(simplifyRing(ring))) {
          final u = (frame.point(b) - frame.point(a)).normalized();
          final r = rectangle((b - a).distance, 1);
          panel(
            'wall-${i++}',
            CraftKind.wall,
            r,
            CraftPlane(
              id: 'wall',
              origin: frame.point(a, .022),
              u: u,
              v: frame.normal,
              region: r,
              grids: const [],
            ),
            .02,
            owner: floor.id,
          );
        }
      }
    } else if (kind == StickerKind.hill) {
      if (box.width > 4 + 1e-6 || box.height > 4 + 1e-6) {
        throw const FormatException('Hill footprint exceeds 4 × 4 tiles');
      }
      var tiers = [region];
      String? owner;
      var count = 0;
      for (var level = 0; level < 3 && tiers.isNotEmpty; level++) {
        final next = <Region>[];
        for (final (i, r) in tiers.indexed) {
          final o = panel(
            'tier-$level-$i',
            CraftKind.floor,
            r,
            elevated(.002 + level * .25),
            .25,
            owner: owner,
          );
          if (level == 0) owner = o.id;
          next.addAll(insetProgramRegion(r, .25));
        }
        count++;
        tiers = next;
      }
      if (count < 2) {
        throw const FormatException('Hill needs room for at least two tiers');
      }
    } else if (kind == StickerKind.bed) {
      if (!rectangular ||
          short < .5 - 1e-6 ||
          long < 1 - 1e-6 ||
          short > 1 + 1e-6 ||
          long > 2 + 1e-6) {
        throw const FormatException('Bed needs a rectangle .5–1 by 1–2 tiles');
      }
      final bed = panel(
        'frame',
        CraftKind.bedFrame,
        region,
        elevated(.002),
        .08,
        owner: frame.owner,
      );
      final mattressRegion = mappedRect(box.deflate(.025));
      final mattress = panel(
        'mattress',
        CraftKind.mattress,
        mattressRegion,
        elevated(.084),
        .035,
        owner: bed.id,
      );
      final alongY = box.height >= box.width;
      final inner = box.deflate(.05);
      final pillow = alongY
          ? Rect.fromLTWH(inner.left, inner.top, inner.width, .2)
          : Rect.fromLTWH(inner.left, inner.top, .2, inner.height);
      final blanket = alongY
          ? Rect.fromLTRB(inner.left, inner.top + .3, inner.right, inner.bottom)
          : Rect.fromLTRB(
              inner.left + .3,
              inner.top,
              inner.right,
              inner.bottom,
            );
      panel(
        'pillow',
        CraftKind.pillow,
        mappedRect(pillow),
        elevated(.121),
        .025,
        owner: mattress.id,
      );
      panel(
        'blanket',
        CraftKind.blanket,
        mappedRect(blanket),
        elevated(.121),
        .008,
        owner: mattress.id,
      );
    } else {
      final wall = objects[frame.owner];
      if (horizontal || wall?.kind != CraftKind.wall) {
        throw const FormatException('Opening needs a wall');
      }
      final local = _inFrame(region, frame, objectPlane(wall!));
      final b = local.bounds;
      if (local.holes.isNotEmpty ||
          (local.area - b.width * b.height).abs() > 1e-6) {
        throw const FormatException('Opening must be an upright rectangle');
      }
      if (b.width < .25 - 1e-6 ||
          b.height < (kind == StickerKind.door ? .5 : .25) - 1e-6 ||
          b.width > definition.maximumWidth + 1e-6 ||
          b.height > definition.maximumHeight + 1e-6) {
        throw FormatException('${definition.name} exceeds its size limits');
      }
      if (!wall.region.containsRegion(local)) {
        throw const FormatException('Opening must lie inside intact wall');
      }
      if (kind == StickerKind.door) {
        if ((b.top - wall.region.bounds.top).abs() > 1e-6) {
          throw const FormatException('Door must touch the bottom of the wall');
        }
      } else {
        if (local.outer.any(
          (p) => wall.region.rings.any(
            (r) => edges(r).any((e) => onSegment(p, e.$1, e.$2)),
          ),
        )) {
          throw const FormatException('Window needs wall around every side');
        }
      }
      ops.add(CutStickerOpening(wall.id, local));
      if (kind == StickerKind.window) {
        final inner = rectangle(
          b.width - .04,
          b.height - .04,
          origin: b.topLeft + const Offset(.02, .02),
        );
        final rim = local.subtract(inner).single;
        panel('frame', CraftKind.window, rim, frame, .015, owner: wall.id);
      }
    }
    return StickerProgram(kind, ops);
  }
}
