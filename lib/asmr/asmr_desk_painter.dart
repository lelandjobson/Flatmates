import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../ui/game/view_crosshair.dart';
import 'asmr_cut_style.dart';
import 'asmr_mapping.dart';
import 'asmr_net.dart';
import 'asmr_paper.dart';
import 'asmr_piece.dart';
import 'asmr_theme.dart';
import 'asmr_turn_dial.dart';

/// The 2D crafting desk, and the last stop of the 3D view's gradient.
const Color kAsmrDeskColor = Color(0xFF14152A);

/// The top of the 3D view's gradient.
const Color kAsmrSkyColor = Color(0xFF2B2D4A);

const Color _kGroove = Color(0xFF2A2440);

/// The desk: paper pieces with their prints, scores, and the cut under way.
/// Desk point `p` lands on screen at `origin + p * scale`, turned clockwise
/// by [angle] about [origin].
class AsmrDeskPainter extends CustomPainter {
  const AsmrDeskPainter({
    required this.pieces,
    required this.tiles,
    required this.origin,
    required this.scale,
    this.angle = 0,
    this.projection,
    this.selectedIds = const {},
    this.hoveredId,
    this.selectedOutline = 0,
    this.flash = const {},
    this.stroke,
    this.reach = const [],
    this.knifeTip,
    this.finger,
    this.rotateHandle,
    this.blueprint,
    this.affixedNets = const {},
    this.blueprintColors = const {},
    this.placementGlow = 0,
    this.placementGroup,
    this.shadowThrow = 10,
    this.shadowSpread = 8,
    this.shadowColor = const Color(0x73000000),
    this.darkOverlay = 0.22,
    this.theme,
    this.ghost = 0,
    this.paintBackground = true,
  });

  final List<AsmrPiece> pieces;
  final AsmrPaperTiles tiles;
  final Offset origin;
  final double scale;
  final double angle;

  /// Desk point to screen, when the cut pitches the view. Null keeps the flat
  /// translate, rotate, and scale.
  final Float64List? projection;
  final Set<String> selectedIds;
  final String? hoveredId;
  final double selectedOutline;

  /// Piece id to 0–1: a white ring flashing round a piece just cut free.
  final Map<String, double> flash;

  /// The exacto cut under way, on the desk.
  final List<Offset>? stroke;

  /// Where the straight cut under way will cut, on the desk.
  final List<List<Offset>> reach;

  /// Where the blade cuts, and the finger holding it, on screen.
  final Offset? knifeTip;
  final Offset? finger;

  /// The selected piece's rotate handle, on screen.
  final Offset? rotateHandle;

  /// The hologram on the desk. Pieces on its outer edge cast [shadowColor].
  final AsmrNet? blueprint;
  final Map<int, AsmrNet> affixedNets;
  final Map<int, Map<String, Color>> blueprintColors;
  final double placementGlow;
  final int? placementGroup;

  /// How far that shadow is offset, in screen pixels, down and a little right.
  final double shadowThrow;

  /// How soft that shadow is, in screen pixels.
  final double shadowSpread;

  /// The shadow's color, alpha included.
  final Color shadowColor;

  /// How much a piece is darkened when it is not on a blueprint edge.
  final double darkOverlay;

  /// Colors for this view. Null keeps the colors the desk was drawn with.
  final AsmrTheme? theme;

  /// 0–1: how far the paper is drawn as dashed outlines instead of filled,
  /// for the desk seen behind the 3D view.
  final double ghost;

  /// Whether the desk color is drawn under the paper. Off when a backdrop
  /// behind this layer draws it.
  final bool paintBackground;

  Color _dye(AsmrThemeSlot slot, Color color) =>
      theme?.ink(slot, color) ?? color;

