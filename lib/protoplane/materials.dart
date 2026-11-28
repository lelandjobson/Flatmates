import 'dart:ui';
import 'housing_balance.dart';

enum MaterialContext { indoor, outdoor }

enum MaterialUse { indoor, outdoor, both }

enum PaperMaterial {
  paperWhite('paper.white', 'White', Color(0xfff7f5ef)),
  graphite('paper.graphite', 'Graphite', Color(0xff383838)),
  cork('paper.cork', 'Cork', Color(0xffa58a64)),
  paperGreen('paper.green', 'Green', Color(0xffb3d294));

  const PaperMaterial(this.id, this.label, this.base);
  final String id, label;
  final Color base;
  bool get craftable => this == paperWhite || this == paperGreen;
  int get starterUnits => this == paperWhite
      ? HousingBalance.starterBuilding
      : this == paperGreen
      ? HousingBalance.starterCloth
      : 0;
  int get purchasePrice => this == paperGreen
      ? HousingBalance.clothPrice
      : HousingBalance.buildingPrice;
  MaterialUse get use => this == paperWhite
      ? MaterialUse.outdoor
      : this == paperGreen
      ? MaterialUse.indoor
      : MaterialUse.both;
  bool allows(MaterialContext context) =>
      use == MaterialUse.both || use.name == context.name;
  static PaperMaterial decode(String id) => values.firstWhere(
    (m) => m.id == id,
    orElse: () => throw FormatException('Unknown paper material: $id'),
  );
}

const paperMaterials = PaperMaterial.values;
// Source compatibility for authored fixtures; saves use stable material IDs.
typedef PaperColor = PaperMaterial;
