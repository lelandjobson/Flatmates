import 'dart:convert';
import 'dart:io';

import 'package:flatmates/gridcraft/blueprint.dart';
import 'package:flatmates/gridcraft/cube_craft.dart';
import 'package:flatmates/gridcraft/folded_model.dart';
import 'package:flatmates/papercut/craft_v1.dart';
import 'package:flatmates/papercut/fold_pose.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

CraftV1 _craft(String id) {
  final raw = File('assets/craft_viewer/$id/craft.json').readAsStringSync();
  return CraftV1.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}

GridStep _level(String path) {
  final raw = File(path).readAsStringSync();
  return GridBlueprint.fromJson(
    jsonDecode(raw) as Map<String, dynamic>,
  ).steps.single;
}

void _expectMatrix(Matrix4 actual, Matrix4 expected) {
  for (var i = 0; i < 16; i++) {
    expect(actual.storage[i], closeTo(expected.storage[i], 1e-6));
  }
}

void main() {
  test('the craft_Cube asset is what the generator writes', () {
    expect(
      File('$kCubeCraftDirectory/craft.json').readAsStringSync(),
      cubeCraftJsonText(),
    );
    expect(
      File('$kCubeCraftDirectory/folded.obj').readAsStringSync(),
      cubeCraftObj(),
    );
  });

  test('craft_Cube folds into a closed 5x5x5 box standing on its hub', () {
    final craft = _craft(kCubeCraftId);
    final poses = applyFoldPose(craft, 1, 1);
    final corners = <Vector3>[];
    for (final face in craft.faces) {
      final loop = face.flatLoops.first;
      final points = [
        for (final point in loop.sublist(0, loop.length - 1))
          poses[face.id]!.transformed3(point),
      ];
      corners.addAll(points);
      final zs = points.map((point) => point.z);
      if (face.foldParentSurfaceId == null) {
        expect(zs.every((z) => z.abs() < 1e-9), isTrue, reason: face.id);
      } else {
        expect(zs.reduce((a, b) => a > b ? a : b), greaterThan(0));
      }
    }
    double span(double Function(Vector3) axis) {
      final values = corners.map(axis).toList()..sort();
      return values.last - values.first;
    }

    expect(span((p) => p.x), closeTo(5, 1e-9));
    expect(span((p) => p.y), closeTo(5, 1e-9));
    expect(span((p) => p.z), closeTo(5, 1e-9));

    final centers = <String>{};
    for (final face in craft.faces) {
      final loop = face.flatLoops.first;
      final sum = Vector3.zero();
      for (final point in loop.sublist(0, loop.length - 1)) {
        sum.add(poses[face.id]!.transformed3(point));
      }
      sum.scale(1 / 4);
      centers.add(
        '${sum.x.toStringAsFixed(3)},${sum.y.toStringAsFixed(3)},'
        '${sum.z.toStringAsFixed(3)}',
      );
    }
    expect(centers, hasLength(6));
  });

  test('the cube model keeps the hub on its blueprint square', () {
    final level = _level('levels/cube/cube.json');
    expect(level.craft?.id, kCubeCraftId);
    expect(level.craft?.step, 1);
    final model = foldedModelFromCraft(_craft(kCubeCraftId), 1, level)!;
    expect(model.faces, hasLength(6));
    expect(model.islands, hasLength(1));
    expect(model.hinges, hasLength(5));
    for (var i = 0; i < model.faces.length; i++) {
      expect(model.faces[i].outline, level.polygons[model.faces[i].ring]);
    }
    final hub = model.faceOfRing(0)!;
    expect(model.islands.single.first, hub);
    _expectMatrix(model.faces[hub].toWorld, Matrix4.identity());
    expect(model.outwardNormal(hub).z, closeTo(-1, 1e-9));
    expect(model.center.z, closeTo(2.5, 1e-9));
  });

  test('wrapPose is flat at 0 and folded at 1', () {
    final level = _level('levels/cube/cube.json');
    final model = foldedModelFromCraft(_craft(kCubeCraftId), 1, level)!;
    final back = model.faceOfRing(3)!;
    final flat = wrapPose(model, back, 0);
    final folded = wrapPose(model, back, 1);
    expect(flat.keys.toSet(), model.islands.single.toSet());
    for (final entry in flat.entries) {
      _expectMatrix(entry.value, model.faces[back].toWorld);
      _expectMatrix(folded[entry.key]!, model.faces[entry.key].toWorld);
    }
    final rising = wrapPose(
      model,
      model.faceOfRing(0)!,
      0,
      from: Matrix4.identity(),
    );
    for (final pose in rising.values) {
      _expectMatrix(pose, Matrix4.identity());
    }
  });

  test('the side table maps every craft face onto its level', () {
    final craft = _craft('craft_Nightstand');
    const levels = {
      1: 'levels/side-table/1-legs.json',
      2: 'levels/side-table/2-tabletop.json',
      3: 'levels/side-table/3-shelf.json',
      4: 'levels/side-table/4-knob.json',
    };
    const faceCounts = {1: 20, 2: 6, 3: 5, 4: 6};
    for (final entry in levels.entries) {
      final level = _level(entry.value);
      expect(level.craft?.id, 'craft_Nightstand');
      expect(level.craft?.step, entry.key);
      final model = foldedModelFromCraft(craft, entry.key, level)!;
      expect(
        model.faces,
        hasLength(faceCounts[entry.key]),
        reason: entry.value,
      );
      final closed = [
        for (var i = 0; i < level.polygons.length; i++)
          if (level.isRingClosed(i)) i,
      ];
      expect(model.islands, hasLength(closed.length), reason: entry.value);
      for (final island in model.islands) {
        final rings = {for (final face in island) model.faces[face].ring};
        expect(rings, hasLength(1), reason: entry.value);
        expect(closed, contains(rings.single));
      }
      expect(model.bounds.min.z, greaterThan(-1e-6));
      for (final island in model.islands) {
        final poses = wrapPose(model, island.first, 1);
        for (final face in island) {
          _expectMatrix(poses[face]!, model.faces[face].toWorld);
        }
      }
    }
  });

  test('pickFace hits the nearest face', () {
    final level = _level('levels/cube/cube.json');
    final model = foldedModelFromCraft(_craft(kCubeCraftId), 1, level)!;
    final down = pickFace(model, Vector3(7.5, 7.5, 50), Vector3(0, 0, -1))!;
    expect(model.faces[down.face].ring, 3);
    expect(down.distance, closeTo(45, 1e-9));
    final up = pickFace(model, Vector3(7.5, 7.5, -50), Vector3(0, 0, 1))!;
    expect(model.faces[up.face].ring, 0);
    expect(pickFace(model, Vector3(40, 40, 50), Vector3(0, 0, -1)), isNull);
  });

  test('stepIslands joins pieces across shared penciled edges', () {
    final cube = _level('levels/cube/cube.json');
    expect(stepIslands(cube), [
      {0, 1, 2, 3, 4, 5},
    ]);
  });
}
