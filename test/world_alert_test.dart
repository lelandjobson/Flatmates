import 'package:flatmates/gameplay/alerts/alert_reveal.dart';
import 'package:flatmates/gameplay/alerts/volume_alerts.dart';
import 'package:flatmates/gameplay/alerts/world_alert_layout.dart';
import 'package:flatmates/gameplay/paths/path_store.dart';
import 'package:flatmates/gameplay/volumes/volume.dart';
import 'package:flatmates/gameplay/volumes/volume_program.dart';
import 'package:flatmates/gameplay/volumes/volume_store.dart';
import 'package:flatmates/gameplay/walls/wall_store.dart';
import 'package:flatmates/rendering/scene/camera.dart';
import 'package:flatmates/ui/game/game_tool_carousel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

Volume _mass(List<(int, int)> tiles, {int id = 1}) {
  return Volume(
    id: id,
    cells: [
      for (final (tx, ty) in tiles)
        VolumeCell(tx: tx, ty: ty, box: BoxPrimitive()),
    ],
  );
}

void main() {
  test('centermost tile is the one nearest the mean', () {
    expect(centermostTile([(0, 0), (2, 0), (0, 2), (2, 2), (1, 1)]), (1, 1));
    expect(centermostTile([(3, 1), (3, 2), (4, 1)]), (3, 1));
  });

  test('one sandwich per volume keeps unprogrammed before missing door', () {
    final volumes = VolumeStore();
    final volume = _mass([(2, 2), (3, 2)]);
    volumes.volumes.add(volume);
    final alerts = collectVolumeAlerts(
      volumes: volumes,
      programs: VolumeProgramStore(),
      walls: WallStore(),
      paths: PathStore(grid: volumes.grid),
    );
    expect(alerts, hasLength(1));
    expect(alerts.single.id, 'volume:1');
    expect(alerts.single.issues.map((i) => i.id), [
      'volume:1:unprogrammed',
      'volume:1:noEntry',
    ]);
    expect(alerts.single.primary.requirementIcon, Icons.weekend_outlined);
    expect(alerts.single.primary.remediation.mode, GameMode.select);
    expect(alerts.single.primary.remediation.openProgramPicker, isTrue);
    expect(alerts.single.primary.remediation.tx, 2);
    expect(alerts.single.primary.remediation.ty, 2);
  });

  test('a programmed one-cell volume drops the program alert', () {
    final volumes = VolumeStore();
    final volume = _mass([(2, 2)]);
    volume.cells.single.accessibleSides.add(VolumeSide.east);
    volumes.volumes.add(volume);
    final programs = VolumeProgramStore()
      ..assignIndoor(tx: 2, ty: 2, programId: kProgramBedroom);
    final alerts = collectVolumeAlerts(
      volumes: volumes,
      programs: programs,
      walls: WallStore(),
      paths: PathStore(grid: volumes.grid),
    );
    expect(alerts, isEmpty);
  });

  test('programmed volume without a door raises the path-tool alert', () {
    final volumes = VolumeStore();
    final volume = _mass([(2, 2), (3, 2)]);
    volumes.volumes.add(volume);
    final programs = VolumeProgramStore()
      ..assignIndoor(tx: 2, ty: 2, programId: kProgramBedroom);
    final alerts = collectVolumeAlerts(
      volumes: volumes,
      programs: programs,
      walls: WallStore(),
      paths: PathStore(grid: volumes.grid),
    );
    expect(alerts, hasLength(1));
    expect(alerts.single.issues, hasLength(1));
    expect(alerts.single.primary.id, 'volume:1:noEntry');
    expect(
      alerts.single.primary.requirementIcon,
      Icons.door_front_door_outlined,
    );
    expect(alerts.single.primary.remediation.mode, GameMode.create);
    expect(alerts.single.primary.remediation.createTool, GameCreateTool.path);
  });

  test('isolated bedroom is the last volume alert', () {
    final volumes = VolumeStore();
    final volume = _mass([(2, 2), (3, 2)]);
    volume.cellAt(3, 2)!.accessibleSides.add(VolumeSide.east);
    volumes.volumes.add(volume);
    final programs = VolumeProgramStore()
      ..assignIndoor(tx: 2, ty: 2, programId: kProgramBedroom)
      ..assignIndoor(tx: 3, ty: 2, programId: kProgramLeisure);
    final alerts = collectVolumeAlerts(
      volumes: volumes,
      programs: programs,
      walls: WallStore(),
      paths: PathStore(grid: volumes.grid),
    );
    expect(alerts, hasLength(1));
    expect(alerts.single.primary.id, 'volume:1:bedroomAccess');
    expect(alerts.single.primary.requirementIcon, Icons.bed_outlined);
    expect(alerts.single.primary.remediation.tx, 2);
    expect(alerts.single.primary.remediation.ty, 2);
  });

  test('resolved volumes emit no alerts', () {
    final volumes = VolumeStore();
    final volume = _mass([(2, 2), (3, 2)]);
    volume.cellAt(3, 2)!.accessibleSides.add(VolumeSide.east);
    volumes.volumes.add(volume);
    final programs = VolumeProgramStore()
      ..assignIndoor(tx: 2, ty: 2, programId: kProgramBedroom);
    expect(
      collectVolumeAlerts(
        volumes: volumes,
        programs: programs,
        walls: WallStore(),
        paths: PathStore(grid: volumes.grid),
      ),
      isEmpty,
    );
  });

  test('door candidate prefers a cell an outdoor path already meets', () {
    final volumes = VolumeStore();
    final volume = _mass([(2, 2), (4, 2)]);
    volumes.volumes.add(volume);
    final paths = PathStore(grid: volumes.grid)..placeAndJoin(5, 2);
    expect(
      doorCandidateTile(volume: volume, volumes: volumes, paths: paths),
      (4, 2),
    );
  });

  test('door candidate falls back to the cell nearest a path', () {
    final volumes = VolumeStore();
    final volume = _mass([(2, 2), (3, 2)]);
    volumes.volumes.add(volume);
    final paths = PathStore(grid: volumes.grid)..placeAndJoin(6, 2);
    expect(
      doorCandidateTile(volume: volume, volumes: volumes, paths: paths),
      (3, 2),
    );
  });

  test('visibleWorldAlerts hides in create and when looking inside', () {
    final alert = collectVolumeAlerts(
      volumes: VolumeStore()..volumes.add(_mass([(2, 2)])),
      programs: VolumeProgramStore(),
      walls: WallStore(),
      paths: PathStore(),
    ).single;
    expect(
      visibleWorldAlerts(
        alerts: [alert],
        createMode: true,
        lookingInside: (_) => false,
      ),
      isEmpty,
    );
    expect(
      visibleWorldAlerts(
        alerts: [alert],
        createMode: false,
        lookingInside: (_) => true,
      ),
      isEmpty,
    );
    expect(
      visibleWorldAlerts(
        alerts: [alert],
        createMode: false,
        lookingInside: (_) => false,
      ),
      [alert],
    );
  });

  test('projectToScreenOrEdge clamps off-screen points to the inset', () {
    final camera = Camera(
      name: 'alert-proj',
      position: Vector3(0, 24, 24),
      target: Vector3.zero(),
      fovDegrees: 50,
    );
    const viewport = Size(400, 300);
    const margin = 28.0;
    final on = camera.projectToScreenOrEdge(
      Vector3.zero(),
      viewport,
      margin: margin,
    );
    expect(on, isNotNull);
    expect(on!.onScreen, isTrue);

    final off = camera.projectToScreenOrEdge(
      Vector3(80, 0, 0),
      viewport,
      margin: margin,
    );
    expect(off, isNotNull);
    expect(off!.onScreen, isFalse);
    expect(off.position.dx, inInclusiveRange(margin, 400 - margin));
    expect(off.position.dy, inInclusiveRange(margin, 300 - margin));

    final behind = camera.projectToScreenOrEdge(
      Vector3(0, 40, 40),
      viewport,
      margin: margin,
    );
    expect(behind, isNotNull);
    expect(behind!.onScreen, isFalse);
  });

  test('hitbox is 50% larger than the icon', () {
    expect(worldAlertHitSize(kWorldAlertVisualSize), 48);
    final hit = worldAlertHitRect(
      screen: const Offset(100, 80),
      issueCount: 1,
      expanded: false,
    );
    expect(hit.width, 48);
    expect(hit.height, 48);
    expect(hit.center, const Offset(100, 80));
  });

  test('sandwich stretches for several issues and collapses to a circle', () {
    expect(
      sandwichVisualWidth(issueCount: 2, expanded: false),
      kWorldAlertVisualSize,
    );
    expect(
      sandwichVisualWidth(issueCount: 2, expanded: true),
      kWorldAlertBorder * 2 +
          kWorldAlertPillPad * 2 +
          kWorldAlertVisualSize * 2 +
          kWorldAlertBubbleGap,
    );
    final centers = sandwichBubbleCenters(
      screen: const Offset(0, 0),
      issueCount: 2,
      expanded: true,
    );
    expect(centers, hasLength(2));
    expect(centers[0].dx, lessThan(0));
    expect(centers[1].dx, greaterThan(0));
    expect(
      nearestSandwichBubble(
        pointer: Offset(centers[1].dx, 0),
        centers: centers,
      ),
      1,
    );
  });

  test('waypoints scale to half size at 50 tiles', () {
    expect(
      waypointDistanceScale(
        world: Vector3.zero(),
        lookAt: Vector3.zero(),
        tileSize: 8,
      ),
      1,
    );
    expect(
      waypointDistanceScale(
        world: Vector3(25 * 8, 0, 0),
        lookAt: Vector3.zero(),
        tileSize: 8,
      ),
      0.75,
    );
    expect(
      waypointDistanceScale(
        world: Vector3(50 * 8, 0, 0),
        lookAt: Vector3.zero(),
        tileSize: 8,
      ),
      0.5,
    );
    expect(
      waypointDistanceScale(
        world: Vector3(80 * 8, 0, 0),
        lookAt: Vector3.zero(),
        tileSize: 8,
      ),
      0.5,
    );
  });

  test('pointer expand uses the game cursor, not a widget hover', () {
    expect(
      pointerExpandsAlert(
        pointer: const Offset(100, 80),
        screen: const Offset(100, 80),
        issueCount: 1,
        currentlyExpanded: false,
      ),
      isTrue,
    );
    expect(
      pointerExpandsAlert(
        pointer: const Offset(200, 80),
        screen: const Offset(100, 80),
        issueCount: 1,
        currentlyExpanded: false,
      ),
      isFalse,
    );
  });
}
