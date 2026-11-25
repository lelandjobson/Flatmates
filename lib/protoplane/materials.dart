import 'dart:ui';

enum PaperMaterial {
  paperWhite('paper.white', 'White', Color(0xfff7f5ef)),
  graphite('paper.graphite', 'Graphite', Color(0xff383838)),
  cork('paper.cork', 'Cork', Color(0xffa58a64)),
  paperGreen('paper.green', 'Green', Color(0xffb3d294));

  const PaperMaterial(this.id, this.label, this.base);
  final String id, label;
  final Color base;
  bool get craftable => this == paperWhite || this == paperGreen;
  int get starterUnits => this == paperWhite ? 256 : 0;
  static PaperMaterial decode(String id) => values.firstWhere(
    (m) => m.id == id,
    orElse: () => throw FormatException('Unknown paper material: $id'),
  );
}

const paperMaterials = PaperMaterial.values;
// Source compatibility for authored fixtures; saves use stable material IDs.
typedef PaperColor = PaperMaterial;
