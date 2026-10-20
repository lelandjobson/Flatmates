import 'dart:math' as math;

import 'package:flutter/animation.dart' show Curves;
import 'package:flutter/rendering.dart';

import '../gridcraft/folded_model.dart';
import '../papercut/camera.dart';
import 'asmr_mapping.dart';
import 'asmr_model_paper.dart';
import 'asmr_net.dart';
import 'asmr_paper.dart';
import 'asmr_piece.dart';

/// How long a piece takes to fly from the desk onto the model.
const Duration kAsmrFlightDuration = Duration(milliseconds: 450);

/// A piece flying from the desk onto the model. [piece] is already bound,
/// at the pose it will rest at on its net; [from] lays its paper on screen
/// where it left the desk.
class AsmrFlight {
  AsmrFlight({required this.piece, required this.from});

  final AsmrPiece piece;
  final Matrix4 from;
  double t = 0;

  /// Moves the flight on by [seconds]. True once it has landed.
  bool advance(double seconds) {
    t = math.min(1, t + seconds * 1e6 / kAsmrFlightDuration.inMicroseconds);
    return t >= 1;
  }

  double get eased => Curves.easeInOutCubic.transform(t);
}

/// Paper coordinates of [piece] to screen pixels on the desk, where desk
/// point `p` lands at `origin + p * scale`.
Matrix4 deskPaperToScreen(AsmrPiece piece, Offset origin, double scale) =>
    Matrix4.translationValues(origin.dx, origin.dy, 0) *
    Matrix4.diagonal3Values(scale, scale, 1) *
    piece.pose;

/// [a] and [b] mixed at [t]. Each is first scaled so [at] has w = 1, or a
/// perspective end's w would pull the paper away from both ends mid-flight.
Matrix4 lerpHomography(Matrix4 a, Matrix4 b, double t, Offset at) {
  double w(Matrix4 m) {
    final value = m.entry(3, 0) * at.dx + m.entry(3, 1) * at.dy + m.entry(3, 3);
    return value.abs() < 1e-12 ? 1 : value;
  }

  final wa = w(a);
  final wb = w(b);
  final out = Matrix4.zero();
  for (var i = 0; i < 16; i++) {
    out.storage[i] = a.storage[i] / wa * (1 - t) + b.storage[i] / wb * t;
  }
  return out;
}

/// Pieces in flight, over both panes of the split view. Each slice and
/// overhang part eases from the desk to its own face, whose end is worked
/// out every frame so a landing follows the model while it turns.
class AsmrFlightPainter extends CustomPainter {
  const AsmrFlightPainter({
    required this.flights,
    required this.camera,
    required this.model,
    required this.modelSize,
    required this.tiles,
  });

  final List<AsmrFlight> flights;
  final PapercutCamera camera;
  final FoldedModel model;

  /// The model pane's size. Its top left is this canvas's.
  final Size modelSize;
  final AsmrPaperTiles tiles;

  @override
  void paint(Canvas canvas, Size size) {
    for (final flight in flights) {
      final piece = flight.piece;
      final net = piece.binding;
      if (net == null) continue;
      final u = flight.eased;
      final faces = <int, AsmrNetFace>{
        for (final face in net.faces) face.face: face,
      };
      final parts = <(int, List<Offset>, Path)>[
        for (final slice in slicesOf(piece))
          (slice.face, slice.ring, slice.localPath),
        for (final part in overhangOf(piece))
          (part.face, part.ring, part.localPath),
      ];
      for (final (face, ring, path) in parts) {
        final netFace = faces[face];
        if (netFace == null || ring.isEmpty) continue;
        final to = boundPaperToScreen(
          camera: camera,
          size: modelSize,
          model: model,
          netFace: netFace,
          piece: piece,
        );
        var center = Offset.zero;
        for (final p in ring) {
          center += p;
        }
        center = center / ring.length.toDouble();
        final shade = 1 + (faceShade(model, face) - 1) * u;
        canvas.save();
        canvas.transform(lerpHomography(flight.from, to, u, center).storage);
        canvas.drawPath(path, tiles.paint(piece.paper, shade: shade));
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant AsmrFlightPainter old) => true;
}
