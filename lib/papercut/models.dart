import 'dart:ui';

import 'package:vector_math/vector_math_64.dart';

import '../crafting/crafting_material.dart';

/// Millimeters per craft cell. Papercut only; the crafting canvas is untouched.
const double kPapercutMmPerCell = 25;

/// An 8×8 sheet in millimeters (one cell is [kPapercutMmPerCell]).
double get kPapercutSheetMm =>
    CraftingMaterial.paperSizeCells * kPapercutMmPerCell;

const Color kPapercutPink = Color(0xFFFFB3BA);
const Color kPapercutYellow = Color(0xFFFFF3B0);
const Color kPapercutGreen = Color(0xFFBAFFC9);
const Color kPapercutBackground = Color(0xFF1A1A2E);
const Color kPapercutGuide = Color(0xFF9E9E9E);
const Color kPapercutFold = Color(0xFF90A4AE);
const Color kPapercutCut = Color(0xFF000000);
const Color kPapercutScissorAllowed = Color(0xFF66BB6A);
const Color kPapercutScissorDenied = Color(0xFFE53935);
const Color kPapercutRuler = Color(0xFFFFD54F);

/// A curve on a blueprint step is either a cut perimeter or a fold.
enum PapercutCurveRole { cut, fold }

/// One flat face of a craft step: an outer ring and optional holes, in millimeters.
class PapercutNet {
  const PapercutNet({required this.outer, this.holes = const []});

  final List<Offset> outer;
  final List<List<Offset>> holes;
}

/// Closed cut perimeters and open or closed fold guides, in millimeters.
class PapercutCurve {
  const PapercutCurve({
    required this.id,
    required this.role,
    required this.points,
    this.closed = true,
    this.foldGroup,
    this.foldAngleDegrees = 90,
  });

  final String id;
  final PapercutCurveRole role;
  final List<Offset> points;
  final bool closed;

  /// Folds that share a group are meant to turn together later.
  final String? foldGroup;

  /// Degrees about the fold line. Positive turns toward the camera.
  final double foldAngleDegrees;
}

/// Goal kinds. Only [cutPerimeters] is scored today.
enum PapercutGoalType { cutPerimeters }

class PapercutGoal {
  const PapercutGoal(this.type);

  final PapercutGoalType type;

  static const cutPerimeters = PapercutGoal(PapercutGoalType.cutPerimeters);
}

sealed class PapercutGeometry {
  const PapercutGeometry();

  String get id;
}

/// Curve step. [hasSheet] attaches an 8×8 paper sheet; the step is not the sheet.
class PapercutCurveGeometry extends PapercutGeometry {
  const PapercutCurveGeometry({
    required this.id,
    required this.curves,
    this.hasSheet = true,
    this.nets = const [],
  });

  @override
  final String id;
  final List<PapercutCurve> curves;
  final bool hasSheet;

  /// Starting paper when a craft step brings its own net. Empty uses the square sheet.
  final List<PapercutNet> nets;

  Iterable<PapercutCurve> get cutCurves => curves.where(
    (curve) => curve.role == PapercutCurveRole.cut && curve.closed,
  );

  Iterable<PapercutCurve> get foldCurves =>
      curves.where((curve) => curve.role == PapercutCurveRole.fold);
}

/// Mesh step. Same id style as a curve that has already been folded.
class PapercutMeshGeometry extends PapercutGeometry {
  PapercutMeshGeometry({
    required this.id,
    required this.triangles,
    Vector3? targetEulerDegrees,
  }) : targetEulerDegrees = targetEulerDegrees ?? Vector3.zero();

  @override
  final String id;

  /// Triangle vertices in millimeters. Z is toward the camera.
  final List<List<Vector3>> triangles;

  /// Optional target orientation in degrees (pitch, yaw, roll).
  final Vector3 targetEulerDegrees;
}

class PapercutStep {
  const PapercutStep({
    required this.id,
    required this.label,
    required this.geometry,
    required this.goals,
    this.paperColor = kPapercutPink,
  });

  final String id;
  final String label;
  final PapercutGeometry geometry;
  final List<PapercutGoal> goals;
  final Color paperColor;

  bool get wantsCutPerimeters =>
      goals.any((goal) => goal.type == PapercutGoalType.cutPerimeters);
}

class PapercutBlueprint {
  const PapercutBlueprint({
    required this.id,
    required this.name,
    required this.steps,
  });

  final String id;
  final String name;
  final List<PapercutStep> steps;
}
