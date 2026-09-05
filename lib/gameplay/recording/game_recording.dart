import 'package:vector_math/vector_math_64.dart';

import '../../crafting/placed_paper.dart';
import '../../landscape/landscape_generator.dart';
import '../../landscape/landscape_grid.dart';
import '../friends/friend_instance.dart';
import '../friends/friend_instance_store.dart';
import '../friends/friend_mesh_sync.dart';
import '../vision/map_vision.dart';
import '../paint/face_paint_store.dart';
import '../paper/paper_cost.dart';
import '../paper/paper_wallet.dart';
import '../paths/path_store.dart';
import '../viewers/world_plane.dart';
import '../volumes/volume.dart';
import '../volumes/volume_store.dart';
import '../walls/wall_edge.dart';
import '../walls/wall_store.dart';

/// Repo-relative path for the default GameView recording.
const kDefaultGameRecordingPath = 'assets/gameplay/recordings/default.json';

/// Authored gameplay content that can be written to JSON and reapplied later.
///
/// Generated landscape materials are not stored — only paint / erase, plus
/// volumes, paths, and face canvases. Coverage voids are rebuilt on apply.
class GameRecording {
  const GameRecording({
    required this.nextVolumeId,
    required this.volumes,
    required this.pathTiles,
    required this.pathEdges,
    required this.wallEdges,
    required this.friends,
    required this.facePaint,
    required this.landscapePaint,
    required this.landscapeErase,
    this.paperHeld = kStartingPaper,
    this.volumePaperCommitted = const {},
    this.pathPaperCommitted = 0,
    this.wallPaperCommitted = 0,
    this.paperPersisted = false,
    this.version = currentSchemaVersion,
  });

  static const int currentSchemaVersion = 1;

  /// Stable instance id for the sample Cubeboy.
  static const String sampleCubeboyId = 'rec-cubeboy-1';

  final int version;
  final int nextVolumeId;
  final List<Volume> volumes;
  final Set<(int, int)> pathTiles;
  final Set<PathEdge> pathEdges;
  final Set<WallEdge> wallEdges;
  final List<FriendInstance> friends;
  final FacePaintStore facePaint;
  final List<(int x, int y, int colorIndex)> landscapePaint;
  final List<(int x, int y)> landscapeErase;
  final int paperHeld;
  final Map<int, int> volumePaperCommitted;
  final int pathPaperCommitted;
  final int wallPaperCommitted;
  final bool paperPersisted;

  factory GameRecording.empty() => GameRecording(
        nextVolumeId: 1,
        volumes: const [],
        pathTiles: {},
        pathEdges: {},
        wallEdges: {},
        friends: const [],
        facePaint: FacePaintStore(),
        landscapePaint: const [],
        landscapeErase: const [],
      );

