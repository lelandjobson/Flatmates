import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flatmates/crafting/placed_paper.dart';
import 'package:flatmates/gameplay/paint/face_paint_store.dart';
import 'package:flatmates/gameplay/paths/path_store.dart';
import 'package:flatmates/gameplay/friends/friend_instance.dart';
import 'package:flatmates/gameplay/recording/game_recording.dart';
import 'package:flatmates/gameplay/recording/game_recording_io.dart';
import 'package:flatmates/gameplay/viewers/world_plane.dart';
import 'package:flatmates/gameplay/vision/map_vision.dart';
import 'package:flatmates/gameplay/volumes/volume.dart';
import 'package:flatmates/gameplay/volumes/volume_store.dart';
import 'package:flatmates/gameplay/walls/wall_edge.dart';
import 'package:flatmates/gameplay/walls/wall_regions.dart';
import 'package:flatmates/gameplay/walls/wall_store.dart';
import 'package:flatmates/landscape/landscape_generator.dart';
import 'package:flatmates/landscape/landscape_grid.dart';
import 'package:flatmates/landscape/landscape_material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const vision = MapVisionConfig.game;
  final ox = vision.startingOriginTx;
  final oy = vision.startingOriginTy;

  VolumeStore emptyVolumes({int tilesSide = 16}) => VolumeStore(
        grid: VolumeGrid(tilesSide: tilesSide, tileSize: 8),
      );

  test('json roundtrip preserves volumes, paths, and face paint', () {
    final volumes = emptyVolumes();
    expect(volumes.startNew(3, 4), isTrue);
    volumes.draftCell!.box.widthSubtiles = 6;
    expect(volumes.confirmEdit(), isTrue);
    volumes.toggleAccess(VolumeSide.south);
    expect(volumes.confirmAccess(), isTrue);

    final paths = PathStore(grid: volumes.grid);
    expect(paths.addIsland(3, 5), isTrue);
    expect(paths.connect(3, 5, 3, 6), isTrue);

    final paint = FacePaintStore();
    final cell = volumes.volumes.single.cells.single;
    final canvas = paint.canvasFor(
      volumeId: volumes.volumes.single.id,
      cell: cell,
      face: VolumeFace.posY,
    );
    canvas.paint(1, 2, PaperColor.pink);

    final walls = WallStore(grid: volumes.grid);
    expect(walls.add(WallEdge(3, 5, 4, 5)), isTrue);

    final recording = GameRecording.capture(
      volumes: volumes,
      paths: paths,
      walls: walls,
      facePaint: paint,
    );
    final decoded = GameRecording.fromJson(
      jsonDecode(jsonEncode(recording.toJson())) as Map<String, dynamic>,
    );

    expect(decoded.volumes, hasLength(1));
    expect(decoded.volumes.single.id, 1);
    expect(decoded.volumes.single.cells.single.tx, 3);
    expect(decoded.volumes.single.cells.single.ty, 4);
    expect(decoded.volumes.single.cells.single.box.widthSubtiles, 6);
    expect(
      decoded.volumes.single.cells.single.accessibleSides,
      {VolumeSide.south},
    );
    expect(decoded.pathTiles, containsAll([(3, 5), (3, 6)]));
    expect(decoded.pathEdges, contains(PathEdge(3, 5, 3, 6)));
    expect(decoded.wallEdges, contains(WallEdge(3, 5, 4, 5)));
    expect(decoded.nextVolumeId, greaterThan(1));

    final roof = decoded.facePaint.canvases[const FacePaintKey(
      volumeId: 1,
      tx: 3,
      ty: 4,
      face: VolumeFace.posY,
    )];
    expect(roof, isNotNull);
    expect(roof!.colorAt(1, 2), PaperColor.pink);
  });

  test('applyTo replaces live content and landscape paint', () {
    final volumes = emptyVolumes(tilesSide: vision.worldTilesSide);
    expect(volumes.startNew(0, 0), isTrue);
    expect(volumes.confirmEdit(), isTrue);
    volumes.toggleAccess(VolumeSide.south);
    expect(volumes.confirmAccess(), isTrue);
    final paths = PathStore(grid: volumes.grid)..addIsland(1, 1);
    final paint = FacePaintStore();

    final recording = GameRecording.sample();
    final walls = WallStore(grid: volumes.grid);
    recording.applyTo(
      volumes: volumes,
      paths: paths,
      walls: walls,
      facePaint: paint,
    );

    expect(volumes.volumes, hasLength(4));
    expect(volumes.phase, VolumeEditPhase.idle);
    expect(volumes.draftVolume, isNull);
    expect(volumes.occupant(0, 0), isNull);
    expect(volumes.occupant(ox + 5, oy + 5), 1);
    expect(volumes.occupant(ox + 12, oy + 10), 3);
    expect(paths.contains(ox + 5, oy + 6), isTrue);
    expect(paths.contains(1, 1), isFalse);
    expect(
      paint.canvases.containsKey(
        FacePaintKey(
          volumeId: 1,
          tx: ox + 5,
          ty: oy + 5,
          face: VolumeFace.posY,
        ),
      ),
      isTrue,
    );
    expect(
      paint.canvases.containsKey(
        FacePaintKey(
          volumeId: 2,
          tx: ox + 10,
          ty: oy + 5,
          face: VolumeFace.posX,
        ),
      ),
      isTrue,
    );
    expect(
      paint.canvases.containsKey(
        FacePaintKey(
          volumeId: 4,
          tx: ox + 4,
          ty: oy + 9,
          face: VolumeFace.negZ,
        ),
      ),
      isTrue,
    );
  });

  test('capture and apply landscape paint and erase', () {
    final gen = LandscapeGenerator(
      const LandscapeGenParams(tilesSide: 16, pixelsPerTile: 8),
    );
    final grid = LandscapeGrid.fromGenerator(gen);
    expect(grid.paint(4, 5, PaperColor.green), isTrue);
    expect(grid.erase(6, 7), isTrue);

    final volumes = emptyVolumes();
    final paths = PathStore(grid: volumes.grid);
    final paint = FacePaintStore();
    final walls = WallStore(grid: volumes.grid);
    final recording = GameRecording.capture(
      volumes: volumes,
      paths: paths,
      walls: walls,
      facePaint: paint,
      landscape: grid,
    );
    expect(recording.landscapePaint, contains((4, 5, PaperColor.green.index)));
    expect(recording.landscapeErase, contains((6, 7)));

    final restored = LandscapeGrid.fromGenerator(gen);
    expect(restored.paintIds[restored.index(4, 5)], LandscapeGrid.kNoPaint);
    recording.applyTo(
      volumes: volumes,
      paths: paths,
      walls: walls,
      facePaint: paint,
      landscape: restored,
      generator: gen,
    );
    expect(restored.paintIds[restored.index(4, 5)], PaperColor.green.index);
    expect(restored.materials[restored.index(6, 7)], kLandscapeEmpty);
  });

  test('sample recording encodes and decodes', () {
    final encoded = GameRecording.sample().toJson();
    final decoded = GameRecording.fromJson(encoded);
    expect(decoded.volumes, hasLength(4));
    expect(decoded.pathTiles, isNotEmpty);
    expect(decoded.pathEdges, isNotEmpty);
    expect(decoded.facePaint.canvases, isNotEmpty);
    expect(decoded.nextVolumeId, 5);
    expect(decoded.wallEdges, isNotEmpty);
    expect(decoded.friends, hasLength(1));
    expect(decoded.friends.single.friend.id, kCubeboyFriend.id);
  });

  test('sample walls form four enclosed regions', () {
    final walls = WallStore(
      grid: VolumeGrid(tilesSide: vision.worldTilesSide, tileSize: 8),
    );
    walls.restore(GameRecording.sample().wallEdges);
    final regions = computeEnclosedRegions(walls);
    expect(regions, hasLength(4));
  });

  test('legacy recordings without walls or friends decode empty', () {
    final json = GameRecording.sample().toJson();
    json.remove('walls');
    json.remove('friends');
    final decoded = GameRecording.fromJson(json);
    expect(decoded.wallEdges, isEmpty);
    expect(decoded.friends, isEmpty);
  });

  test('repo default recording path resolves', () {
    final file = GameRecordingIo.resolveDefaultFile();
    expect(file, isNotNull);
    expect(file!.existsSync(), isTrue);
  });

  testWidgets('bundled default recording decodes', (tester) async {
    final raw = await rootBundle.loadString(kDefaultGameRecordingPath);
    final fromAsset = GameRecording.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
    expect(fromAsset.version, GameRecording.currentSchemaVersion);
    expect(fromAsset.volumes, isNotEmpty);
    expect(fromAsset.pathTiles, isNotEmpty);
    expect(fromAsset.friends, isNotEmpty);
    expect(fromAsset.friends.single.friend.id, kCubeboyFriend.id);
    final walls = WallStore(
      grid: VolumeGrid(tilesSide: vision.worldTilesSide, tileSize: 8),
    )..restore(fromAsset.wallEdges);
    expect(computeEnclosedRegions(walls), isNotEmpty);
  });
}
