import 'dart:ui';
import 'models.dart';
import 'harvest.dart';

enum PaperAction { placement, removal, split }

/// Captured before mutation; animation never reads changing world geometry.
class PaperCompletion {
  PaperCompletion({
    required this.action,
    required this.plane,
    required List<Offset> trace,
    this.paper = const [],
    this.harvest,
    this.placedIds = const {},
    this.affectedIds = const {},
  }) : trace = List.unmodifiable(trace);
  final PaperAction action;
  final CraftPlane plane;
  final List<Offset> trace;
  final List<CraftObject> paper;
  final HarvestResult? harvest;
  final Set<String> placedIds, affectedIds;
}