  /// A small village used to bootstrap [kDefaultGameRecordingPath].
  factory GameRecording.sample() {
    final houseA = Volume(
      id: 1,
      cells: [
        VolumeCell(
          tx: 5,
          ty: 5,
          box: BoxPrimitive(),
          accessibleSides: {VolumeSide.south},
        ),
        VolumeCell(tx: 6, ty: 5, box: BoxPrimitive()),
      ],
    );
    final houseB = Volume(
      id: 2,
      cells: [
        VolumeCell(
          tx: 10,
          ty: 5,
          box: BoxPrimitive(
            widthSubtiles: 7,
            depthSubtiles: 7,
            heightSubtiles: 5,
            originXSubtiles: 1,
            originZSubtiles: 1,
          ),
          accessibleSides: {VolumeSide.south},
        ),
      ],
    );
    final houseC = Volume(
      id: 3,
      cells: [
        VolumeCell(
          tx: 11,
          ty: 9,
          box: BoxPrimitive(),
          accessibleSides: {VolumeSide.west},
        ),
        VolumeCell(tx: 12, ty: 9, box: BoxPrimitive()),
        VolumeCell(tx: 11, ty: 10, box: BoxPrimitive()),
        VolumeCell(tx: 12, ty: 10, box: BoxPrimitive()),
      ],
    );
    final houseD = Volume(
      id: 4,
      cells: [
        VolumeCell(
          tx: 4,
          ty: 9,
          box: BoxPrimitive(
            widthSubtiles: 6,
            depthSubtiles: 8,
            heightSubtiles: 6,
            originXSubtiles: 2,
          ),
          accessibleSides: {VolumeSide.east},
        ),
      ],
    );

    final paint = FacePaintStore.fromCanvases({
      const FacePaintKey(
        volumeId: 1,
        tx: 5,
        ty: 5,
        face: VolumeFace.posY,
      ): _roofCanvas(8, 8, PaperColor.pink, PaperColor.yellow),
      const FacePaintKey(
        volumeId: 1,
        tx: 6,
        ty: 5,
        face: VolumeFace.posY,
      ): _roofCanvas(8, 8, PaperColor.pink, PaperColor.green),
      const FacePaintKey(
        volumeId: 2,
        tx: 10,
        ty: 5,
        face: VolumeFace.posY,
      ): _roofCanvas(7, 7, PaperColor.yellow, PaperColor.green),
      const FacePaintKey(
        volumeId: 3,
        tx: 11,
        ty: 9,
        face: VolumeFace.posY,
      ): _roofCanvas(8, 8, PaperColor.green, PaperColor.pink),
      const FacePaintKey(
        volumeId: 3,
        tx: 12,
        ty: 9,
        face: VolumeFace.posY,
      ): _roofCanvas(8, 8, PaperColor.green, PaperColor.yellow),
      const FacePaintKey(
        volumeId: 3,
        tx: 11,
        ty: 10,
        face: VolumeFace.posY,
      ): _roofCanvas(8, 8, PaperColor.green, PaperColor.pink),
      const FacePaintKey(
        volumeId: 3,
        tx: 12,
        ty: 10,
        face: VolumeFace.posY,
      ): _roofCanvas(8, 8, PaperColor.yellow, PaperColor.green),
      const FacePaintKey(
        volumeId: 4,
        tx: 4,
        ty: 9,
        face: VolumeFace.posY,
      ): _roofCanvas(6, 8, PaperColor.yellow, PaperColor.pink),
      ..._sideCanvases(
        volumeId: 2,
        tx: 10,
        ty: 5,
        box: houseB.cells.single.box,
        a: PaperColor.yellow,
        b: PaperColor.green,
      ),
      ..._sideCanvases(
        volumeId: 4,
        tx: 4,
        ty: 9,
        box: houseD.cells.single.box,
        a: PaperColor.yellow,
        b: PaperColor.pink,
      ),
    });

    final tiles = <(int, int)>{
      (5, 6),
      (6, 6),
      (7, 6),
      (8, 6),
      (9, 6),
      (10, 6),
      (8, 7),
      (8, 8),
      (5, 9),
      (6, 9),
      (7, 9),
      (8, 9),
      (9, 9),
      (10, 9),
    };

    final edges = <PathEdge>{
      PathEdge(5, 6, 6, 6),
      PathEdge(6, 6, 7, 6),
      PathEdge(7, 6, 8, 6),
      PathEdge(8, 6, 9, 6),
      PathEdge(9, 6, 10, 6),
      PathEdge(8, 6, 8, 7),
      PathEdge(8, 7, 8, 8),
      PathEdge(8, 8, 8, 9),
      PathEdge(5, 9, 6, 9),
      PathEdge(6, 9, 7, 9),
      PathEdge(7, 9, 8, 9),
      PathEdge(8, 9, 9, 9),
      PathEdge(9, 9, 10, 9),
    };

    const grid = VolumeGrid(tilesSide: 16, tileSize: 8);
    final cubeboyAt = grid.tileCenter(8, 7)
      ..y = FriendMeshLayout.sitOnGroundY(tileSize: grid.tileSize);

    return GameRecording(
      nextVolumeId: 5,
      volumes: [houseA, houseB, houseC, houseD],
      pathTiles: tiles,
      pathEdges: edges,
      wallEdges: {
        ..._encloseTile(2, 2),
        ..._encloseTile(13, 2),
        ..._encloseTile(2, 13),
        ..._encloseRect(12, 12, 14, 14),
      },
      friends: [
        FriendInstance(
          id: sampleCubeboyId,
          friend: kCubeboyFriend,
          position: cubeboyAt,
        ),
      ],
      facePaint: paint,
      landscapePaint: const [
        (7, 50, 0),
        (8, 50, 0),
        (9, 50, 1),
        (7, 51, 2),
        (8, 51, 1),
        (9, 51, 2),
      ],
      landscapeErase: const [],
    ).shifted(
      dtx: MapVisionConfig.game.startingOriginTx,
      dty: MapVisionConfig.game.startingOriginTy,
    );
  }

