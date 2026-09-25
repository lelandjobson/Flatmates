import 'dart:math' as math;
import 'dart:ui';

import '../geometry/polygon_union.dart';
import 'paper.dart';

/// Splits every piece the stroke crosses. Returns null when the stroke misses.
PapercutSheet? applyPapercutCut(PapercutSheet sheet, List<Offset> stroke) {
  final cleaned = _cleanStroke(stroke);
  if (cleaned.length < 2) return null;

  final nextPieces = <PapercutPiece>[];
  var hit = false;
  var nextId = sheet.nextPieceId;
  for (final piece in sheet.pieces) {
    final clipped = _clipStroke(cleaned, piece);
    if (clipped.isEmpty) {
      nextPieces.add(piece);
      continue;
    }
    hit = true;
    final faces = _solidFaces(piece, clipped);
    if (faces.length <= 1) {
      nextPieces.add(piece);
      continue;
    }
    final built = _piecesFromFaces(faces, piece, nextId);
    nextId += built.length;
    nextPieces.addAll(built);
  }
  if (!hit) return null;
  return PapercutSheet(
    pieces: nextPieces,
    cutStrokes: [...sheet.cutStrokes, cleaned],
    creases: sheet.creases,
    nextPieceId: nextId,
  );
}

/// Stores a crease where the straight edge crosses paper. Does not deform it.
PapercutSheet? applyPapercutCrease(
  PapercutSheet sheet, {
  required Offset a,
  required Offset b,
  required String groupId,
  required double angleDegrees,
}) {
  if ((b - a).distance < 1) return null;
  final points = <Offset>[];
  for (final piece in sheet.pieces) {
    for (final segment in _clipStroke([a, b], piece)) {
      points.add(segment.$1);
      points.add(segment.$2);
    }
  }
  if (points.length < 2) return null;
  final span = _extremeSpan(a, b, points);
  final crease = PapercutCrease(
    id: 'crease-${sheet.creases.length}',
    a: span.$1,
    b: span.$2,
    groupId: groupId,
    angleDegrees: angleDegrees,
  );
  return PapercutSheet(
    pieces: sheet.pieces,
    cutStrokes: sheet.cutStrokes,
    creases: [...sheet.creases, crease],
    nextPieceId: sheet.nextPieceId,
  );
}

List<Offset> _cleanStroke(List<Offset> stroke) {
  final cleaned = <Offset>[];
  for (final point in stroke) {
    if (cleaned.isEmpty || (cleaned.last - point).distance > 0.2) {
      cleaned.add(point);
    }
  }
  return cleaned;
}

List<(Offset, Offset)> _clipStroke(List<Offset> stroke, PapercutPiece piece) {
  final clipped = <(Offset, Offset)>[];
  for (var i = 0; i < stroke.length - 1; i++) {
    clipped.addAll(_clipSegment(stroke[i], stroke[i + 1], piece));
  }
  return clipped;
}

List<(Offset, Offset)> _clipSegment(Offset a, Offset b, PapercutPiece piece) {
  final dx = b.dx - a.dx;
  final dy = b.dy - a.dy;
  if (dx * dx + dy * dy < 1e-8) return const [];

  final parameters = <double>[0, 1];
  void addRing(List<Offset> ring) {
    for (var i = 0; i < ring.length; i++) {
      final t = _segmentParameter(a, b, ring[i], ring[(i + 1) % ring.length]);
      if (t != null) parameters.add(t);
    }
  }

  addRing(piece.vertices);
  for (final hole in piece.holes) {
    addRing(hole);
  }
  parameters.sort();

  final result = <(Offset, Offset)>[];
  for (var i = 0; i < parameters.length - 1; i++) {
    final t0 = parameters[i];
    final t1 = parameters[i + 1];
    if (t1 - t0 < 1e-5) continue;
    final mid = (t0 + t1) / 2;
    if (mid < 0 || mid > 1) continue;
    final probe = Offset(a.dx + dx * mid, a.dy + dy * mid);
    if (!_inSolid(probe, piece)) continue;
    final c0 = t0.clamp(0.0, 1.0);
    final c1 = t1.clamp(0.0, 1.0);
    if (c1 - c0 < 1e-5) continue;
    result.add((
      Offset(a.dx + dx * c0, a.dy + dy * c0),
      Offset(a.dx + dx * c1, a.dy + dy * c1),
    ));
  }
  return result;
}

