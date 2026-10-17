import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import 'papercraft_net.dart';

const String kPapercraftLevelDirectory = 'levels/papercraft';

String papercraftDirectory(PapercraftDesign design) =>
    'assets/craft_viewer/${design.craftId}';

String papercraftLevelPath(PapercraftDesign design) =>
    '$kPapercraftLevelDirectory/${design.puzzleId}.json';

/// Every design in the papercraft collection.
List<PapercraftDesign> papercraftDesigns() => [
  rocketDesign(),
  birdhouseDesign(),
  coffeeCupDesign(),
];

Vector3 _p(num x, num y, num z) =>
    Vector3(x.toDouble(), y.toDouble(), z.toDouble());

/// A quarter turn about the vertical through the origin, [turns] times.
Vector3 _turn(Vector3 p, int turns) {
  var x = p.x;
  var y = p.y;
  for (var i = 0; i < turns; i++) {
    (x, y) = (-y, x);
  }
  return Vector3(x, y, p.z);
}

NetFace _turned(String name, List<Vector3> corners, int turns) =>
    NetFace(name, [for (final p in corners) _turn(p, turns)]);

const _sides = ['south', 'east', 'north', 'west'];

/// A square body with a pyramid nose, a flared skirt, and two fins: five
/// polyhedra in four islands. Each side wall is split around the fin it
/// carries so the fin's edges meet whole wall edges.
PapercraftDesign rocketDesign() {
  final lift = math.sqrt(3);
  Vector3 p(num x, num y, num z) => _p(x, y, z + lift);
  final apex = p(2, 2, 6 + math.sqrt(12));
  const frame = {
    'side': [(0, 0), (1, 1), (1, 5), (0, 6)],
    'bottom': [(0, 0), (4, 0), (3, 1), (1, 1)],
    'far side': [(4, 0), (4, 6), (3, 5), (3, 1)],
    'top': [(0, 6), (1, 5), (3, 5), (4, 6)],
  };
  List<NetFace> wall(String side, num x) => [
    for (final entry in frame.entries)
      NetFace('$side wall ${entry.key}', [
        for (final (y, z) in entry.value) p(x, y, z),
      ]),
  ];

  final east = wall('east', 4);
  final west = wall('west', 0);
  bool far(NetFace face) => face.name.endsWith('far side');
  final front = NetIsland(
    root: 'south wall',
    faces: [
      NetFace('south wall', [p(0, 0, 0), p(4, 0, 0), p(4, 0, 6), p(0, 0, 6)]),
      ...east.where((face) => !far(face)),
      ...west.where((face) => !far(face)),
      NetFace('nose south', [p(0, 0, 6), p(4, 0, 6), apex]),
      NetFace('nose east', [p(4, 0, 6), p(4, 4, 6), apex]),
      NetFace('nose west', [p(0, 4, 6), p(0, 0, 6), apex]),
    ],
    parents: const {
      'east wall side': 'south wall',
      'east wall bottom': 'east wall side',
      'east wall top': 'east wall side',
      'west wall side': 'south wall',
      'west wall bottom': 'west wall side',
      'west wall top': 'west wall side',
      'nose south': 'south wall',
      'nose east': 'east wall top',
      'nose west': 'west wall top',
    },
  );
  final back = NetIsland(
    root: 'north wall',
    faces: [
      NetFace('north wall', [p(4, 4, 0), p(0, 4, 0), p(0, 4, 6), p(4, 4, 6)]),
      ...east.where(far),
      ...west.where(far),
      NetFace('nose north', [p(4, 4, 6), p(0, 4, 6), apex]),
    ],
    parents: const {
      'east wall far side': 'north wall',
      'west wall far side': 'north wall',
      'nose north': 'north wall',
    },
  );

  final low = -lift;
  final skirt = NetIsland(
    root: 'skirt base',
    faces: [
      NetFace('skirt base', [
        p(-1, -1, low),
        p(5, -1, low),
        p(5, 5, low),
        p(-1, 5, low),
      ]),
      NetFace('skirt south', [
        p(-1, -1, low),
        p(5, -1, low),
        p(4, 0, 0),
        p(0, 0, 0),
      ]),
      NetFace('skirt east', [
        p(5, -1, low),
        p(5, 5, low),
        p(4, 4, 0),
        p(4, 0, 0),
      ]),
      NetFace('skirt north', [
        p(5, 5, low),
        p(-1, 5, low),
        p(0, 4, 0),
        p(4, 4, 0),
      ]),
      NetFace('skirt west', [
        p(-1, 5, low),
        p(-1, -1, low),
        p(0, 0, 0),
        p(0, 4, 0),
      ]),
    ],
    parents: const {
      'skirt south': 'skirt base',
      'skirt east': 'skirt base',
      'skirt north': 'skirt base',
      'skirt west': 'skirt base',
    },
  );

  NetIsland fin(String side, num wall, num tip) => NetIsland(
    root: '$side fin base',
    faces: [
      NetFace('$side fin base', [
        p(wall, 1, 1),
        p(tip, 1, 1),
        p(tip, 3, 1),
        p(wall, 3, 1),
      ]),
      NetFace('$side fin front', [p(wall, 1, 1), p(tip, 1, 1), p(wall, 1, 5)]),
      NetFace('$side fin back', [p(wall, 3, 1), p(tip, 3, 1), p(wall, 3, 5)]),
      NetFace('$side fin edge', [
        p(tip, 1, 1),
        p(tip, 3, 1),
        p(wall, 3, 5),
        p(wall, 1, 5),
      ]),
    ],
    parents: {
      '$side fin front': '$side fin base',
      '$side fin back': '$side fin base',
      '$side fin edge': '$side fin base',
    },
  );

  return PapercraftDesign(
    craftId: 'craft_Rocket',
    layer: 'Rocket',
    puzzleId: 'rocket',
    name: 'Rocket',
    islands: [front, back, skirt, fin('east', 4, 7), fin('west', 0, -3)],
  );
}