  /// Move tile-space content by [dtx],[dty]. Friend world positions stay put
  /// so a centered map expansion keeps them in the starting village.
  GameRecording shifted({
    required int dtx,
    required int dty,
    int pixelsPerTile = VolumeGrid.defaultSubtilesPerTile,
  }) {
    if (dtx == 0 && dty == 0) return this;
    final dxp = dtx * pixelsPerTile;
    final dyp = dty * pixelsPerTile;
    return GameRecording(
      version: version,
      nextVolumeId: nextVolumeId,
      volumes: [
        for (final volume in volumes)
          Volume(
            id: volume.id,
            datum: volume.datum,
            cells: [
              for (final cell in volume.cells)
                VolumeCell(
                  tx: cell.tx + dtx,
                  ty: cell.ty + dty,
                  box: cell.box.clone(),
                  accessibleSides: Set<VolumeSide>.from(cell.accessibleSides),
                  doorOrigins: Map<VolumeSide, int>.from(cell.doorOrigins),
                ),
            ],
          ),
      ],
      pathTiles: {
        for (final tile in pathTiles) (tile.$1 + dtx, tile.$2 + dty),
      },
      pathEdges: {
        for (final edge in pathEdges)
          PathEdge(edge.x0 + dtx, edge.y0 + dty, edge.x1 + dtx, edge.y1 + dty),
      },
      wallEdges: {
        for (final edge in wallEdges)
          WallEdge(
            edge.x0 + dtx,
            edge.y0 + dty,
            edge.x1 + dtx,
            edge.y1 + dty,
            kind: edge.kind,
          ),
      },
      friends: [for (final instance in friends) instance.clone()],
      facePaint: FacePaintStore.fromCanvases({
        for (final entry in facePaint.canvases.entries)
          FacePaintKey(
            volumeId: entry.key.volumeId,
            tx: entry.key.tx + dtx,
            ty: entry.key.ty + dty,
            face: entry.key.face,
          ): entry.value,
      }),
      landscapePaint: [
        for (final cell in landscapePaint)
          (cell.$1 + dxp, cell.$2 + dyp, cell.$3),
      ],
      landscapeErase: [
        for (final cell in landscapeErase) (cell.$1 + dxp, cell.$2 + dyp),
      ],
    );
  }

