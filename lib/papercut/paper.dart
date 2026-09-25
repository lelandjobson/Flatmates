import 'dart:math' as math;
import 'dart:ui';

import 'models.dart';

/// One piece of a sheet after zero or more cuts. Coordinates are millimeters.
class PapercutPiece {
  const PapercutPiece({
    required this.id,
    required this.color,
    required this.vertices,
    this.holes = const [],
  });

  final String id;
  final Color color;
  final List<Offset> vertices;
  final List<List<Offset>> holes;

  PapercutPiece clone() {
    return PapercutPiece(
      id: id,
      color: color,
      vertices: List<Offset>.from(vertices),
      holes: [for (final hole in holes) List<Offset>.from(hole)],
    );
  }
}

/// A straight-edge crease. It is drawn, not folded into a mesh.
class PapercutCrease {
  const PapercutCrease({
    required this.id,
    required this.a,
    required this.b,
    required this.groupId,
    required this.angleDegrees,
  });

  final String id;
  final Offset a;
  final Offset b;
  final String groupId;
  final double angleDegrees;
}

class PapercutSheet {
  const PapercutSheet({
    required this.pieces,
    this.cutStrokes = const [],
    this.creases = const [],
    this.nextPieceId = 1,
  });

  factory PapercutSheet.square({required Color color}) {
    final half = kPapercutSheetMm / 2;
    return PapercutSheet(
      pieces: [
        PapercutPiece(
          id: 'sheet-0',
          color: color,
          vertices: [
            Offset(-half, -half),
            Offset(half, -half),
            Offset(half, half),
            Offset(-half, half),
          ],
        ),
      ],
    );
  }

  factory PapercutSheet.empty() => const PapercutSheet(pieces: []);

  final List<PapercutPiece> pieces;
  final List<List<Offset>> cutStrokes;
  final List<PapercutCrease> creases;
  final int nextPieceId;

  PapercutSheet clone() {
    return PapercutSheet(
      pieces: [for (final piece in pieces) piece.clone()],
      cutStrokes: [for (final stroke in cutStrokes) List<Offset>.from(stroke)],
      creases: List<PapercutCrease>.from(creases),
      nextPieceId: nextPieceId,
    );
  }
}

/// Moving-average smooth, used on exacto strokes before they are unprojected.
List<Offset> smoothOffsets(List<Offset> raw, {int window = 4}) {
  if (raw.length < 3 || window <= 0) return List<Offset>.from(raw);
  final smoothed = <Offset>[];
  for (var i = 0; i < raw.length; i++) {
    var sum = Offset.zero;
    var count = 0;
    final start = math.max(0, i - window);
    final end = math.min(raw.length - 1, i + window);
    for (var j = start; j <= end; j++) {
      sum += raw[j];
      count++;
    }
    smoothed.add(sum / count.toDouble());
  }
  return smoothed;
}

List<Offset> resampleOffsets(List<Offset> points, double spacing) {
  if (points.length < 2 || spacing <= 0) return List<Offset>.from(points);
  final out = <Offset>[points.first];
  var anchor = points.first;
  var remain = spacing;
  for (var i = 1; i < points.length; i++) {
    var from = anchor;
    final end = points[i];
    var dist = (end - from).distance;
    while (dist + 1e-6 >= remain && dist > 1e-6) {
      final t = remain / dist;
      final point = Offset(
        from.dx + (end.dx - from.dx) * t,
        from.dy + (end.dy - from.dy) * t,
      );
      out.add(point);
      from = point;
      dist = (end - from).distance;
      remain = spacing;
    }
    remain -= dist;
    anchor = end;
  }
  if ((out.last - points.last).distance > spacing * 0.25) {
    out.add(points.last);
  }
  return out;
}
