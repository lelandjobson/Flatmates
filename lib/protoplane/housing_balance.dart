/// Initial playable-loop tuning. Paper units represent sixteenths of a tile.
class HousingBalance {
  static const unitsPerTile = 16;
  static const starterBuilding = 32, starterCloth = 8;
  static const packSize = 16, buildingPrice = 20, clothPrice = 12;
  static const emergencyBuilding = 16, emergencyCloth = 8;
  static const baseRating = 40,
      largeBonus = 20,
      windowBonus = 20,
      spaceBonus = 20;
  static const spacePerResident = .5;
  static const safeRating = 60;
  static int rent(int rating) => 4 + rating ~/ 20;
  static double departure(int rating) =>
      rating >= safeRating ? 0 : (safeRating - rating) / 100;
}