  static FaceCanvas _roofCanvas(
    int width,
    int height,
    PaperColor a,
    PaperColor b,
  ) {
    final canvas = FaceCanvas(width: width, height: height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final border = x == 0 || y == 0 || x == width - 1 || y == height - 1;
        canvas.paint(x, y, border ? a : ((x + y).isEven ? a : b));
      }
    }
    return canvas;
  }

  static Map<FacePaintKey, FaceCanvas> _sideCanvases({
    required int volumeId,
    required int tx,
    required int ty,
    required BoxPrimitive box,
    required PaperColor a,
    required PaperColor b,
  }) {
    const sides = [
      VolumeFace.posX,
      VolumeFace.negX,
      VolumeFace.posZ,
      VolumeFace.negZ,
    ];
    return {
      for (final face in sides)
        FacePaintKey(volumeId: volumeId, tx: tx, ty: ty, face: face):
            _filledFace(box, face, a, b),
    };
  }

  static FaceCanvas _filledFace(
    BoxPrimitive box,
    VolumeFace face,
    PaperColor a,
    PaperColor b,
  ) {
    final (width, height) = FacePaintStore.faceSize(box, face);
    final canvas = FaceCanvas(width: width, height: height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        canvas.paint(x, y, (x + y).isEven ? a : b);
      }
    }
    return canvas;
  }

  static Set<WallEdge> _encloseTile(int tx, int ty) => _encloseRect(
        tx,
        ty,
        tx + 1,
        ty + 1,
      );

  /// Vertex-space rectangle [x0,x1] × [y0,y1]. Tiles inside are the region.
  static Set<WallEdge> _encloseRect(int x0, int y0, int x1, int y1) {
    final edges = <WallEdge>{};
    for (var x = x0; x < x1; x++) {
      edges.add(WallEdge(x, y0, x + 1, y0));
      edges.add(WallEdge(x, y1, x + 1, y1));
    }
    for (var y = y0; y < y1; y++) {
      edges.add(WallEdge(x0, y, x0, y + 1));
      edges.add(WallEdge(x1, y, x1, y + 1));
    }
    return edges;
  }

  factory GameRecording.capture({
    required VolumeStore volumes,
    required PathStore paths,
    required WallStore walls,
    required FacePaintStore facePaint,
    FriendInstanceStore? friends,
    LandscapeGrid? landscape,
    PaperWallet? paper,
  }) {
    var nextId = volumes.nextId;
    for (final volume in volumes.volumes) {
      if (volume.id >= nextId) nextId = volume.id + 1;
    }
    return GameRecording(
      nextVolumeId: nextId,
      volumes: [for (final volume in volumes.volumes) volume.clone()],
      pathTiles: Set<(int, int)>.from(paths.tiles),
      pathEdges: Set<PathEdge>.from(paths.edges),
      wallEdges: Set<WallEdge>.from(walls.edges),
      friends: [
        if (friends != null)
          for (final instance in friends.instances) instance.clone(),
      ],
      facePaint: facePaint.copy(),
      landscapePaint: [
        if (landscape != null)
          for (var y = 0; y < landscape.side; y++)
            for (var x = 0; x < landscape.side; x++)
              if (landscape.paintIds[landscape.index(x, y)] >= 0)
                (x, y, landscape.paintIds[landscape.index(x, y)]),
      ],
      landscapeErase: [
        if (landscape != null)
          for (var y = 0; y < landscape.side; y++)
            for (var x = 0; x < landscape.side; x++)
              if (landscape.materials[landscape.index(x, y)] == kLandscapeEmpty)
                (x, y),
      ],
      paperHeld: paper?.held ?? kStartingPaper,
      volumePaperCommitted: paper == null
          ? const {}
          : Map<int, int>.from(paper.volumeCommitted),
      pathPaperCommitted: paper?.pathCommitted ?? 0,
      wallPaperCommitted: paper?.wallCommitted ?? 0,
      paperPersisted: paper != null,
    );
  }

  void applyTo({
    required VolumeStore volumes,
    required PathStore paths,
    required WallStore walls,
    required FacePaintStore facePaint,
    FriendInstanceStore? friends,
    LandscapeGrid? landscape,
    LandscapeGenerator? generator,
    PaperWallet? paper,
  }) {
    volumes.restore(
      volumes: [for (final volume in this.volumes) volume.clone()],
      draftVolume: null,
      draftCell: null,
      draftIsGrow: false,
      phase: VolumeEditPhase.idle,
      nextId: nextVolumeId,
    );
    paths.restore(
      tiles: Set<(int, int)>.from(pathTiles),
      edges: Set<PathEdge>.from(pathEdges),
    );
    walls.restore(Set<WallEdge>.from(wallEdges));
    friends?.restore([
      for (final instance in this.friends) instance.clone(),
    ]);
    facePaint.restoreFrom(this.facePaint);
    if (landscape != null) {
      if (generator != null) {
        landscape.restoreFrom(LandscapeGrid.fromGenerator(generator));
      }
      for (final cell in landscapeErase) {
        landscape.erase(cell.$1, cell.$2);
      }
      for (final cell in landscapePaint) {
        final colorIndex = cell.$3;
        if (colorIndex < 0 || colorIndex >= PaperColor.values.length) continue;
        landscape.paint(cell.$1, cell.$2, PaperColor.values[colorIndex]);
      }
    }
    if (paper == null) return;
    if (paperPersisted) {
      final restored = PaperWallet(held: paperHeld);
      restored.volumeCommitted.addAll(volumePaperCommitted);
      restored.pathCommitted = pathPaperCommitted;
      restored.wallCommitted = wallPaperCommitted;
      paper.restoreFrom(restored);
    } else {
      paper.restoreFrom(PaperWallet());
      paper.settleWorld(volumes: volumes, paths: paths, walls: walls);
    }
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': version,
        'nextVolumeId': nextVolumeId,
        'volumes': [
          for (final volume in volumes) _volumeToJson(volume),
        ],
        'paths': {
          'tiles': [
            for (final tile in _sortedTiles(pathTiles)) [tile.$1, tile.$2],
          ],
          'edges': [
            for (final edge in _sortedEdges(pathEdges))
              [edge.x0, edge.y0, edge.x1, edge.y1],
          ],
        },
        'walls': {
          'edges': [
            for (final edge in _sortedWallEdges(wallEdges))
              [edge.x0, edge.y0, edge.x1, edge.y1, edge.kind.name],
          ],
        },
        'friends': [
          for (final instance in friends)
            {
              'id': instance.id,
              'friendId': instance.friend.id,
              'position': [
                instance.position.x,
                instance.position.y,
                instance.position.z,
              ],
              'yaw': instance.yaw,
            },
        ],
        'facePaint': [
          for (final entry in _sortedFacePaint(facePaint.canvases))
            if (_canvasHasPaint(entry.value))
              {
                'volumeId': entry.key.volumeId,
                'tx': entry.key.tx,
                'ty': entry.key.ty,
                'face': entry.key.face.name,
                'width': entry.value.width,
                'height': entry.value.height,
                'cells': entry.value.cells.toList(),
              },
        ],
        'landscape': {
          'paint': [
            for (final cell in landscapePaint) [cell.$1, cell.$2, cell.$3],
          ],
          'erase': [
            for (final cell in landscapeErase) [cell.$1, cell.$2],
          ],
        },
        if (paperPersisted)
          'paper': {
            'held': paperHeld,
            'volumes': {
              for (final e in volumePaperCommitted.entries) '${e.key}': e.value,
            },
            'path': pathPaperCommitted,
            'walls': wallPaperCommitted,
          },
      };

  factory GameRecording.fromJson(Map<String, dynamic> json) {
    final version = _int(json['schemaVersion']) ?? currentSchemaVersion;
    if (version != currentSchemaVersion) {
      throw FormatException(
        'Unsupported game recording schemaVersion $version',
      );
    }
    final volumesJson = json['volumes'];
    final volumes = <Volume>[
      if (volumesJson is List)
        for (final item in volumesJson)
          if (item is Map) _volumeFromJson(item.cast<String, dynamic>()),
    ];
    var nextId = _int(json['nextVolumeId']) ?? 1;
    for (final volume in volumes) {
      if (volume.id >= nextId) nextId = volume.id + 1;
    }

    final pathsJson = json['paths'];
    final pathsMap = pathsJson is Map
        ? pathsJson.cast<String, dynamic>()
        : const <String, dynamic>{};
    final tiles = <(int, int)>{
      for (final item in _asList(pathsMap['tiles']))
        if (item is List && item.length >= 2) (_int(item[0])!, _int(item[1])!),
    };
    final edges = <PathEdge>{
      for (final item in _asList(pathsMap['edges']))
        if (item is List && item.length >= 4)
          PathEdge(_int(item[0])!, _int(item[1])!, _int(item[2])!, _int(item[3])!),
    };

    final wallsJson = json['walls'];
    final wallsMap = wallsJson is Map
        ? wallsJson.cast<String, dynamic>()
        : const <String, dynamic>{};
    final wallEdges = <WallEdge>{
      for (final item in _asList(wallsMap['edges']))
        if (item is List && item.length >= 4)
          WallEdge(
            _int(item[0])!,
            _int(item[1])!,
            _int(item[2])!,
            _int(item[3])!,
            kind: wallKindFromName(item.length >= 5 ? item[4] as String? : null),
          ),
    };

    final friends = <FriendInstance>[
      for (final item in _asList(json['friends']))
        if (item is Map) _friendFromJson(item.cast<String, dynamic>()),
    ];

    final canvases = <FacePaintKey, FaceCanvas>{};
    for (final item in _asList(json['facePaint'])) {
      if (item is! Map) continue;
      final map = item.cast<String, dynamic>();
      final face = _faceFromName(map['face'] as String?);
      if (face == null) continue;
      final width = _int(map['width']);
      final height = _int(map['height']);
      final cells = _asList(map['cells']).map(_int).whereType<int>().toList();
      if (width == null || height == null || cells.length != width * height) {
        continue;
      }
      canvases[FacePaintKey(
        volumeId: _int(map['volumeId']) ?? 0,
        tx: _int(map['tx']) ?? 0,
        ty: _int(map['ty']) ?? 0,
        face: face,
      )] = FaceCanvas.fromCells(width: width, height: height, cells: cells);
    }

    final landscapeJson = json['landscape'];
    final landscapeMap = landscapeJson is Map
        ? landscapeJson.cast<String, dynamic>()
        : const <String, dynamic>{};
    final paint = <(int, int, int)>[
      for (final item in _asList(landscapeMap['paint']))
        if (item is List && item.length >= 3)
          (_int(item[0])!, _int(item[1])!, _int(item[2])!),
    ];
    final erase = <(int, int)>[
      for (final item in _asList(landscapeMap['erase']))
        if (item is List && item.length >= 2) (_int(item[0])!, _int(item[1])!),
    ];

    final paperJson = json['paper'];
    final paperMap = paperJson is Map
        ? paperJson.cast<String, dynamic>()
        : null;
    final volumePaper = <int, int>{};
    if (paperMap != null) {
      final volumesPaper = paperMap['volumes'];
      if (volumesPaper is Map) {
        for (final entry in volumesPaper.entries) {
          final id = int.tryParse('${entry.key}');
          final cost = _int(entry.value);
          if (id != null && cost != null) volumePaper[id] = cost;
        }
      }
    }

    return GameRecording(
      version: version,
      nextVolumeId: nextId,
      volumes: volumes,
      pathTiles: tiles,
      pathEdges: edges,
      wallEdges: wallEdges,
      friends: friends,
      facePaint: FacePaintStore.fromCanvases(canvases),
      landscapePaint: paint,
      landscapeErase: erase,
      paperHeld: paperMap == null
          ? kStartingPaper
          : (_int(paperMap['held']) ?? kStartingPaper),
      volumePaperCommitted: volumePaper,
      pathPaperCommitted: paperMap == null ? 0 : (_int(paperMap['path']) ?? 0),
      wallPaperCommitted: paperMap == null ? 0 : (_int(paperMap['walls']) ?? 0),
      paperPersisted: paperMap != null,
    );
  }
}

