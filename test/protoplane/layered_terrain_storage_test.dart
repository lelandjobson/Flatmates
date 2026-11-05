import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/protoplane/models.dart';
import 'package:flatmates/protoplane/storage.dart';
import 'dart:convert';
import 'layered_terrain_test.dart' show centerId, drawTile, snapshot;

void main() {
  test(
    'Paper saves retain history, recover backups, and ignore retired files',
    () async {
      final dir = await Directory.systemTemp.createTemp('paper-storage-');
      addTearDown(() => dir.delete(recursive: true));
      ProtoplaneStorage store() =>
          ProtoplaneStorage(directory: () async => dir);
      final paper = ProtoplaneController();
      addTearDown(paper.dispose);
      final storage = store();
      await storage.load(paper.load);
      final folder = Directory('${dir.path}/protoplane_concept');
      final retired = [
        File('${folder.path}/world-ink.json'),
        File('${folder.path}/world.json'),
      ];
      for (final file in retired) {
        await file.writeAsString('retired world');
      }
      paper.enter(centerId(paper, PaperMaterial.paperWhite));
      drawTile(paper);
      paper.commitDrawing();
      final saved = snapshot(paper);
      await storage.save(saved);
      paper.undo();
      expect(paper.balances[PaperMaterial.paperWhite], 256);
      paper.redo();
      expect(snapshot(paper), saved);
      await storage.save(saved);
      final file = File('${folder.path}/world-paper.json');
      await file.writeAsString('broken');
      final recovered = store();
      final loaded = await recovered.load(paper.load);
      expect(recovered.recoveryMessage, isNotNull);
      expect(loaded, saved);
      paper.clearWorld();
      await recovered.save(paper.toJson());
      for (final old in retired) {
        expect(await old.readAsString(), 'retired world');
      }
      for (final preset in ['ink', 'pastel']) {
        final bad = jsonDecode(jsonEncode(saved)) as Map<String, dynamic>;
        bad['preset'] = preset;
        final before = paper.toJson();
        expect(() => paper.load(bad), throwsFormatException);
        expect(paper.toJson(), before);
      }
      final blocked = ProtoplaneStorage(
        directory: () => Future.error(FileSystemException('Disk unavailable')),
      );
      await expectLater(blocked.save(saved), throwsStateError);
    },
  );
  test(
    'navigation follows exposed edges, never bridges islands, and restores after undo',
    () {
      final c = ProtoplaneController();
      addTearDown(c.dispose);
      final white = centerId(c, PaperMaterial.paperWhite);
      final graph = c.navigationGraph;
      final neighbors = graph.neighbors[white]!;
      expect(neighbors.length, 4);
      expect(
        neighbors.every(
          (e) =>
              c.landscape.terrain.tiles[e.planeId]!.sheet.material ==
              PaperMaterial.paperWhite,
        ),
        isTrue,
      );
      for (final entry in graph.neighbors.entries) {
        final island = c.landscape.terrain.tiles[entry.key]!.sheet.island;
        expect(
          entry.value.every(
            (e) => c.landscape.terrain.tiles[e.planeId]!.sheet.island == island,
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