  @override
  void paint(Canvas canvas, Size size) {
    if (paintBackground) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = theme?.solid(AsmrThemeSlot.desk) ?? kAsmrDeskColor,
      );
    }
    canvas.save();
    // Bound native blur/layer allocation before entering the pitched plane.
    canvas.clipRect(Offset.zero & size);
    final view = projection;
    if (view != null) {
      canvas.transform(view);
    } else {
      canvas.translate(origin.dx, origin.dy);
      canvas.rotate(angle);
      canvas.scale(scale);
    }
    final px = 1 / scale;
    final dashed = ghost.clamp(0.0, 1.0);
    if (dashed < 1) {
      if (dashed > 0) {
        canvas.saveLayer(
          null,
          Paint()..color = Colors.white.withValues(alpha: 1 - dashed),
        );
      }
      _paintPieces(canvas, px);
      if (dashed > 0) canvas.restore();
    }
    if (dashed > 0) _paintGhosts(canvas, px, dashed);

    if (hoveredId != null && ghost < 1) {
      for (final piece in pieces) {
        if (piece.id != hoveredId) continue;
        canvas.save();
        canvas.transform(piece.pose.storage);
        canvas.drawPath(
          piece.localPath,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2 * px
            ..color = _dye(AsmrThemeSlot.selection, const Color(0xB3FFFFFF)),
        );
        canvas.restore();
      }
    }

    for (final line in reach) {
      _paintCutGlow(canvas, line, px);
    }

    final cut = stroke;
    if (cut != null && cut.length >= 2) {
      final path = _polyline(cut);
      _paintPaperCut(canvas, path, px);
    }
    canvas.restore();

    final handle = rotateHandle;
    if (handle != null && selectedOutline > 0) {
      final a = selectedOutline;
      canvas.drawCircle(
        handle,
        13,
        Paint()..color = Colors.black.withValues(alpha: 0.35 * a),
      );
      canvas.drawCircle(
        handle,
        13,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = _dye(
            AsmrThemeSlot.selection,
            Colors.white.withValues(alpha: 0.9 * a),
          ),
      );
      final arc = Rect.fromCircle(center: handle, radius: 6);
      canvas.drawArc(
        arc,
        -2.6,
        4.4,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round
          ..color = _dye(
            AsmrThemeSlot.selection,
            Colors.white.withValues(alpha: 0.9 * a),
          ),
      );
    }

    final tip = knifeTip;
    if (tip != null) paintKnife(canvas, tip, finger, theme: theme);
  }

  void _paintPieces(Canvas canvas, double px) {
    final net = blueprint;
    final hasBlueprint = net != null && !net.isEmpty;
    final onEdge = <String>{
      if (hasBlueprint)
        for (final piece in pieces)
          if (piece.blueprints.isNotEmpty || onBlueprintEdge(piece, net))
            piece.id,
    };
    for (final piece in pieces) {
      if (!onEdge.contains(piece.id)) {
        _paintPiece(canvas, piece, px, contactShadow: true, dim: hasBlueprint);
      }
    }
    for (final piece in pieces) {
      if (!onEdge.contains(piece.id)) continue;
      _paintEdgeShadow(canvas, piece, px);
      _paintPiece(canvas, piece, px, contactShadow: false, dim: false);
    }
  }

  /// Each piece's outline and holes as white dashes, [amount] strong.
  void _paintGhosts(Canvas canvas, double px, double amount) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4 * px
      ..strokeCap = StrokeCap.round
      ..color = _dye(
        AsmrThemeSlot.selection,
        Colors.white.withValues(alpha: 0.8 * amount),
      );
    final dash = 7 * px;
    final gap = 5 * px;
    for (final piece in pieces) {
      canvas.save();
      canvas.transform(piece.pose.storage);
      _paintAffixedBlueprint(canvas, piece, px, opacity: amount);
      canvas.restore();
      for (final ring in [piece.deskRing, ...piece.deskHoles]) {
        if (ring.length < 2) continue;
        final path = Path()..addPolygon(ring, true);
        for (final metric in path.computeMetrics()) {
          var at = 0.0;
          while (at < metric.length) {
            canvas.drawPath(
              metric.extractPath(at, math.min(at + dash, metric.length)),
              paint,
            );
            at += dash + gap;
          }
        }
      }
    }
  }

  /// The exacto's crosshair at [tip], tied to the [finger] holding it.
  static void paintKnife(
    Canvas canvas,
    Offset tip,
    Offset? finger, {
    AsmrTheme? theme,
  }) {
    Color dye(AsmrThemeSlot slot, Color color) =>
        theme?.ink(slot, color) ?? color;
    final hand = finger;
    if (hand != null && (hand - tip).distance > 1) {
      canvas.drawCircle(
        hand,
        22,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = dye(
            AsmrThemeSlot.knife,
            Colors.white.withValues(alpha: 0.25),
          ),
      );
      canvas.drawLine(
        hand + (tip - hand) / (tip - hand).distance * 22,
        tip + (hand - tip) / (hand - tip).distance * 9,
        Paint()
          ..strokeWidth = 1
          ..color = dye(
            AsmrThemeSlot.knife,
            Colors.white.withValues(alpha: 0.25),
          ),
      );
    }
    _crosshair(canvas, tip, theme);
  }

  /// Active cuts and unfinished scores stay white until pieces separate.
  void _paintPaperCut(Canvas canvas, Path path, double px) {
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4 * px
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white.withValues(alpha: 0.6)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2.5 * px),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4 * px
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white,
    );
  }

  /// White preview of the straight cut on the paper it will go through.
  void _paintCutGlow(Canvas canvas, List<Offset> line, double px) {
    if (line.length < 2) return;
    final path = _polyline(line);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10 * px
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white.withValues(alpha: 0.4)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 * px),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.4 * px
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.black.withValues(alpha: 0.4),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6 * px
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white,
    );
  }

  /// Down and a little to the right, the way the shadow is thrown.
  static const Offset _shadowDir = Offset(0.330, 0.944);

  void _paintEdgeShadow(Canvas canvas, AsmrPiece piece, double px) {
    if (shadowColor.a == 0) return;
    final throwPx = shadowThrow.clamp(0.0, 80.0);
    final spreadPx = shadowSpread.clamp(0.0, 80.0);
    canvas.save();
    final cast = _onScreen(_shadowDir * throwPx * px);
    canvas.translate(cast.dx, cast.dy);
    canvas.transform(piece.pose.storage);
    canvas.drawPath(
      piece.localPath,
      Paint()
        ..color = shadowColor
        ..maskFilter = spreadPx > 0.05
            ? MaskFilter.blur(BlurStyle.normal, spreadPx * px)
            : null,
    );
    canvas.restore();
  }

  void _paintPiece(
    Canvas canvas,
    AsmrPiece piece,
    double px, {
    required bool contactShadow,
    required bool dim,
  }) {
    final path = piece.localPath;
    if (piece.liberated && contactShadow) {
      canvas.save();
      final drop = _onScreen(Offset(1.6 * px, 2.8 * px));
      canvas.translate(drop.dx, drop.dy);
      canvas.transform(piece.pose.storage);
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.35)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 * px),
      );
      canvas.restore();
    }
    canvas.save();
    canvas.transform(piece.pose.storage);
    final tone = theme;
    if (tone != null &&
        !tone.plain(AsmrThemeSlot.paper) &&
        piece.paper.pattern == AsmrPattern.plain) {
      canvas.drawPath(
        path,
        Paint()
          ..color = piece.paper.color.withValues(
            alpha: tone.opacityOf(AsmrThemeSlot.paper),
          ),
      );
    } else if (tone != null && !tone.plain(AsmrThemeSlot.paper)) {
      canvas.saveLayer(
        path.getBounds(),
        Paint()
          ..color = Colors.white.withValues(
            alpha: tone.opacityOf(AsmrThemeSlot.paper),
          )
          ..colorFilter = ColorFilter.mode(
            tone.colorOf(AsmrThemeSlot.paper),
            BlendMode.modulate,
          ),
      );
      canvas.drawPath(path, tiles.paint(piece.paper));
      canvas.restore();
    } else {
      canvas.drawPath(path, tiles.paint(piece.paper));
    }
    final shade = darkOverlay.clamp(0.0, 1.0);
    if (dim && shade > 0) {
      canvas.drawPath(
        path,
        Paint()..color = Colors.black.withValues(alpha: shade),
      );
    }
    _paintAffixedBlueprint(canvas, piece, px);
    if (piece.scores.isNotEmpty) {
      canvas.save();
      canvas.clipPath(path);
      // One stroke/blur per piece rather than one per accumulated cut line.
      _paintPaperCut(canvas, piece.scorePath, px);
      canvas.restore();
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = px
        ..color = _dye(AsmrThemeSlot.score, _kGroove.withValues(alpha: 0.45)),
    );
    paintAsmrCutEdges(canvas, piece, px);
    final ring = flash[piece.id] ?? 0;
    if (ring > 0) {
      final flashPath = piece.edgeTone == null ? path : Path();
      if (piece.edgeTone != null) {
        for (final edge in piece.cutEdges) {
          if (edge.length >= 2) flashPath.addPath(_polyline(edge), Offset.zero);
        }
      }
      canvas.drawPath(
        flashPath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (2 + 5 * ring) * px
          ..color =
              (piece.edgeTone == null
                      ? Colors.white
                      : piece.paper.cutEdgeColor(piece.edgeTone!))
                  .withValues(alpha: 0.6 * ring)
          ..maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            (2 * ring + 0.5) * px,
          ),
      );
    }
    if (selectedIds.contains(piece.id) && selectedOutline > 0) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2 * px
          ..color = _dye(
            AsmrThemeSlot.selection,
            Colors.white.withValues(alpha: 0.95 * selectedOutline),
          ),
      );
    }
    canvas.restore();
  }

  /// The blueprint is ink on the paper: clip before drawing each stamp so
  /// holes, cuts and moved fragments keep exactly their portion of the lines.
  void _paintAffixedBlueprint(
    Canvas canvas,
    AsmrPiece piece,
    double px, {
    double opacity = 1,
  }) {
    if (piece.blueprints.isEmpty) return;
    canvas.save();
    canvas.clipPath(piece.localPath);
    final bounds = piece.localPath.getBounds();
    for (final stamp in piece.blueprints) {
      final net = affixedNets[stamp.group];
      if (net == null) continue;
      final bright = _dye(AsmrThemeSlot.hologram, piece.paper.markingColor);
      final pulse = stamp.group == placementGroup
          ? math.sin(math.pi * placementGlow)
          : 0.0;
      if (pulse > 0) {
        for (final face in net.faces) {
          canvas.drawPath(
            Path()
              ..addPolygon([for (final p in face.ring) stamp.toPaper(p)], true),
            Paint()..color = bright.withValues(alpha: 0.18 * pulse * opacity),
          );
        }
      }
      for (final edge in net.edges) {
        final a = stamp.toPaper(edge.a), b = stamp.toPaper(edge.b);
        if (!Rect.fromPoints(
          a,
          b,
        ).inflate((4 + 8 * pulse) * px).overlaps(bounds)) {
          continue;
        }
        if ((b - a).distanceSquared < 1e-16) continue;
        final ink = blueprintColors[stamp.group]?[edge.key] ?? bright;
        final path = Path()
          ..moveTo(a.dx, a.dy)
          ..lineTo(b.dx, b.dy);
        if (edge.fold) {
          final paint = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2 * px
            ..color = ink.withValues(alpha: 0.65 * opacity);
          for (final metric in path.computeMetrics()) {
            for (var at = 0.0; at < metric.length; at += 8 * px) {
              canvas.drawPath(
                metric.extractPath(at, math.min(at + 4 * px, metric.length)),
                paint,
              );
            }
          }
        } else {
          canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = (3 + 6 * pulse) * px
              ..maskFilter = MaskFilter.blur(
                BlurStyle.normal,
                (1 + 3 * pulse) * px,
              )
              ..color = ink.withValues(alpha: (0.25 + 0.4 * pulse) * opacity),
          );
          canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.7 * px
              ..strokeCap = StrokeCap.round
              ..color = ink.withValues(alpha: ink.a * opacity),
          );
        }
      }
    }
    canvas.restore();
  }

  /// A screen-space offset as a desk offset, so shadows fall down the
  /// screen however the desk is turned.
  Offset _onScreen(Offset v) {
    if (angle == 0) return v;
    final c = math.cos(angle);
    final s = math.sin(angle);
    return Offset(c * v.dx + s * v.dy, -s * v.dx + c * v.dy);
  }

  static void _crosshair(Canvas canvas, Offset at, AsmrTheme? theme) {
    Color dye(AsmrThemeSlot slot, Color color) =>
        theme?.ink(slot, color) ?? color;
    for (final (width, color) in [
      (3.2, Colors.black.withValues(alpha: 0.45)),
      (1.4, dye(AsmrThemeSlot.knife, Colors.white)),
    ]) {
      final paint = Paint()
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..color = color;
      const gap = 3.0;
      const reach = 9.0;
      canvas.drawLine(
        at + const Offset(-reach, 0),
        at + const Offset(-gap, 0),
        paint,
      );
      canvas.drawLine(
        at + const Offset(gap, 0),
        at + const Offset(reach, 0),
        paint,
      );
      canvas.drawLine(
        at + const Offset(0, -reach),
        at + const Offset(0, -gap),
        paint,
      );
      canvas.drawLine(
        at + const Offset(0, gap),
        at + const Offset(0, reach),
        paint,
      );
    }
    canvas.drawCircle(at, 1.3, Paint()..color = Colors.white);
  }

  static Path _polyline(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    return path;
  }

  @override
  bool shouldRepaint(covariant AsmrDeskPainter old) => true;
}