Map<String, dynamic> _volumeToJson(Volume volume) => {
      'id': volume.id,
      'datum': volume.datum,
      'cells': [
        for (final cell in volume.cells)
          {
            'tx': cell.tx,
            'ty': cell.ty,
            'box': {
              'widthSubtiles': cell.box.widthSubtiles,
              'depthSubtiles': cell.box.depthSubtiles,
              'heightSubtiles': cell.box.heightSubtiles,
              'originXSubtiles': cell.box.originXSubtiles,
              'originZSubtiles': cell.box.originZSubtiles,
            },
            'accessibleSides': [
              for (final side in VolumeSide.values)
                if (cell.accessibleSides.contains(side)) side.name,
            ],
            'doorOrigins': {
              for (final side in VolumeSide.values)
                if (cell.doorOrigins.containsKey(side))
                  side.name: cell.doorOrigins[side],
            },
          },
      ],
    };

FriendInstance _friendFromJson(Map<String, dynamic> json) {
  final pos = _asList(json['position']);
  return FriendInstance(
    id: json['id'] as String? ?? GameRecording.sampleCubeboyId,
    friend: friendTemplateById(json['friendId'] as String? ?? kCubeboyFriend.id),
    position: Vector3(
      _double(pos.isNotEmpty ? pos[0] : 0) ?? 0,
      _double(pos.length > 1 ? pos[1] : 0) ?? 0,
      _double(pos.length > 2 ? pos[2] : 0) ?? 0,
    ),
    yaw: _double(json['yaw']) ?? 0,
  );
}

