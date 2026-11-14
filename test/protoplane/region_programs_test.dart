import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/protoplane/models.dart';
import 'package:flatmates/protoplane/geometry.dart';
import 'package:flatmates/protoplane/dev_settings.dart';

void main() {
  test(
    'L-shaped house uses the largest supported rectangle and deterministic ties',
    () {
      final c = ProtoplaneController(unlimitedPaper: true);
      addTearDown(c.dispose);
      final p = c.planes['ground-starter-paperWhite-0-0']!,
          s = c.regionSurface('ground-starter-paperWhite-0-0')!;
      final l = Region([
        Offset.zero,
        const Offset(2, 0),
        const Offset(2, 1),
        const Offset(1, 1),
        const Offset(1, 2),
        const Offset(0, 2),
      ]);
      final r = LightRegion('l', s.id, mapRegion(l, p, s.frame));
      c.workspace.regions[r.id] = r;
      final plan = c.evaluateProgram(
        ProgramKind.house,
        r,
        s,
        s.frame.local(p.point(const Offset(.5, 1.5))),
      );
      expect(plan.issue, isNull);
      expect(plan.objects, hasLength(6));
      final floor = plan.objects.firstWhere((o) => o.kind == CraftKind.floor);
      expect(floor.region.area, closeTo(2, 1e-6));
      expect(floor.region.bounds.width, 1);
      expect(floor.region.bounds.height, 2);
      final tie = c.evaluateProgram(
        ProgramKind.house,
        r,
        s,
        s.frame.local(p.point(const Offset(.5, .5))),
      );
      expect(tie.objects.first.region.bounds.width, 2);
      expect(tie.objects.first.region.bounds.height, 1);
      expect(c.applyProgram(plan), isTrue);
      expect(c.workspace.regions, isEmpty);
    },
  );

  test('Light pencil, Cut and Place share configured diagonal connections', () {
    final c = ProtoplaneController();
    addTearDown(c.dispose);
    c.enter('ground-starter-paperWhite-0-0');
    c.setProtoplaneConnections(GridConnections.diagonal);
    final p = c.activePlane!,
        s = RegionSurface(c.activePlane!, [c.activePlane!.id]);
    final light = c.drawingGrid(s);
    bool connected(CraftGrid g) =>
        g.connection(
          g.nodes.indexOf(Offset.zero),
          g.nodes.indexOf(const Offset(.5, .5)),
        ) !=
        null;
    expect(connected(light), isTrue);
    for (final tool in [CraftTool.scissors, CraftTool.place]) {
      c.selectTool(tool);
      expect(connected(c.grid!), isTrue);
    }
    expect(p.id, s.id);
  });
  test(
    'world open Place keeps regions and creates resizable saved attachments',
    () {
      final c = ProtoplaneController(unlimitedPaper: true);
      addTearDown(c.dispose);
      final p = c.planes['ground-starter-paperWhite-0-0']!,
          s = c.regionSurface('ground-starter-paperWhite-0-0')!;
      Offset mapped(Offset v) => s.frame.local(p.point(v));
      c.drawLightPath(
        s,
        [
          const Offset(0, 0),
          const Offset(1, 0),
          const Offset(1, 1),
          const Offset(0, 1),
          const Offset(0, 0),
        ].map(mapped).toList(),
      );
      final regions = c.workspace.toJson().toString();
      expect(
        c.commitRegionPath(
          s,
          [const Offset(0, .5), const Offset(1, .5)].map(mapped).toList(),
          place: true,
        ),
        isTrue,
      );
      expect(c.workspace.toJson().toString(), regions);
      final object = c.objects.values.single;
      expect(object.linear, isNotNull);
      expect(c.resizeLinear(object.id, extent: 1.5), isTrue);
      expect(c.objects[object.id]!.linear!.extent, 1.5);
      final loaded = ProtoplaneController()..load(c.toJson());
      addTearDown(loaded.dispose);
      expect(loaded.objects[object.id]!.linear!.extent, 1.5);
      c.undo();
      c.undo();
      expect(c.objects, isEmpty);
      expect(c.workspace.toJson().toString(), regions);
    },
  );
  test(
    'full boundary loops, repeated edges, shared seams and cross-plane merge',
    () {
      final c = ProtoplaneController();
      addTearDown(c.dispose);
      final p = c.planes['ground-starter-paperWhite-0-0']!, w = c.workspace;
      w.surfaces[p.id] = RegionSurface(p, [p.id]);
      final loop = [...p.region.outer, p.region.outer.first];
      expect(w.draw(p.id, loop), isTrue);
      expect(w.regions, hasLength(1));
      expect(w.draw(p.id, loop), isFalse);
      expect(w.regions, hasLength(1));
      w.draw(p.id, [const Offset(0, .5), const Offset(1, .5)]);
      w.draw(p.id, [const Offset(.5, 0), const Offset(.5, 1)]);
      expect(w.regions, hasLength(4));
      final chosen = w.at(p.id, const Offset(.25, .25))!;
      expect(
        w.combine(chosen, LightRegion('other', 'other-plane', chosen.geometry)),
        isFalse,
      );
      w.consume(chosen);
      expect(w.regions, hasLength(3));
      expect(w.lines[p.id]!.any((s) => s.a.dx == .5 && s.b.dx == .5), isTrue);
      expect(w.at(p.id, const Offset(.25, .25))!.implied, isTrue);
    },
  );

  test(
    'loops, subdivisions, consume and history preserve disjoint regions',
    () {
      final c = ProtoplaneController(unlimitedPaper: true);
      addTearDown(c.dispose);
      final p = c.planes['ground-starter-paperWhite-0-0']!;
      final s = RegionSurface(p, [p.id]);
      c.workspace.surfaces[s.id] = s;
      c.drawLightPath(s, [
        const Offset(.25, .25),
        const Offset(.75, .25),
        const Offset(.75, .75),
        const Offset(.25, .75),
        const Offset(.25, .25),
      ]);
      expect(c.workspace.regions, hasLength(1));
      expect(
        c.workspace.regions.values.fold<double>(
          0,
          (v, r) => v + r.geometry.area,
        ),
        closeTo(.25, 1e-6),
      );
      final inside = c.workspace.at(s.id, const Offset(.5, .5))!;
      expect(inside.geometry.area, closeTo(.25, 1e-6));
      c.drawLightPath(s, [const Offset(0, .5), const Offset(1, .5)]);
      expect(c.workspace.regions.length, greaterThan(2));
      c.undo();
      expect(c.workspace.regions, hasLength(1));
      c.redo();
      expect(c.workspace.regions.length, greaterThan(2));
      expect(c.toJson().containsKey('regions'), isFalse);
    },
  );
  test('partial strokes close a loop, combine refuses corner contacts', () {
    final c = ProtoplaneController(unlimitedPaper: true);
    addTearDown(c.dispose);
    final p = c.planes['ground-starter-paperWhite-0-0']!, w = c.workspace;
    w.surfaces[p.id] = RegionSurface(p, [p.id]);
    w.draw(p.id, [
      const Offset(.25, .25),
      const Offset(.75, .25),
      const Offset(.75, .75),
    ]);
    expect(w.regions, isEmpty);
    w.draw(p.id, [
      const Offset(.75, .75),
      const Offset(.25, .75),
      const Offset(.25, .25),
    ]);
    expect(w.regions, hasLength(1));
    final parts = [w.regions.values.single, w.at(p.id, const Offset(.1, .1))!];
    expect(w.combine(parts[0], parts[1]), isTrue);
    expect(w.regions, hasLength(1));
    expect(
      sharedRegionEdge(
        rectangle(1, 1),
        rectangle(1, 1, origin: const Offset(1, 1)),
      ),
      isFalse,
    );
  });
  test(
    'largest rectangle respects L shape, holes and exact one-tile minimum',
    () {
      final l = Region([
        Offset.zero,
        const Offset(2, 0),
        const Offset(2, 1),
        const Offset(1, 1),
        const Offset(1, 2),
        const Offset(0, 2),
      ]);
      final r = largestRegionRectangle(
        l,
        spacing: .5,
        minimum: 1,
        nearPoint: const Offset(1.5, .5),
      )!;
      expect(r, const Rect.fromLTWH(0, 0, 2, 1));
      expect(
        largestRegionRectangle(
          rectangle(.99, 1),
          spacing: .5,
          minimum: 1,
          nearPoint: Offset.zero,
        ),
        isNull,
      );
      final hole = Region(rectangle(2, 2).outer, [
        rectangle(.5, .5, origin: const Offset(.75, .75)).outer,
      ]);
      final fitted = largestRegionRectangle(
        hole,
        spacing: .25,
        minimum: .25,
        nearPoint: Offset.zero,
      )!;
      expect(
        hole.containsRegion(
          rectangle(fitted.width, fitted.height, origin: fitted.topLeft),
        ),
        isTrue,
      );
    },
  );
  test('house is staged, atomic, editable, saved and undoable', () {
    final c = ProtoplaneController(unlimitedPaper: true);
    addTearDown(c.dispose);
    final p = c.planes['ground-starter-paperWhite-0-0']!;
    final s = RegionSurface(p, [p.id]),
        target = LightRegion('a', p.id, p.region);
    c.workspace.surfaces[p.id] = s;
    c.workspace.regions[target.id] = target;
    final before = c.toJson().toString(),
        balance = c.balances[PaperMaterial.paperWhite];
    final plan = c.evaluateProgram(
      ProgramKind.house,
      target,
      s,
      const Offset(.5, 0),
    );
    expect(plan.issue, isNull);
    expect(plan.objects, hasLength(6));
    expect(c.toJson().toString(), before);
    expect(c.applyProgram(plan), isTrue);
    expect(c.objects, hasLength(6));
    expect(c.workspace.regions, isEmpty);
    expect(c.balances[PaperMaterial.paperWhite], balance);
    final restored = ProtoplaneController()..load(c.toJson());
    addTearDown(restored.dispose);
    expect(restored.assemblies, hasLength(1));
    expect(restored.workspace.regions, isEmpty);
    c.undo();
    expect(c.objects, isEmpty);
    expect(c.workspace.regions, hasLength(1));
    c.redo();
    expect(c.objects, hasLength(6));
    expect(c.workspace.regions, isEmpty);
  });
  test(
    'invalid and unaffordable drops change nothing; pool excavates all layers',
    () {
      final c = ProtoplaneController(unlimitedPaper: false);
      addTearDown(c.dispose);
      final p = c.planes['ground-starter-paperWhite-0-0']!,
          s = RegionSurface(c.planes['ground-starter-paperWhite-0-0']!, [
            'ground-starter-paperWhite-0-0',
          ]);
      c.workspace.surfaces[p.id] = s;
      final target = LightRegion('a', p.id, p.region);
      c.workspace.regions['a'] = target;
      final before = c.toJson().toString();
      final expensive = c.evaluateProgram(
        ProgramKind.house,
        target,
        s,
        Offset.zero,
      );
      expect(expensive.issue, ProgramIssue.paper);
      expect(c.applyProgram(expensive), isFalse);
      expect(c.toJson().toString(), before);
      expect(c.workspace.regions, hasLength(1));
      c.unlimitedPaper = true;
      final pool = c.evaluateProgram(ProgramKind.pool, target, s, Offset.zero);
      expect(pool.issue, isNull);
      expect(pool.water, isNotNull);
      expect(pool.water!.area, lessThan(1));
      expect(c.applyProgram(pool), isTrue);
      expect(
        c.landscape.terrain.sheets.take(3).every((s) => s.cuts.isNotEmpty),
        isTrue,
      );
    },
  );

  test(
    'concave pool preserves its island and drains when its lining is edited',
    () {
      final c = ProtoplaneController(unlimitedPaper: true);
      addTearDown(c.dispose);
      final p = c.planes['ground-starter-paperWhite-0-0']!;
      final outline = Region(
        [
          Offset.zero,
          const Offset(1, 0),
          const Offset(1, .5),
          const Offset(.75, .5),
          const Offset(.75, 1),
          const Offset(0, 1),
        ],
        [rectangle(.2, .2, origin: const Offset(.2, .2)).outer],
      );
      final s = RegionSurface(p, [p.id]);
      final r = LightRegion('pool', p.id, outline);
      c.workspace.surfaces[s.id] = s;
      c.workspace.regions[r.id] = r;
      final plan = c.evaluateProgram(
        ProgramKind.pool,
        r,
        s,
        const Offset(.6, .2),
      );
      expect(plan.issue, isNull);
      expect(plan.water!.holes, hasLength(1));
      expect(c.applyProgram(plan), isTrue);
      final assembly = c.assemblies.values.single;
      expect(c.poolWater(assembly), isNotNull);
      expect(
        c.landscape.terrain
            .remainingInTile(p.id)
            .any((r) => r.contains(const Offset(.3, .3))),
        isTrue,
      );
      final liner = c.objects[assembly.components['lining-0']]!;
      c.objects[liner.id] = liner.copyWith(depth: .1);
      expect(c.poolWater(assembly), isNull);
    },
  );

  test(
    'narrow lining collapse and unsupported house preserve the workspace',
    () {
      final c = ProtoplaneController(unlimitedPaper: true);
      addTearDown(c.dispose);
      final p = c.planes['ground-starter-paperWhite-0-0']!;
      final s = RegionSurface(p, [p.id]);
      final outline = Region([
        Offset.zero,
        const Offset(.4, 0),
        const Offset(.4, .485),
        const Offset(.6, .485),
        const Offset(.6, 0),
        const Offset(1, 0),
        const Offset(1, 1),
        const Offset(.6, 1),
        const Offset(.6, .515),
        const Offset(.4, .515),
        const Offset(.4, 1),
        const Offset(0, 1),
      ]);
      final r = LightRegion('narrow', p.id, outline);
      c.workspace.surfaces[s.id] = s;
      c.workspace.regions[r.id] = r;
      final before = c.toJson().toString();
      expect(
        c.evaluateProgram(ProgramKind.pool, r, s, Offset.zero).issue,
        ProgramIssue.outline,
      );
      expect(c.toJson().toString(), before);
      c.landscape.deplete(p.id, rectangle(.5, 1));
      final full = LightRegion('full', p.id, p.region);
      c.workspace.regions[full.id] = full;
      expect(
        c.evaluateProgram(ProgramKind.house, full, s, Offset.zero).valid,
        isFalse,
      );
      expect(c.workspace.regions, hasLength(2));
    },
  );

  test(
    'table, rug and frame create ordinary geometry with orientation checks',
    () {
      for (final kind in [
        ProgramKind.table,
        ProgramKind.rug,
        ProgramKind.pictureFrame,
      ]) {
        final c = ProtoplaneController(unlimitedPaper: true);
        addTearDown(c.dispose);
        var p = c.planes['ground-starter-paperWhite-0-0']!;
        var s = RegionSurface(p, [p.id]);
        var r = LightRegion('target', s.id, p.region);
        c.workspace.surfaces[s.id] = s;
        c.workspace.regions[r.id] = r;
        if (kind == ProgramKind.pictureFrame) {
          c.protoplaneCells = 4;
          expect(
            c.evaluateProgram(kind, r, s, Offset.zero).issue,
            ProgramIssue.orientation,
          );
          expect(
            c.applyProgram(
              c.evaluateProgram(ProgramKind.house, r, s, Offset.zero),
            ),
            isTrue,
          );
          final wall = c.assemblies.values.single.components['wall-2']!;
          p = c.planes['surface-$wall']!;
          s = RegionSurface(p, [p.id]);
          r = LightRegion(
            'frame',
            s.id,
            rectangle(.5, .5, origin: const Offset(.25, .25)),
          );
          c.workspace.surfaces[s.id] = s;
          c.workspace.regions[r.id] = r;
        }
        final plan = c.evaluateProgram(kind, r, s, r.geometry.bounds.center);
        expect(plan.issue, isNull, reason: kind.name);
        expect(plan.objects, hasLength(kind == ProgramKind.table ? 5 : 1));
        expect(plan.quote, greaterThan(0));
        if (kind == ProgramKind.pictureFrame) {
          expect(plan.objects.single.region.holes, hasLength(1));
        }
        expect(c.applyProgram(plan), isTrue);
        expect(c.workspace.regions, isEmpty);
      }
    },
  );

  test('Volume stages subdivision and only consumes on Apply', () {
    final c = ProtoplaneController(unlimitedPaper: true);
    addTearDown(c.dispose);
    final p = c.planes['ground-starter-paperWhite-0-0']!,
        s = RegionSurface(c.planes['ground-starter-paperWhite-0-0']!, [
          'ground-starter-paperWhite-0-0',
        ]);
    final target = LightRegion('a', s.id, rectangle(.5, .5));
    c.workspace.surfaces[s.id] = s;
    c.workspace.regions[target.id] = target;
    final before = c.toJson().toString();
    final plan = c.evaluateProgram(
      ProgramKind.volume,
      target,
      s,
      const Offset(.25, .25),
    );
    expect(plan.issue, isNull);
    expect(c.applyProgram(plan), isTrue);
    expect(c.pendingVolume, isNotNull);
    expect(c.toJson().toString(), before);
    expect(c.workspace.regions, hasLength(1));
    c.setProgramDepth(.3);
    expect(c.applyProgram(c.pendingVolume!, confirmVolume: true), isTrue);
    expect(c.objects.values.single.depth, .3);
    expect(c.workspace.regions, isEmpty);
    expect(
      c.landscape.terrain
          .remainingInTile(p.id)
          .fold<double>(0, (s, r) => s + r.area),
      closeTo(.75, 1e-6),
    );
    c.undo();
    expect(c.toJson().toString(), before);
    expect(c.workspace.regions, hasLength(1));
    c.redo();
    expect(c.objects, hasLength(1));
    expect(c.workspace.regions, isEmpty);
  });

  test('stale implied drops and ended sessions cannot resurrect regions', () {
    final c = ProtoplaneController(unlimitedPaper: true);
    addTearDown(c.dispose);
    final p = c.planes['ground-starter-paperWhite-0-0']!,
        s = RegionSurface(c.planes['ground-starter-paperWhite-0-0']!, [
          'ground-starter-paperWhite-0-0',
        ]);
    c.workspace.surfaces[s.id] = s;
    final target = c.workspace.at(s.id, const Offset(.5, .5))!;
    final plan = c.evaluateProgram(ProgramKind.house, target, s, Offset.zero);
    c.drawLightPath(s, [const Offset(0, .5), const Offset(1, .5)]);
    final before = c.toJson().toString();
    expect(c.applyProgram(plan), isFalse);
    expect(c.programIssue, ProgramIssue.stale);
    expect(c.toJson().toString(), before);
    c.clearRegions();
    c.undo();
    expect(c.workspace.regions, hasLength(2));
    c.endRegionSession();
    c.undo();
    c.redo();
    expect(c.workspace.regions, isEmpty);
    expect(p.region.area, 1);
  });

  test(
    'unlimited paper migrates on, preserves balances, and can be disabled',
    () {
      final settings = ProtoplaneSettings();
      expect(settings.unlimitedPaper, isTrue);
      settings.load({...settings.toJson()}..remove('unlimitedPaper'));
      expect(settings.unlimitedPaper, isTrue);
      settings.unlimitedPaper = false;
      final restored = ProtoplaneSettings()..load(settings.toJson());
      expect(restored.unlimitedPaper, isFalse);
      final c = ProtoplaneController(unlimitedPaper: true);
      addTearDown(c.dispose);
      final balance = c.balances[PaperMaterial.paperWhite]!;
      c.spendPaper(PaperMaterial.paperWhite, 9000);
      expect(c.balances[PaperMaterial.paperWhite], balance);
      c.unlimitedPaper = false;
      expect(c.canSpend(PaperMaterial.paperWhite, 9000), isFalse);
      c.spendPaper(PaperMaterial.paperWhite, 20);
      expect(c.balances[PaperMaterial.paperWhite], balance - 20);
    },
  );

  test('nested material islands survive Boolean difference', () {
    final outer = Region(rectangle(3, 3).outer, [
      rectangle(1, 1, origin: const Offset(1, 1)).outer,
    ]);
    final inset = insetProgramRegion(outer, .1).single;
    final lining = outer.subtract(inset);
    expect(lining, hasLength(2));
    expect(lining.every((r) => r.valid), isTrue);
    expect(
      lining.fold<double>(0, (v, r) => v + r.area),
      closeTo(outer.area - inset.area, 1e-6),
    );
    expect(lining[0].overlaps(lining[1]), isFalse);
  });

  test(
    'house supports block removal, and finite programs charge once across undo',
    () {
      final c = ProtoplaneController()
        ..balances[PaperMaterial.paperWhite] = 9000;
      addTearDown(c.dispose);
      final p = c.planes['ground-starter-paperWhite-0-0']!,
          s = RegionSurface(c.planes['ground-starter-paperWhite-0-0']!, [
            'ground-starter-paperWhite-0-0',
          ]);
      final target = LightRegion('house', s.id, p.region);
      c.workspace.surfaces[s.id] = s;
      c.workspace.regions[target.id] = target;
      final plan = c.evaluateProgram(ProgramKind.house, target, s, Offset.zero);
      expect(plan.valid, isTrue);
      expect(c.applyProgram(plan), isTrue);
      final world = c.toJson().toString(),
          balance = c.balances[PaperMaterial.paperWhite];
      expect(balance, 9000 - plan.quote);
      final cut = LightRegion('implied:test', s.id, p.region, implied: true);
      expect(
        c.evaluateProgram(ProgramKind.cut, cut, s, Offset.zero).issue,
        ProgramIssue.support,
      );
      expect(c.toJson().toString(), world);
      c.undo();
      expect(c.balances[PaperMaterial.paperWhite], 9000);
      expect(c.workspace.regions, hasLength(1));
      c.redo();
      expect(c.toJson().toString(), world);
      expect(c.balances[PaperMaterial.paperWhite], balance);
    },
  );
}
