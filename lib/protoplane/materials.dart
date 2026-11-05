import 'dart:ui';

enum WorldPreset { paper, ink, pastel }

enum PaperPattern { solid, dots, diagonalLines }

enum PaperMaterial {
  red('pastel.red', 'Coral', WorldPreset.pastel, Color(0xffe8a19b)),
  yellow('pastel.yellow', 'Butter', WorldPreset.pastel, Color(0xffe9d88d)),
  green('pastel.green', 'Sage', WorldPreset.pastel, Color(0xffa4c8ac)),
  blue('pastel.blue', 'Mist', WorldPreset.pastel, Color(0xffa4c5d4)),
  sand('pastel.sand', 'Sand', WorldPreset.pastel, Color(0xffcfbfa5)),
  white('ink.white', 'White', WorldPreset.ink, Color(0xfff4f1e8)),
  black('ink.black', 'Black', WorldPreset.ink, Color(0xff202020)),
  dots(
    'ink.dots',
    'Dots',
    WorldPreset.ink,
    Color(0xfff4f1e8),
    PaperPattern.dots,
  ),
  lines(
    'ink.lines',
    'Lines',
    WorldPreset.ink,
    Color(0xfff4f1e8),
    PaperPattern.diagonalLines,
  ),
  inkRed('ink.red', 'Red', WorldPreset.ink, Color(0xffc84a36)),
  inkBlue('ink.blue', 'Blue', WorldPreset.ink, Color(0xff3155a6)),
  paperWhite('paper.white', 'White', WorldPreset.paper, Color(0xfff7f5ef)),
  graphite('paper.graphite', 'Graphite', WorldPreset.paper, Color(0xff383838)),
  cork('paper.cork', 'Cork', WorldPreset.paper, Color(0xffa58a64));

  const PaperMaterial(
    this.id,
    this.label,
    this.preset,
    this.base, [
    this.pattern = PaperPattern.solid,
  ]);
  final String id, label;
  final WorldPreset preset;
  final Color base;
  final PaperPattern pattern;
  Color get ink => const Color(0xff202020);
  bool get patterned => pattern != PaperPattern.solid;
  bool get craftable => this != graphite && this != cork;
  int get starterUnits =>
      !craftable || this == inkRed || this == inkBlue ? 0 : 256;
  static PaperMaterial decode(String id) => values.firstWhere(
    (m) => m.id == id || (m.preset == WorldPreset.pastel && m.name == id),
    orElse: () => throw FormatException('Unknown paper material: $id'),
  );
}

const pastelMaterials = [
  PaperMaterial.red,
  PaperMaterial.yellow,
  PaperMaterial.green,
  PaperMaterial.blue,
  PaperMaterial.sand,
];
const inkMaterials = [
  PaperMaterial.white,
  PaperMaterial.black,
  PaperMaterial.dots,
  PaperMaterial.lines,
  PaperMaterial.inkRed,
  PaperMaterial.inkBlue,
];

const paperMaterials = [
  PaperMaterial.paperWhite,
  PaperMaterial.graphite,
  PaperMaterial.cork,
];

extension WorldPresetMaterials on WorldPreset {
  List<PaperMaterial> get materials => this == WorldPreset.paper
      ? paperMaterials
      : this == WorldPreset.ink
      ? inkMaterials
      : pastelMaterials;
  String get fileName => this == WorldPreset.paper
      ? 'world-paper.json'
      : this == WorldPreset.ink
      ? 'world-ink.json'
      : 'world.json';
  String get label => this == WorldPreset.paper
      ? 'Paper'
      : this == WorldPreset.ink
      ? 'Ink'
      : 'Pastel';
}

// Source compatibility for existing authored fixtures; saves use material IDs.
typedef PaperColor = PaperMaterial;