/// The exacto's crosshair on its own layer, over the straight edge.
class AsmrKnifePainter extends CustomPainter {
  const AsmrKnifePainter({required this.tip, this.finger, this.theme});

  final Offset tip;
  final Offset? finger;
  final AsmrTheme? theme;

  @override
  void paint(Canvas canvas, Size size) =>
      AsmrDeskPainter.paintKnife(canvas, tip, finger, theme: theme);

  @override
  bool shouldRepaint(covariant AsmrKnifePainter old) =>
      old.tip != tip ||
      old.finger != finger ||
      old.theme?.stamp != theme?.stamp;
}

/// The scissors' blade on screen: a line from where the cut starts, [from],
/// up to the blade's tip, [to], drawn faint. [mark] is how far the drag under
/// way will cut, drawn over the blade in red. [dial] is the turn bar below
/// the blade, and its circle is the reticle's, [knob] pixels from the middle.
class AsmrScissorsPainter extends CustomPainter {
  const AsmrScissorsPainter({
    required this.from,
    required this.to,
    this.mark,
    this.circle,
    this.aiming = false,
    this.controlsOpacity = 1,
    this.aimPoints = const [],
    this.stuck = false,
    this.dial,
    this.knob = 0,
    this.dialHeld = false,
    this.cruise = false,
    this.theme,
  });

