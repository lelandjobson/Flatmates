import 'package:flutter/material.dart';

import '../volumes/volume_program.dart';

enum StuffAnchor { floor, wall }

const kStuffBed = 'bed';
const kStuffDesk = 'desk';
const kStuffLamp = 'lamp';
const kStuffChair = 'chair';
const kStuffCrate = 'crate';
const kStuffShelf = 'shelf';

const kStuffPlaneEpsilon = 0.06;
const kStuffHullPad = 0.28;
const kStuffHullMin = 0.55;
const kStuffAnchorSlab = 0.12;
const kStuffSevereAnchor = 0.28;

class StuffSpec {
  const StuffSpec({
    required this.id,
    required this.label,
    required this.icon,
    required this.programIds,
    required this.anchor,
    required this.paperCost,
    this.hullPad = kStuffHullPad,
    this.hullMin = kStuffHullMin,
  });

  final String id;
  final String label;
  final IconData icon;
  final List<String> programIds;
  final StuffAnchor anchor;
  final int paperCost;
  final double hullPad;
  final double hullMin;

  bool get isFloor => anchor == StuffAnchor.floor;
  bool get isWall => anchor == StuffAnchor.wall;
}

const List<StuffSpec> kStuffCatalog = [
  StuffSpec(
    id: kStuffBed,
    label: 'Bed',
    icon: Icons.bed_outlined,
    programIds: [kProgramBedroom],
    anchor: StuffAnchor.floor,
    paperCost: 3,
  ),
  StuffSpec(
    id: kStuffDesk,
    label: 'Desk',
    icon: Icons.desk_outlined,
    programIds: [kProgramBedroom],
    anchor: StuffAnchor.floor,
    paperCost: 2,
  ),
  StuffSpec(
    id: kStuffLamp,
    label: 'Lamp',
    icon: Icons.lightbulb_outline,
    programIds: [kProgramBedroom, kProgramLeisure],
    anchor: StuffAnchor.floor,
    paperCost: 1,
  ),
  StuffSpec(
    id: kStuffChair,
    label: 'Chair',
    icon: Icons.chair_outlined,
    programIds: [kProgramLeisure],
    anchor: StuffAnchor.floor,
    paperCost: 1,
  ),
  StuffSpec(
    id: kStuffCrate,
    label: 'Crate',
    icon: Icons.inventory_2_outlined,
    programIds: [kProgramStorage],
    anchor: StuffAnchor.floor,
    paperCost: 1,
  ),
  StuffSpec(
    id: kStuffShelf,
    label: 'Shelf',
    icon: Icons.shelves,
    programIds: [kProgramStorage],
    anchor: StuffAnchor.wall,
    paperCost: 2,
  ),
];

StuffSpec? stuffById(String id) {
  for (final spec in kStuffCatalog) {
    if (spec.id == id) return spec;
  }
  return null;
}

List<StuffSpec> stuffForProgram(String programId) {
  return [
    for (final spec in kStuffCatalog)
      if (spec.programIds.contains(programId)) spec,
  ];
}