Volume _volumeFromJson(Map<String, dynamic> json) {
  final cells = <VolumeCell>[
    for (final item in _asList(json['cells']))
      if (item is Map) _cellFromJson(item.cast<String, dynamic>()),
  ];
  return Volume(
    id: _int(json['id']) ?? 0,
    cells: cells,
    datum: _int(json['datum']) ?? 0,
  );
}

VolumeCell _cellFromJson(Map<String, dynamic> json) {
  final boxJson = json['box'];
  final boxMap = boxJson is Map
      ? boxJson.cast<String, dynamic>()
      : const <String, dynamic>{};
  return VolumeCell(
    tx: _int(json['tx']) ?? 0,
    ty: _int(json['ty']) ?? 0,
    box: BoxPrimitive(
      widthSubtiles:
          _int(boxMap['widthSubtiles']) ?? VolumeGrid.defaultSubtilesPerTile,
      depthSubtiles:
          _int(boxMap['depthSubtiles']) ?? VolumeGrid.defaultSubtilesPerTile,
      heightSubtiles:
          _int(boxMap['heightSubtiles']) ?? BoxPrimitive.maxHeightSubtiles,
      originXSubtiles: _int(boxMap['originXSubtiles']) ?? 0,
      originZSubtiles: _int(boxMap['originZSubtiles']) ?? 0,
    ),
    accessibleSides: {
      for (final item in _asList(json['accessibleSides']))
        if (item is String)
          for (final side in VolumeSide.values)
            if (side.name == item) side,
    },
    doorOrigins: {
      for (final entry in _asMap(json['doorOrigins']).entries)
        for (final side in VolumeSide.values)
          if (side.name == entry.key)
            side: _int(entry.value) ?? 0,
    },
  );
}

