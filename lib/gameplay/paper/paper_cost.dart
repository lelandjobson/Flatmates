import '../paths/path_shape.dart';
import '../paths/path_store.dart';
import '../volumes/volume.dart';
import '../volumes/volume_solid.dart';

/// One paper sheet covers a 4×4 subtile square.
const int kPaperSheetSubtiles = 16;

const int kStartingPaper = 200;

/// Sheets required for [area] subtile². Zero area is free; any leftover
/// fragment still costs a full sheet.
int papersForArea(int area) {
  if (area <= 0) return 0;
  return (area + kPaperSheetSubtiles - 1) ~/ kPaperSheetSubtiles;
}

/// Remaining exterior solid fragment area, including floor and roof.
///
/// [VolumeSolid] only keeps roof + walls. Floor is the cell footprints,
/// which never swallow each other.
int volumeExteriorArea(Volume volume, VolumeGrid grid) {
  final solid = resolveVolumeSolid(volume, grid);
  var area = 0;
  for (final surface in solid.surfaces) {
    for (final fragment in surface.fragments) {
      area += fragment.area;
    }
  }
  for (final cell in volume.cells) {
    area += cell.box.widthSubtiles * cell.box.depthSubtiles;
  }
  return area;
}

int volumePaperCost(Volume volume, VolumeGrid grid) =>
    papersForArea(volumeExteriorArea(volume, grid));

/// User path footprint area only (no derived door stubs).
int userPathFootprintArea(
  PathStore paths, {
  int subtilesPerTile = VolumeGrid.defaultSubtilesPerTile,
}) {
  var area = 0;
  for (final (tx, ty) in paths.tiles) {
    for (final piece in pathFootprints(
      paths.neighborMask(tx, ty),
      subtilesPerTile: subtilesPerTile,
    )) {
      area += piece.widthSubtiles * piece.depthSubtiles;
    }
  }
  return area;
}

int pathPaperCost(
  PathStore paths, {
  int subtilesPerTile = VolumeGrid.defaultSubtilesPerTile,
}) =>
    papersForArea(
      userPathFootprintArea(paths, subtilesPerTile: subtilesPerTile),
    );

int wallPaperCost(int edgeCount) => edgeCount;
