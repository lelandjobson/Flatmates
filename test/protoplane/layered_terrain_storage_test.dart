import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/protoplane/models.dart';
import 'package:flatmates/protoplane/storage.dart';
import 'package:flatmates/protoplane/world_sessions.dart';
import 'layered_terrain_test.dart' show centerId, drawTile, snapshot;

void main() {
  test(
    'Paper saves, recovery, switching, drafts and histories remain independent',
    () async {
      final dir = await Directory.systemTemp.createTemp('paper-worlds');
      addTearDown(() => dir.delete(recursive: true));
      WorldSessions sessions() => WorldSessions(
        storageFactory: (p) =>
            ProtoplaneStorage(directory: () async => dir, fileName: p.fileName),
      );
      final worlds = sessions();
      addTearDown(worlds.dispose);
      await worlds.load(WorldPreset.paper);
      final paper = worlds.controller(WorldPreset.paper);
      paper.enter(centerId(paper, PaperMaterial.paperWhite));
      drawTile(paper);
      paper.commitDrawing();
      final saved = snapshot(paper);
      paper.appendNode(0);
      final ink = await worlds.switchFrom(WorldPreset.paper, WorldPreset.ink);
      final inkBefore = snapshot(ink);
      expect(
        await worlds.switchFrom(WorldPreset.ink, WorldPreset.paper),
        same(paper),
      );
      expect(paper.draft.path, [0]);
      paper.undo(); // draft
      paper.undo(); // harvest
      expect(paper.balances[PaperMaterial.paperWhite], 256);
      paper.redo();
      expect(snapshot(paper), saved);
      await worlds.switchFrom(WorldPreset.paper, WorldPreset.ink);
      final file = File('${dir.path}/protoplane_concept/world-paper.json');
      await file.writeAsString('broken');
      final fresh = sessions();
      addTearDown(fresh.dispose);
      await fresh.load(WorldPreset.paper);
      expect(fresh.storage(WorldPreset.paper).recoveryMessage, isNotNull);
      expect(snapshot(fresh.controller(WorldPreset.paper)), saved);
      fresh.controller(WorldPreset.paper).clearWorld();
      await fresh.load(WorldPreset.ink);
      expect(snapshot(fresh.controller(WorldPreset.ink)), inkBefore);
      final blocked = WorldSessions(
        storageFactory: (p) => ProtoplaneStorage(
          directory: () =>
              Future.error(FileSystemException('Disk unavailable')),
          fileName: p.fileName,
        ),
      );
      addTearDown(blocked.dispose);
      expect(
        () => blocked.switchFrom(WorldPreset.paper, WorldPreset.ink),
        throwsStateError,
      );
    },
  );
  test(
    'navigation follows exposed edges, never bridges islands, and restores after undo',
    () {
      final c = ProtoplaneController(preset: WorldPreset.paper);
      addTearDown(c.dispose);
      final white = centerId(c, PaperMaterial.paperWhite);
      final graph = c.navigationGraph;
      final neighbors = graph.neighbors[white]!;
      expect(neighbors.length, 4);
      expect(
        neighbors.every(
          (e) =>
              c.landscape.terrain!.tiles[e.planeId]!.sheet.material ==
              PaperMaterial.paperWhite,
        ),
        isTrue,
      );
      for (final entry in graph.neighbors.entries) {
        final island = c.landscape.terrain!.tiles[entry.key]!.sheet.island;
        expect(
          entry.value.every(
            (e) =>
                c.landscape.terrain!.tiles[e.planeId]!.sheet.island == island,
          ),
          isTrue,
        );
      }
      final nodes = c.planes[white]!.grids.first.nodes.toList();
      c.enter(white);
      drawTile(c);
      c.commitDrawing();
      expect(c.navigationGraph, isNot(same(graph)));
      expect(c.navigationGraph, same(c.navigationGraph));
      expect(c.navigationGraph.neighbors[white], isNull);
      expect(c.planes[white]!.grids.first.nodes, nodes);
      c.undo();
      expect(c.navigationGraph.neighbors[white]!.length, 4);
      expect(c.planes[white]!.grids.first.nodes, nodes);
    },
  );
}
