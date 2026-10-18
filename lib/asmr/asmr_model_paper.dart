import 'dart:typed_data';

import 'package:flutter/animation.dart' show Curves;
import 'package:flutter/painting.dart';
import 'package:vector_math/vector_math_64.dart';

import '../gridcraft/folded_model.dart';
import '../gridcraft/model_painter.dart' show kPreselectColor;
import '../papercut/camera.dart';
import 'asmr_mapping.dart';
import 'asmr_paper.dart';
import 'asmr_piece.dart';

/// Added to a slice's view depth so it paints over the face it lies on
/// without leaving the face's plane. A lift would open a crack at the fold.
const double _kPaperDepthBias = 0.05;

final Vector3 _kLight = Vector3(-0.35, -0.5, 0.8).normalized();
const double _kShadeDark = 0.72;

/// Adds every bound piece to the model's back-to-front list, through
/// `ModelPainter.sheets`. A piece that crosses a fold is already sliced along
/// it, and each slice is drawn in its own face's plane, so the two sides meet
/// on the fold. Overhang sticks out flat from the face it hangs off.
/// [highlight] fills faces with the preselect color under their paper, so the
/// paper keeps its own color. [tint] lays a color, alpha included, over a
/// face under the highlight.
void addBoundPaper({
  required Canvas canvas,
  required Size size,
  required PapercutCamera camera,
  required FoldedModel model,
  required Iterable<AsmrPiece> pieces,
  required AsmrPaperTiles tiles,
  required void Function(double depth, VoidCallback paint) add,
  Map<int, double> highlight = const {},
  Map<int, Color> tint = const {},
}) {
  final view = camera.camera.viewMatrix;
  final screen = _screenFromWorld(camera, size);
  final eyeNear = camera.camera.near;
  for (final entry in tint.entries) {
    final face = model.faces[entry.key];
    final ring = face.worldRing();
    if (!_inFront(view, ring, eyeNear)) continue;
    final Matrix4 faceToScreen = screen * face.toWorld;
    add(_depth(view, ring) + 3e-7, () {
      canvas.save();
      canvas.transform(_flat(faceToScreen));
      canvas.drawPath(
        Path()..addPolygon(face.outline, true),
        Paint()..color = entry.value,
      );
      canvas.restore();
    });
  }
  for (final entry in highlight.entries) {
    final t = Curves.easeOut.transform(entry.value.clamp(0.0, 1.0));
    if (t <= 0) continue;
    final face = model.faces[entry.key];
    final ring = face.worldRing();
    if (!_inFront(view, ring, eyeNear)) continue;
    final Matrix4 faceToScreen = screen * face.toWorld;
    add(_depth(view, ring) + 5e-7, () {
      canvas.save();
      canvas.transform(_flat(faceToScreen));
      canvas.drawPath(
        Path()..addPolygon(face.outline, true),
        Paint()..color = kPreselectColor.withValues(alpha: 0.34 * t),
      );
      canvas.restore();
    });
  }
  var order = 0;
  for (final piece in pieces) {
    final net = piece.binding;
    if (net == null) continue;
    final overhang = overhangOf(piece);
    final slices = slicesOf(piece);
    for (final netFace in net.faces) {
      final f = netFace.face;
      final face = model.faces[f];
      final Matrix4 faceToScreen = screen * face.toWorld;
      final Matrix4 paperToFace = netFace.netToFace * piece.pose;
      final paint = tiles.paint(
        piece.paper,
        shade: _shade(model.outwardNormal(f)),
      );
      final tie = ++order * 1e-6;
      List<Vector3> worldOf(List<Offset> loop) => [
        for (final p in loop)
          face.toWorld.transformed3(paperToFace.transformed3(_vec(p))),
      ];
      for (final slice in slices) {
        if (slice.face != f) continue;
        final corners = worldOf(slice.ring);
        if (!_inFront(view, corners, eyeNear)) continue;
        add(_depth(view, corners) + _kPaperDepthBias + tie, () {
          canvas.save();
          canvas.transform(_flat(faceToScreen));
          canvas.transform(paperToFace.storage);
          canvas.drawPath(slice.localPath, paint);
          canvas.restore();
        });
      }
      for (final part in overhang) {
        if (part.face != f) continue;
        final corners = worldOf(part.ring);
        if (!_inFront(view, corners, eyeNear)) continue;
        add(_depth(view, corners) + _kPaperDepthBias + tie, () {
          canvas.save();
          canvas.transform(_flat(faceToScreen));
          canvas.transform(paperToFace.storage);
          canvas.drawPath(part.localPath, paint);
          canvas.restore();
        });
      }
    }
  }
}

Vector3 _vec(Offset p) => Vector3(p.dx, p.dy, 0);

double _shade(Vector3 normal) {
  final lambert = normal.normalized().dot(_kLight);
  return _kShadeDark + (1 - _kShadeDark) * (lambert + 1) / 2;
}

/// World space to screen pixels, with perspective.
Matrix4 _screenFromWorld(PapercutCamera camera, Size size) {
  final viewport = Matrix4.identity()
    ..setEntry(0, 0, size.width / 2)
    ..setEntry(0, 3, size.width / 2)
    ..setEntry(1, 1, -size.height / 2)
    ..setEntry(1, 3, size.height / 2);
  return viewport * camera.camera.viewProjectionMatrix(size);
}

/// [m] for a canvas: points come in with z = 0 and depth is not kept, so the
/// z row and column pass straight through. What is left is the plane's
/// homography.
Float64List _flat(Matrix4 m) {
  final s = Float64List.fromList(m.storage);
  s[2] = 0;
  s[6] = 0;
  s[14] = 0;
  s[8] = 0;
  s[9] = 0;
  s[10] = 1;
  s[11] = 0;
  return s;
}

bool _inFront(Matrix4 view, List<Vector3> points, double near) {
  for (final p in points) {
    if (-view.transformed3(p).z <= near) return false;
  }
  return true;
}

double _depth(Matrix4 view, List<Vector3> ring) {
  var sum = 0.0;
  for (final p in ring) {
    sum += view.transformed3(p).z;
  }
  return ring.isEmpty ? 0 : sum / ring.length;
}
