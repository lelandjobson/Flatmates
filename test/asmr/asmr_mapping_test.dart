import 'dart:ui';

import 'package:flatmates/asmr/asmr_cube.dart';
import 'package:flatmates/asmr/asmr_mapping.dart';
import 'package:flatmates/asmr/asmr_net.dart';
import 'package:flatmates/asmr/asmr_paper.dart';
import 'package:flatmates/asmr/asmr_piece.dart';
import 'package:flatmates/geometry/polygon_union.dart';
import 'package:flatmates/gridcraft/wrap_cut.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

void main() {
  final model = asmrCubeModel();
  final adjacency = faceAdjacency(model);
  final single = unfoldSelection(model, adjacency, [const HologramPick(2)]);

  AsmrPiece bound(Size size, {Offset at = Offset.zero, AsmrNet? net}) =>
      AsmrPiece.sheet(
        id: 'p',
        paper: kAsmrPapers.first,
        at: at,
        size: size,
      ).copyWith(liberated: true, binding: net ?? single);

  test('paper over a one-face hologram fills that face only', () {
    final coverage = faceCoverage(model, [bound(const Size(52, 52))]);
    expect(coverage[2], 1);
    for (final entry in coverage.entries) {
      if (entry.key != 2) expect(entry.value, 0);
    }
  });

  test('half a face is half covered', () {
    final coverage = faceCoverage(model, [
      bound(const Size(25, 60), at: const Offset(-12.5, 0)),
    ]);
    expect(coverage[2], closeTo(0.5, 0.05));
  });

  test('unbound paper covers nothing', () {
    final piece = AsmrPiece.sheet(
      id: 'p',
      paper: kAsmrPapers.first,
      at: Offset.zero,
      size: const Size(60, 60),
    );
    expect(faceCoverage(model, [piece]).values.every((v) => v == 0), isTrue);
  });

  test('paper past the net hangs off the face it touches', () {
    final piece = bound(const Size(50, 80), at: const Offset(0, 15));
    final overhang = overhangOf(piece);
    expect(overhang, hasLength(1));
    expect(overhang.single.face, 2);
    expect(polygonSignedArea(overhang.single.ring).abs(), closeTo(50 * 30, 1));
    expect(identical(overhangOf(piece), overhang), isTrue);
  });

  test('a two-face net leaves the rest of a big sheet as overhang', () {
    final b = adjacency[2].first!.face;
    final pair = unfoldSelection(model, adjacency, [
      const HologramPick(2),
      HologramPick(b, from: 2),
    ]);
    final piece = bound(const Size(140, 140), net: pair);
    final overhang = overhangOf(piece);
    var area = 0.0;
    for (final part in overhang) {
      area += polygonSignedArea(part.ring).abs();
      for (final hole in part.holes) {
        area -= polygonSignedArea(hole).abs();
      }
      expect({2, b}, contains(part.face));
    }
    expect(area, closeTo(140 * 140 - 2 * 2500, 1));
    expect(faceCoverage(model, [piece])[b], 1);
  });

  test('a sheet across two faces is sliced along the fold', () {
    final b = adjacency[2].first!.face;
    final pair = unfoldSelection(model, adjacency, [
      const HologramPick(2),
      HologramPick(b, from: 2),
    ]);
    final piece = bound(const Size(140, 140), net: pair);
    final slices = slicesOf(piece);
    expect(slices.map((s) => s.face).toSet(), {2, b});
    expect(identical(slicesOf(piece), slices), isTrue);
    for (final slice in slices) {
      var area = polygonSignedArea(slice.ring).abs();
      for (final hole in slice.holes) {
        area -= polygonSignedArea(hole).abs();
      }
      expect(area, closeTo(2500, 1));
    }

    Vector3 world(AsmrSlice slice, Offset local) {
      final face = pair.of(slice.face)!;
      return model.faces[slice.face].world(
        applyAffine(face.netToFace, piece.toDesk(local)),
      );
    }

    bool sameEdge(Offset a0, Offset a1, Offset b0, Offset b1) {
      final a = world(slices[0], a0);
      final b = world(slices[0], a1);
      final c = world(slices[1], b0);
      final d = world(slices[1], b1);
      final forward = (a - c).length < 1e-4 && (b - d).length < 1e-4;
      final back = (a - d).length < 1e-4 && (b - c).length < 1e-4;
      return forward || back;
    }

    final ring0 = slices[0].ring;
    final ring1 = slices[1].ring;
    var shared = false;
    for (var i = 0; i < ring0.length && !shared; i++) {
      for (var j = 0; j < ring1.length && !shared; j++) {
        shared = sameEdge(
          ring0[i],
          ring0[(i + 1) % ring0.length],
          ring1[j],
          ring1[(j + 1) % ring1.length],
        );
      }
    }
    expect(shared, isTrue);
  });

  test('paper inside the net has no overhang', () {
    expect(overhangOf(bound(const Size(40, 40))), isEmpty);
  });

  test('paper off its net shows no overhang', () {
    expect(overhangOf(bound(const Size(20, 20), at: const Offset(200, 0))), isEmpty);
  });

  test('only paper on the blueprint edge counts as touching it', () {
    final wide = single.bounds.width;
    final tall = single.bounds.height;
    final inside = AsmrPiece.sheet(
      id: 'in',
      paper: kAsmrPapers.first,
      at: Offset.zero,
      size: Size(wide * 0.4, tall * 0.4),
    );
    final covering = AsmrPiece.sheet(
      id: 'over',
      paper: kAsmrPapers.first,
      at: Offset.zero,
      size: Size(wide + 8, tall + 8),
    );
    final along = AsmrPiece.sheet(
      id: 'along',
      paper: kAsmrPapers.first,
      at: Offset(single.bounds.right + 10, 0),
      size: const Size(20, 20),
    );
    final aside = AsmrPiece.sheet(
      id: 'off',
      paper: kAsmrPapers.first,
      at: Offset(wide + 80, 0),
      size: const Size(20, 20),
    );
    expect(onBlueprintEdge(inside, single), isFalse);
    expect(onBlueprintEdge(covering, single), isTrue);
    expect(onBlueprintEdge(along, single), isTrue);
    expect(onBlueprintEdge(aside, single), isFalse);
    expect(onBlueprintEdge(covering, AsmrNet.empty), isFalse);
  });

  test('a piece overlaps the hologram only where it covers a face', () {
    expect(overlapsNet(bound(const Size(10, 10)), single), isTrue);
    expect(
      overlapsNet(bound(const Size(10, 10), at: const Offset(100, 0)), single),
      isFalse,
    );
  });
}