/// A gabled house on a base, with a perch under its door and a solar panel
/// on its roof: four polyhedra in four islands. The base top, the house
/// front, and the east roof are each split around what stands on them.
PapercraftDesign birdhouseDesign() {
  final base = NetIsland(
    root: 'base bottom',
    faces: [
      NetFace('base bottom', [
        _p(0, 0, 0),
        _p(8, 0, 0),
        _p(8, 10, 0),
        _p(0, 10, 0),
      ]),
      NetFace('base south', [
        _p(0, 0, 0),
        _p(8, 0, 0),
        _p(8, 0, 1),
        _p(0, 0, 1),
      ]),
      NetFace('base east', [
        _p(8, 0, 0),
        _p(8, 10, 0),
        _p(8, 10, 1),
        _p(8, 0, 1),
      ]),
      NetFace('base north', [
        _p(8, 10, 0),
        _p(0, 10, 0),
        _p(0, 10, 1),
        _p(8, 10, 1),
      ]),
      NetFace('base west', [
        _p(0, 10, 0),
        _p(0, 0, 0),
        _p(0, 0, 1),
        _p(0, 10, 1),
      ]),
      NetFace('base top south', [
        _p(0, 0, 1),
        _p(8, 0, 1),
        _p(7, 1, 1),
        _p(1, 1, 1),
      ]),
      NetFace('base top east', [
        _p(8, 0, 1),
        _p(8, 10, 1),
        _p(7, 9, 1),
        _p(7, 1, 1),
      ]),
      NetFace('base top north', [
        _p(8, 10, 1),
        _p(0, 10, 1),
        _p(1, 9, 1),
        _p(7, 9, 1),
      ]),
      NetFace('base top west', [
        _p(0, 10, 1),
        _p(0, 0, 1),
        _p(1, 1, 1),
        _p(1, 9, 1),
      ]),
    ],
    parents: const {
      'base south': 'base bottom',
      'base east': 'base bottom',
      'base north': 'base bottom',
      'base west': 'base bottom',
      'base top south': 'base south',
      'base top east': 'base east',
      'base top north': 'base north',
      'base top west': 'base west',
    },
  );

  Vector3 front(num x, num z) => _p(x, 1, z);
  Vector3 roof(num y, num t) => _p(7 - 3 * t / 5, y, 5 + 4 * t / 5);
  final house = NetIsland(
    root: 'west wall',
    axis: (1, 0),
    faces: [
      NetFace('west wall', [
        _p(1, 9, 1),
        _p(1, 1, 1),
        _p(1, 1, 5),
        _p(1, 9, 5),
      ]),
      NetFace('east wall', [
        _p(7, 1, 1),
        _p(7, 9, 1),
        _p(7, 9, 5),
        _p(7, 1, 5),
      ]),
      NetFace('front below', [
        front(1, 1),
        front(7, 1),
        front(5, 2),
        front(3, 2),
      ]),
      NetFace('front right', [
        front(7, 1),
        front(7, 5),
        front(5, 3),
        front(5, 2),
      ]),
      NetFace('front gable', [
        front(5, 3),
        front(7, 5),
        front(4, 9),
        front(1, 5),
        front(3, 3),
      ]),
      NetFace('front left', [
        front(1, 1),
        front(3, 2),
        front(3, 3),
        front(1, 5),
      ]),
      NetFace('back gable', [
        _p(7, 9, 1),
        _p(1, 9, 1),
        _p(1, 9, 5),
        _p(4, 9, 9),
        _p(7, 9, 5),
      ]),
      NetFace('west roof', [
        _p(1, 1, 5),
        _p(1, 9, 5),
        _p(4, 9, 9),
        _p(4, 1, 9),
      ]),
      NetFace('east roof eave', [
        roof(1, 0),
        roof(9, 0),
        roof(6, 1),
        roof(3, 1),
      ]),
      NetFace('east roof ridge', [
        roof(9, 5),
        roof(1, 5),
        roof(3, 4),
        roof(6, 4),
      ]),
      NetFace('east roof south', [
        roof(1, 5),
        roof(1, 0),
        roof(3, 1),
        roof(3, 4),
      ]),
      NetFace('east roof north', [
        roof(9, 0),
        roof(9, 5),
        roof(6, 4),
        roof(6, 1),
      ]),
    ],
    parents: const {
      'front left': 'west wall',
      'front below': 'front left',
      'front gable': 'front left',
      'back gable': 'west wall',
      'east wall': 'back gable',
      'front right': 'east wall',
      'west roof': 'west wall',
      'east roof ridge': 'west roof',
      'east roof eave': 'east wall',
      'east roof south': 'east roof eave',
      'east roof north': 'east roof eave',
    },
  );

  final up = Vector3(4, 0, 3) / 5;
  Vector3 panel(num y, num t) => roof(y, t) + up;
  final solar = NetIsland(
    root: 'panel top',
    faces: [
      NetFace('panel top', [
        panel(3, 1),
        panel(6, 1),
        panel(6, 4),
        panel(3, 4),
      ]),
      NetFace('panel eave', [roof(3, 1), roof(6, 1), panel(6, 1), panel(3, 1)]),
      NetFace('panel ridge', [
        roof(6, 4),
        roof(3, 4),
        panel(3, 4),
        panel(6, 4),
      ]),
      NetFace('panel south', [
        roof(3, 4),
        roof(3, 1),
        panel(3, 1),
        panel(3, 4),
      ]),
      NetFace('panel north', [
        roof(6, 1),
        roof(6, 4),
        panel(6, 4),
        panel(6, 1),
      ]),
    ],
    parents: const {
      'panel eave': 'panel top',
      'panel ridge': 'panel top',
      'panel south': 'panel top',
      'panel north': 'panel top',
    },
  );

  final perch = NetIsland(
    root: 'perch top',
    faces: [
      NetFace('perch top', [
        _p(3, -2, 3),
        _p(5, -2, 3),
        _p(5, 1, 3),
        _p(3, 1, 3),
      ]),
      NetFace('perch bottom', [
        _p(3, 1, 2),
        _p(5, 1, 2),
        _p(5, -2, 2),
        _p(3, -2, 2),
      ]),
      NetFace('perch west', [
        _p(3, 1, 2),
        _p(3, -2, 2),
        _p(3, -2, 3),
        _p(3, 1, 3),
      ]),
      NetFace('perch east', [
        _p(5, -2, 2),
        _p(5, 1, 2),
        _p(5, 1, 3),
        _p(5, -2, 3),
      ]),
      NetFace('perch end', [
        _p(3, -2, 2),
        _p(5, -2, 2),
        _p(5, -2, 3),
        _p(3, -2, 3),
      ]),
    ],
    parents: const {
      'perch west': 'perch top',
      'perch east': 'perch top',
      'perch end': 'perch top',
      'perch bottom': 'perch end',
    },
  );

  return PapercraftDesign(
    craftId: 'craft_Birdhouse',
    layer: 'Birdhouse',
    puzzleId: 'birdhouse',
    name: 'Birdhouse',
    islands: [base, house, solar, perch],
  );
}