/// Parameter of the intersection along [a]→[b], or null if the segments miss.
double? _segmentParameter(Offset a, Offset b, Offset p, Offset q) {
  final dxa = b.dx - a.dx;
  final dya = b.dy - a.dy;
  final dxb = q.dx - p.dx;
  final dyb = q.dy - p.dy;
  final denom = dxa * dyb - dya * dxb;
  if (denom.abs() < planarEpsilon) return null;
  final wx = a.dx - p.dx;
  final wy = a.dy - p.dy;
  final t = (dxb * wy - dyb * wx) / denom;
  final u = (dxa * wy - dya * wx) / denom;
  if (t < -planarEpsilon || t > 1 + planarEpsilon) return null;
  if (u < -planarEpsilon || u > 1 + planarEpsilon) return null;
  return t;
}

bool _inSolid(Offset point, PapercutPiece piece) {
  if (!isInsidePolygon(point, piece.vertices)) return false;
  for (final hole in piece.holes) {
    if (isInsidePolygon(point, hole)) return false;
  }
  return true;
}

List<List<Offset>> _solidFaces(
  PapercutPiece piece,
  List<(Offset, Offset)> cuts,
) {
  final segments = <(Offset, Offset)>[];
  void addRing(List<Offset> ring) {
    for (var i = 0; i < ring.length; i++) {
      final next = ring[(i + 1) % ring.length];
      if ((ring[i] - next).distance < 1e-4) continue;
      segments.add((ring[i], next));
    }
  }

  addRing(piece.vertices);
  for (final hole in piece.holes) {
    addRing(hole);
  }
  segments.addAll(cuts);

  final faces = PlanarGraph(splitAllAtIntersections(segments)).findFaces();
  final solid = <List<Offset>>[];
  for (final face in faces) {
    if (face.length < 3) continue;
    if (polygonSignedArea(face).abs() < 1) continue;
    final sample = _faceInteriorPoint(face);
    if (!isInsidePolygon(sample, face)) continue;
    if (!_inSolid(sample, piece)) continue;
    if (_isDuplicate(solid, face)) continue;
    solid.add(face);
  }
  return solid;
}

bool _isDuplicate(List<List<Offset>> faces, List<Offset> face) {
  final centroid = polygonCentroid(face);
  final area = polygonSignedArea(face).abs();
  for (final other in faces) {
    final sameSpot = (polygonCentroid(other) - centroid).distance < 0.5;
    final sameArea = (polygonSignedArea(other).abs() - area).abs() < 1;
    if (sameSpot && sameArea) return true;
  }
  return false;
}

/// Point just to the right of the first usable edge. Rightmost-turn faces
/// keep their interior on the right, even when the centroid falls in a bite.
Offset _faceInteriorPoint(List<Offset> face) {
  const offset = 0.05;
  for (var i = 0; i < face.length; i++) {
    final a = face[i];
    final b = face[(i + 1) % face.length];
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final len2 = dx * dx + dy * dy;
    if (len2 < 1e-8) continue;
    final inv = offset / math.sqrt(len2);
    return Offset((a.dx + b.dx) / 2 + dy * inv, (a.dy + b.dy) / 2 - dx * inv);
  }
  return polygonCentroid(face);
}

List<PapercutPiece> _piecesFromFaces(
  List<List<Offset>> faces,
  PapercutPiece source,
  int idStart,
) {
  final areas = [for (final face in faces) polygonSignedArea(face).abs()];
  final container = List<int?>.filled(faces.length, null);
  for (var i = 0; i < faces.length; i++) {
    final centroid = polygonCentroid(faces[i]);
    var bestArea = double.infinity;
    for (var j = 0; j < faces.length; j++) {
      if (i == j || areas[j] <= areas[i] * 1.02) continue;
      if (!isInsidePolygon(centroid, faces[j])) continue;
      if (areas[j] < bestArea) {
        bestArea = areas[j];
        container[i] = j;
      }
    }
  }

  final holes = List.generate(faces.length, (_) => <List<Offset>>[]);
  for (var i = 0; i < faces.length; i++) {
    final parent = container[i];
    if (parent != null) holes[parent].add(faces[i]);
  }

  return [
    for (var i = 0; i < faces.length; i++)
      PapercutPiece(
        id: '${source.id}-${idStart + i}',
        color: source.color,
        vertices: faces[i],
        holes: holes[i],
      ),
  ];
}

(Offset, Offset) _extremeSpan(Offset a, Offset b, List<Offset> points) {
  final dir = b - a;
  final len2 = dir.dx * dir.dx + dir.dy * dir.dy;
  var minT = double.infinity;
  var maxT = -double.infinity;
  for (final point in points) {
    final t = ((point.dx - a.dx) * dir.dx + (point.dy - a.dy) * dir.dy) / len2;
    if (t < minT) minT = t;
    if (t > maxT) maxT = t;
  }
  return (
    Offset(a.dx + dir.dx * minT, a.dy + dir.dy * minT),
    Offset(a.dx + dir.dx * maxT, a.dy + dir.dy * maxT),
  );
}