  final Offset from;
  final Offset to;
  final AsmrTurnDial? dial;
  final double knob;
  final bool dialHeld;
  final bool cruise;
  final AsmrTheme? theme;

  Color _dye(AsmrThemeSlot slot, Color color) =>
      theme?.ink(slot, color) ?? color;

  /// Where the drag under way stops on the blade, on screen.
  final Offset? mark;

  /// Screen position of the circle, including the camera advance after a cut.
  final Offset? circle;
  final bool aiming;

  /// Blade and rotation bar visibility while the camera finishes lining up.
  /// The circle and any live cut preview retain their own opacity.
  final double controlsOpacity;
  final List<Offset> aimPoints;
  final bool stuck;

  static const _cut = Color(0xFFE5484D);
  static const _reticle = 0.3;

  @override
  void paint(Canvas canvas, Size size) {
    if (aiming) {
      final at = circle ?? from;
      final red = _dye(AsmrThemeSlot.scissorsMark, _cut);
      for (final point in aimPoints) {
        canvas.drawLine(
          at,
          point,
          Paint()
            ..color = red.withValues(alpha: red.a * 0.4)
            ..strokeWidth = 1,
        );
        canvas.drawCircle(
          point,
          5,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = red,
        );
      }
      paintReticleCircle(
        canvas,
        at,
        _dye(AsmrThemeSlot.reticle, const Color(0xF2FFFFFF)),
      );
      return;
    }
    canvas.saveLayer(
      Offset.zero & size,
      Paint()
        ..color = Color.fromRGBO(255, 255, 255, _reticle * controlsOpacity),
    );
    canvas.drawLine(
      from,
      to,
      Paint()
        ..color = _dye(AsmrThemeSlot.scissors, const Color(0x55000000))
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      from,
      to,
      Paint()
        ..color = _dye(AsmrThemeSlot.scissors, const Color(0xE6FFFFFF))
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      to,
      3,
      Paint()..color = _dye(AsmrThemeSlot.scissors, const Color(0xE6FFFFFF)),
    );
    canvas.restore();

    final end = mark;
    if (end != null && (end - from).distance >= 0.5) {
      canvas.drawLine(
        from,
        end,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.4)
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
      );
      canvas.drawLine(
        from,
        end,
        Paint()
          ..color = Colors.white
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round,
      );
    }
    final handle = dial;
    if (handle == null) return;
    final gripInk = _dye(AsmrThemeSlot.turnGrip, const Color(0xE6FFFFFF));
    handle.paint(
      canvas,
      cruise: cruise,
      ink: gripInk.withValues(alpha: gripInk.a * controlsOpacity),
    );
    paintReticleCircle(
      canvas,
      circle ?? end ?? handle.center + Offset(knob, 0),
      stuck
          ? _dye(AsmrThemeSlot.scissorsMark, _cut)
          : _dye(AsmrThemeSlot.reticle, const Color(0xF2FFFFFF)),
    );
  }

  @override
  bool shouldRepaint(AsmrScissorsPainter old) =>
      old.from != from ||
      old.to != to ||
      old.mark != mark ||
      old.circle != circle ||
      old.aiming != aiming ||
      old.controlsOpacity != controlsOpacity ||
      old.aimPoints != aimPoints ||
      old.stuck != stuck ||
      old.dial?.center != dial?.center ||
      old.dial?.halfLength != dial?.halfLength ||
      old.knob != knob ||
      old.dialHeld != dialHeld ||
      old.cruise != cruise ||
      old.theme?.stamp != theme?.stamp;
}