List<dynamic> _asList(Object? value) => value is List ? value : const [];

Map<String, dynamic> _asMap(Object? value) =>
    value is Map ? value.cast<String, dynamic>() : const <String, dynamic>{};

int? _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return null;
}

double? _double(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return null;
}

VolumeFace? _faceFromName(String? name) {
  if (name == null) return null;
  for (final face in VolumeFace.values) {
    if (face.name == name) return face;
  }
  return null;
}

bool _canvasHasPaint(FaceCanvas canvas) {
  for (final id in canvas.cells) {
    if (id >= 0) return true;
  }
  return false;
}

List<(int, int)> _sortedTiles(Set<(int, int)> tiles) {
  final list = tiles.toList()
    ..sort((a, b) {
      final dx = a.$1.compareTo(b.$1);
      return dx != 0 ? dx : a.$2.compareTo(b.$2);
    });
  return list;
}

List<WallEdge> _sortedWallEdges(Set<WallEdge> edges) {
  final list = edges.toList()
    ..sort((a, b) {
      final c0 = a.x0.compareTo(b.x0);
      if (c0 != 0) return c0;
      final c1 = a.y0.compareTo(b.y0);
      if (c1 != 0) return c1;
      final c2 = a.x1.compareTo(b.x1);
      if (c2 != 0) return c2;
      return a.y1.compareTo(b.y1);
    });
  return list;
}

List<PathEdge> _sortedEdges(Set<PathEdge> edges) {
  final list = edges.toList()
    ..sort((a, b) {
      final c0 = a.x0.compareTo(b.x0);
      if (c0 != 0) return c0;
      final c1 = a.y0.compareTo(b.y0);
      if (c1 != 0) return c1;
      final c2 = a.x1.compareTo(b.x1);
      if (c2 != 0) return c2;
      return a.y1.compareTo(b.y1);
    });
  return list;
}

List<MapEntry<FacePaintKey, FaceCanvas>> _sortedFacePaint(
  Map<FacePaintKey, FaceCanvas> canvases,
) {
  final list = canvases.entries.toList()
    ..sort((a, b) {
      final c0 = a.key.volumeId.compareTo(b.key.volumeId);
      if (c0 != 0) return c0;
      final c1 = a.key.tx.compareTo(b.key.tx);
      if (c1 != 0) return c1;
      final c2 = a.key.ty.compareTo(b.key.ty);
      if (c2 != 0) return c2;
      return a.key.face.index.compareTo(b.key.face.index);
    });
  return list;
}