/// A flared cup with a sleeve round its waist and a lid with a sip bump:
/// four islands. The cup and the sleeve are open; the sleeve hides the cup's
/// waist, and the lid's skirt hangs over the rim.
PapercraftDesign coffeeCupDesign() {
  final flare = math.sqrt(8);
  final waist = flare;
  final shoulder = waist + 3;
  final rim = shoulder + flare;

  final cup = NetIsland(
    root: 'cup bottom',
    faces: [
      NetFace('cup bottom', [
        _p(-2, -2, 0),
        _p(2, -2, 0),
        _p(2, 2, 0),
        _p(-2, 2, 0),
      ]),
      for (var k = 0; k < 4; k++) ...[
        _turned('cup ${_sides[k]} foot', [
          _p(-2, -2, 0),
          _p(2, -2, 0),
          _p(3, -3, waist),
          _p(-3, -3, waist),
        ], k),
        _turned('cup ${_sides[k]} waist', [
          _p(-3, -3, waist),
          _p(3, -3, waist),
          _p(3, -3, shoulder),
          _p(-3, -3, shoulder),
        ], k),
        _turned('cup ${_sides[k]} lip', [
          _p(-3, -3, shoulder),
          _p(3, -3, shoulder),
          _p(4, -4, rim),
          _p(-4, -4, rim),
        ], k),
      ],
    ],
    parents: {
      for (final side in _sides) ...{
        'cup $side foot': 'cup bottom',
        'cup $side waist': 'cup $side foot',
        'cup $side lip': 'cup $side waist',
      },
    },
  );

  final sleeve = NetIsland(
    root: 'sleeve south',
    faces: [
      for (var k = 0; k < 4; k++)
        _turned('sleeve ${_sides[k]}', [
          _p(-3.5, -3.5, waist),
          _p(3.5, -3.5, waist),
          _p(3.5, -3.5, shoulder),
          _p(-3.5, -3.5, shoulder),
        ], k),
    ],
    parents: const {
      'sleeve east': 'sleeve south',
      'sleeve north': 'sleeve east',
      'sleeve west': 'sleeve north',
    },
  );

  final skirtLow = rim - 0.5;
  final skirtHigh = rim + 0.5;
  final top = skirtHigh + math.sqrt(3);
  Vector3 lidTop(num x, num y) => _p(x - 3.5, y - 3.5, top);
  Vector3 bumpTop(num x, num y) => lidTop(x, y) + Vector3(0, 0, 1);
  final lid = NetIsland(
    root: 'lid top south',
    faces: [
      NetFace('lid top south', [
        lidTop(0, 0),
        lidTop(7, 0),
        lidTop(5, 5),
        lidTop(2, 5),
      ]),
      NetFace('lid top east', [
        lidTop(7, 0),
        lidTop(7, 7),
        lidTop(5, 6),
        lidTop(5, 5),
      ]),
      NetFace('lid top north', [
        lidTop(7, 7),
        lidTop(0, 7),
        lidTop(2, 6),
        lidTop(5, 6),
      ]),
      NetFace('lid top west', [
        lidTop(0, 7),
        lidTop(0, 0),
        lidTop(2, 5),
        lidTop(2, 6),
      ]),
      for (var k = 0; k < 4; k++) ...[
        _turned('lid ${_sides[k]} shoulder', [
          _p(-4.5, -4.5, skirtHigh),
          _p(4.5, -4.5, skirtHigh),
          lidTop(7, 0),
          lidTop(0, 0),
        ], k),
        _turned('lid ${_sides[k]} skirt', [
          _p(-4.5, -4.5, skirtLow),
          _p(4.5, -4.5, skirtLow),
          _p(4.5, -4.5, skirtHigh),
          _p(-4.5, -4.5, skirtHigh),
        ], k),
      ],
    ],
    parents: const {
      'lid top east': 'lid top south',
      'lid top west': 'lid top south',
      'lid south shoulder': 'lid top south',
      'lid east shoulder': 'lid top east',
      'lid west shoulder': 'lid top west',
      'lid south skirt': 'lid south shoulder',
      'lid east skirt': 'lid east shoulder',
      'lid west skirt': 'lid west shoulder',
      'lid north skirt': 'lid east skirt',
      'lid north shoulder': 'lid north skirt',
      'lid top north': 'lid north shoulder',
    },
  );

  final bump = NetIsland(
    root: 'bump top',
    faces: [
      NetFace('bump top', [
        bumpTop(2, 5),
        bumpTop(5, 5),
        bumpTop(5, 6),
        bumpTop(2, 6),
      ]),
      NetFace('bump south', [
        lidTop(2, 5),
        lidTop(5, 5),
        bumpTop(5, 5),
        bumpTop(2, 5),
      ]),
      NetFace('bump east', [
        lidTop(5, 5),
        lidTop(5, 6),
        bumpTop(5, 6),
        bumpTop(5, 5),
      ]),
      NetFace('bump north', [
        lidTop(5, 6),
        lidTop(2, 6),
        bumpTop(2, 6),
        bumpTop(5, 6),
      ]),
      NetFace('bump west', [
        lidTop(2, 6),
        lidTop(2, 5),
        bumpTop(2, 5),
        bumpTop(2, 6),
      ]),
    ],
    parents: const {
      'bump south': 'bump top',
      'bump east': 'bump top',
      'bump north': 'bump top',
      'bump west': 'bump top',
    },
  );

  return PapercraftDesign(
    craftId: 'craft_CoffeeCup',
    layer: 'CoffeeCup',
    puzzleId: 'coffee-cup',
    name: 'Coffee Cup',
    islands: [cup, sleeve, lid, bump],
  );
}
