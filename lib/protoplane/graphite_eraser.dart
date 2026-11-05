import 'dart:typed_data';
import 'dart:ui';
import 'geometry.dart';
import 'models.dart' show rectangle;

/// Sparse tiles contain one 256-bit depletion mask; no cell entities are saved.
class GraphiteMask {
  static const divisions = 16;
  static const count = divisions * divisions;
  static const byteCount = count ~/ 8;
  static const radius = .055;
  GraphiteMask([Uint8List? data]) : bytes = data ?? Uint8List(byteCount);
  final Uint8List bytes;
  bool removed(int index) => bytes[index >> 3] & (1 << (index & 7)) != 0;
  void remove(int index) => bytes[index >> 3] |= 1 << (index & 7);
  static Rect cell(int index) => Rect.fromLTWH(
    (index % divisions) / divisions,
    (index ~/ divisions) / divisions,
    1 / divisions,
    1 / divisions,
  );

  /// Coalesce equal horizontal spans vertically. At most 128 rectangles even
  /// for a checkerboard, and a completely erased tile produces no survivors.
  List<Rect> rectangles({bool erased = false}) {
    final result = <Rect>[];
    var previous = <(int, int), int>{};
    for (var y = 0; y < divisions; y++) {
      final next = <(int, int), int>{};
      var x = 0;
      while (x < divisions) {
        if (removed(y * divisions + x) != erased) {
          x++;
          continue;
        }
        final start = x;
        while (x < divisions && removed(y * divisions + x) == erased) {
          x++;
        }
        final key = (start, x), old = previous[(start, x)];
        if (old != null) {
          final r = result[old];
          result[old] = Rect.fromLTRB(
            r.left,
            r.top,
            r.right,
            (y + 1) / divisions,
          );
          next[key] = old;
        } else {
          next[key] = result.length;
          result.add(
            Rect.fromLTRB(
              start / divisions,
              y / divisions,
              x / divisions,
              (y + 1) / divisions,
            ),
          );
        }
      }
      previous = next;
    }
    return result;
  }
}

Region rectRegion(Rect rect) =>
    rectangle(rect.width, rect.height, origin: rect.topLeft);
List<Region> intersectRegions(List<Region> regions, Region clip) => [
  for (final r in regions)
    if (r.bounds.overlaps(clip.bounds))
      for (final cell in slabs([
        r,
        clip,
      ], (p) => r.contains(p) && clip.contains(p)))
        if (Region(cell).area > geometryEpsilon) Region(cell),
];

/// Transient gesture data. Areas are precomputed once, not per pointer event.
class GraphiteBrush {
  GraphiteBrush(
    List<Region> remaining,
    List<Region> exposed,
    List<Region> blocked,
  ) {
    for (var i = 0; i < GraphiteMask.count; i++) {
      final square = rectRegion(GraphiteMask.cell(i));
      final actual = intersectRegions(remaining, square);
      final area = actual.fold<double>(0, (a, r) => a + r.area);
      if (area < geometryEpsilon) continue;
      final visible = intersectRegions(
        exposed,
        square,
      ).fold<double>(0, (a, r) => a + r.area);
      if ((visible - area).abs() > geometryEpsilon ||
          blocked.any((r) => actual.any(r.overlaps))) {
        continue;
      }
      areas[i] = area;
      if ((area - square.area).abs() > geometryEpsilon) fragments[i] = actual;
    }
  }
  final areas = Float64List(GraphiteMask.count);
  final Map<int, List<Region>> fragments = {};
  List<Region> regions(int i) =>
      fragments[i] ?? [rectRegion(GraphiteMask.cell(i))];
  Iterable<int> touched(
    Offset from,
    Offset to, {
    double radius = GraphiteMask.radius,
  }) sync* {
    final bounds = Rect.fromPoints(from, to).inflate(radius);
    final n = GraphiteMask.divisions;
    final x0 = (bounds.left * n).floor().clamp(0, n - 1),
        x1 = (bounds.right * n).floor().clamp(0, n - 1);
    final y0 = (bounds.top * n).floor().clamp(0, n - 1),
        y1 = (bounds.bottom * n).floor().clamp(0, n - 1);
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        final i = y * n + x;
        if (areas[i] > 0 && _sweeps(from, to, GraphiteMask.cell(i), radius)) {
          yield i;
        }
      }
    }
  }
}

// A swept disk intersects a rectangle when the center segment intersects it,
// or the minimum segment/edge distance is within the brush radius. Segment
// contacts reuse the project's Boost-referenced Cartesian intersection code.
bool _sweeps(Offset a, Offset b, Rect r, double radius) {
  if (r.contains(a) || r.contains(b)) return true;
  final corners = [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft];
  double distance2(Offset p, Offset a, Offset b) {
    final d = b - a;
    final t = d.distanceSquared == 0
        ? 0.0
        : (((p - a).dx * d.dx + (p - a).dy * d.dy) / d.distanceSquared).clamp(
            0.0,
            1.0,
          );
    return (p - (a + d * t)).distanceSquared;
  }

  for (var i = 0; i < 4; i++) {
    final c = corners[i], d = corners[(i + 1) % 4];
    if (segmentsTouch(a, b, c, d) ||
        distance2(c, a, b) <= radius * radius ||
        distance2(a, c, d) <= radius * radius ||
        distance2(b, c, d) <= radius * radius) {
      return true;
    }
  }
  return false;
}
