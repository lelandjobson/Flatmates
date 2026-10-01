import 'dart:math' as math;
import 'dart:ui';

/// Palette for color-group dots. Index is what puzzles store.
const List<Color> kRulePalette = [
  Color(0xFFE53935),
  Color(0xFF1E88E5),
  Color(0xFF43A047),
  Color(0xFFFDD835),
  Color(0xFF8E24AA),
];

const List<String> kRuleColorNames = [
  'red',
  'blue',
  'green',
  'yellow',
  'purple',
];

/// Directed or undirected grid edge. Arrows run from [a] to [b].
class GridEdge {
  const GridEdge(this.a, this.b);

  final Offset a;
  final Offset b;

  GridEdge turned(Offset origin, Offset Function(Offset, Offset) rotate) {
    return GridEdge(rotate(a, origin), rotate(b, origin));
  }

  Map<String, dynamic> toJson() => {
    'a': [a.dx, a.dy],
    'b': [b.dx, b.dy],
  };

  factory GridEdge.fromJson(Map<String, dynamic> json) {
    return GridEdge(_offset(json['a']), _offset(json['b']));
  }
}

/// Which rule widget a selection refers to.
enum RuleKind { forbidden, color, number, arrow, dock, link, seam }

/// One rule widget, by kind and index in that list.
class RulePick {
  const RulePick(this.kind, this.index);

  final RuleKind kind;
  final int index;

  @override
  bool operator ==(Object other) =>
      other is RulePick && other.kind == kind && other.index == index;

  @override
  int get hashCode => Object.hash(kind, index);
}

class ColorMark {
  const ColorMark(this.point, this.color);

  final Offset point;
  final int color;

  Map<String, dynamic> toJson() => {
    'at': [point.dx, point.dy],
    'color': color,
  };

  factory ColorMark.fromJson(Map<String, dynamic> json) {
    return ColorMark(
      _offset(json['at']),
      (json['color'] as num?)?.toInt() ?? 0,
    );
  }
}

class OrderMark {
  const OrderMark(this.point, this.number);

  final Offset point;
  final int number;

  Map<String, dynamic> toJson() => {
    'at': [point.dx, point.dy],
    'n': number,
  };

  factory OrderMark.fromJson(Map<String, dynamic> json) {
    return OrderMark(_offset(json['at']), (json['n'] as num?)?.toInt() ?? 1);
  }
}

class LinkMark {
  const LinkMark(this.point, this.pair);

  final Offset point;
  final int pair;

  Map<String, dynamic> toJson() => {
    'at': [point.dx, point.dy],
    'pair': pair,
  };

  factory LinkMark.fromJson(Map<String, dynamic> json) {
    return LinkMark(_offset(json['at']), (json['pair'] as num?)?.toInt() ?? 0);
  }
}

/// Authored constraints on one level. Empty rules leave play unchanged.
class GridRules {
  const GridRules({
    this.maxExits,
    this.maxLength,
    this.forbidden = const [],
    this.colors = const [],
    this.numbers = const [],
    this.arrows = const [],
    this.docks = const [],
    this.links = const [],
    this.seams = const [],
  });

  final int? maxExits;
  final double? maxLength;
  final List<Offset> forbidden;
  final List<ColorMark> colors;
  final List<OrderMark> numbers;
  final List<GridEdge> arrows;
  final List<Offset> docks;
  final List<LinkMark> links;
  final List<GridEdge> seams;

  bool get isEmpty =>
      maxExits == null &&
      maxLength == null &&
      forbidden.isEmpty &&
      colors.isEmpty &&
      numbers.isEmpty &&
      arrows.isEmpty &&
      docks.isEmpty &&
      links.isEmpty &&
      seams.isEmpty;

  /// Every point a widget occupies, so the sheet can enclose them.
  Iterable<Offset> get anchors sync* {
    yield* forbidden;
    for (final mark in colors) {
      yield mark.point;
    }
    for (final mark in numbers) {
      yield mark.point;
    }
    for (final edge in arrows) {
      yield edge.a;
      yield edge.b;
    }
    yield* docks;
    for (final mark in links) {
      yield mark.point;
    }
    for (final edge in seams) {
      yield edge.a;
      yield edge.b;
    }
  }

  GridRules copyWith({
    int? maxExits,
    bool clearExits = false,
    double? maxLength,
    bool clearLength = false,
    List<Offset>? forbidden,
    List<ColorMark>? colors,
    List<OrderMark>? numbers,
    List<GridEdge>? arrows,
    List<Offset>? docks,
    List<LinkMark>? links,
    List<GridEdge>? seams,
  }) {
    return GridRules(
      maxExits: clearExits ? null : (maxExits ?? this.maxExits),
      maxLength: clearLength ? null : (maxLength ?? this.maxLength),
      forbidden: forbidden ?? this.forbidden,
      colors: colors ?? this.colors,
      numbers: numbers ?? this.numbers,
      arrows: arrows ?? this.arrows,
      docks: docks ?? this.docks,
      links: links ?? this.links,
      seams: seams ?? this.seams,
    );
  }

  /// True when the blade may travel [from] to [to] under [progress].
  bool allows(
    Offset from,
    Offset to,
    CutProgress progress, {
    required Rect paper,
  }) {
    return consider(from, to, progress, paper: paper).allowed;
  }

  /// Allowed travel, plus the progress that travel would record.
  SegmentRuling consider(
    Offset from,
    Offset to,
    CutProgress progress, {
    required Rect paper,
  }) {
    if ((to - from).distance < 1e-8 || isEmpty) {
      return SegmentRuling(allowed: true, progress: progress);
    }
    if (_hitsForbidden(from, to) || _wrongWay(from, to)) {
      return SegmentRuling(allowed: false, progress: progress);
    }
    final travel = (to - from).distance;
    if (maxLength != null && progress.lengthUsed + travel > maxLength! + 1e-6) {
      return SegmentRuling(allowed: false, progress: progress);
    }
    final entering = _onBoundary(from, paper) && !_onBoundary(to, paper);
    if (entryGemsRemain(this, progress) &&
        entering &&
        !_opensAtGem(from, progress)) {
      return SegmentRuling(allowed: false, progress: progress);
    }

    final colored = _takeColors(from, to, progress);
    if (colored.failed) {
      return SegmentRuling(
        allowed: true,
        failed: true,
        progress: colored.progress,
        cause: FailureCue(FailureKind.color, colored.cause!),
      );
    }
    final ordered = _takeNumbers(from, to, colored.progress);
    if (ordered.failed) {
      return SegmentRuling(
        allowed: true,
        failed: true,
        progress: ordered.progress,
        cause: FailureCue(FailureKind.number, ordered.cause!),
      );
    }
    final linked = _takeLinks(from, to, ordered.progress);
    if (linked == null) {
      return SegmentRuling(allowed: false, progress: progress);
    }

    var next = linked.copyWith(
      lengthUsed: progress.lengthUsed + travel,
      severedSeams: {...linked.severedSeams, ..._seamsCut(from, to)},
    );
    if (_onBoundary(to, paper)) {
      if (docks.isNotEmpty && !docks.any((dock) => _near(dock, to))) {
        return SegmentRuling(allowed: false, progress: progress);
      }
      if (next.openLinks.isNotEmpty) {
        return SegmentRuling(allowed: false, progress: progress);
      }
      if (maxExits != null && next.exitsUsed + 1 > maxExits!) {
        return SegmentRuling(allowed: false, progress: progress);
      }
      next = next.copyWith(exitsUsed: next.exitsUsed + 1);
    }
    return SegmentRuling(allowed: true, progress: next);
  }

  bool seamsSatisfied(CutProgress progress) {
    if (seams.isEmpty) return true;
    for (var i = 0; i < seams.length; i++) {
      if (!progress.severedSeams.contains(i)) return false;
    }
    return true;
  }

  GridRules turned(
    Offset origin,
    Offset Function(Offset point, Offset origin) rotate,
  ) {
    Offset turn(Offset point) => rotate(point, origin);
    return GridRules(
      maxExits: maxExits,
      maxLength: maxLength,
      forbidden: [for (final point in forbidden) turn(point)],
      colors: [
        for (final mark in colors) ColorMark(turn(mark.point), mark.color),
      ],
      numbers: [
        for (final mark in numbers) OrderMark(turn(mark.point), mark.number),
      ],
      arrows: [for (final edge in arrows) edge.turned(origin, rotate)],
      docks: [for (final point in docks) turn(point)],
      links: [for (final mark in links) LinkMark(turn(mark.point), mark.pair)],
      seams: [for (final edge in seams) edge.turned(origin, rotate)],
    );
  }

  Map<String, dynamic> toJson() => {
    if (maxExits != null) 'maxExits': maxExits,
    if (maxLength != null) 'maxLength': maxLength,
    if (forbidden.isNotEmpty)
      'forbidden': [
        for (final point in forbidden) [point.dx, point.dy],
      ],
    if (colors.isNotEmpty) 'colors': [for (final mark in colors) mark.toJson()],
    if (numbers.isNotEmpty)
      'numbers': [for (final mark in numbers) mark.toJson()],
    if (arrows.isNotEmpty) 'arrows': [for (final edge in arrows) edge.toJson()],
    if (docks.isNotEmpty)
      'docks': [
        for (final point in docks) [point.dx, point.dy],
      ],
    if (links.isNotEmpty) 'links': [for (final mark in links) mark.toJson()],
    if (seams.isNotEmpty) 'seams': [for (final edge in seams) edge.toJson()],
  };

  factory GridRules.fromJson(Object? raw) {
    if (raw is! Map) return const GridRules();
    final json = Map<String, dynamic>.from(raw);
    return GridRules(
      maxExits: (json['maxExits'] as num?)?.toInt(),
      maxLength: (json['maxLength'] as num?)?.toDouble(),
      forbidden: _points(json['forbidden']),
      colors: _marks(json['colors'], ColorMark.fromJson),
      numbers: _marks(json['numbers'], OrderMark.fromJson),
      arrows: _marks(json['arrows'], GridEdge.fromJson),
      docks: _points(json['docks']),
      links: _marks(json['links'], LinkMark.fromJson),
      seams: _marks(json['seams'], GridEdge.fromJson),
    );
  }

  bool _hitsForbidden(Offset from, Offset to) {
    for (final point in forbidden) {
      if (_onSegment(point, from, to)) return true;
    }
    return false;
  }

  bool _wrongWay(Offset from, Offset to) {
    final travel = to - from;
    for (final arrow in arrows) {
      if (!_overlaps(from, to, arrow.a, arrow.b)) continue;
      final dir = arrow.b - arrow.a;
      if (travel.dx * dir.dx + travel.dy * dir.dy < 0) return true;
    }
    return false;
  }

  ({CutProgress progress, bool failed, int? cause}) _takeColors(
    Offset from,
    Offset to,
    CutProgress progress,
  ) {
    final hits = _along(from, to, colors.length, (index) {
      if (progress.collectedColors.contains(index)) return null;
      return colors[index].point;
    });
    var open = progress.openColor;
    final collected = {...progress.collectedColors};
    var failed = false;
    int? cause;
    for (final index in hits) {
      final color = colors[index].color;
      if (open != null && open != color && _remaining(open, collected) > 0) {
        failed = true;
        cause ??= index;
      }
      collected.add(index);
      open = _remaining(color, collected) == 0 ? null : color;
    }
    return (
      progress: progress.copyWith(
        openColor: open,
        clearOpenColor: open == null,
        collectedColors: collected,
      ),
      failed: failed,
      cause: cause,
    );
  }

  int _remaining(int color, Set<int> collected) {
    var count = 0;
    for (var i = 0; i < colors.length; i++) {
      if (colors[i].color == color && !collected.contains(i)) count++;
    }
    return count;
  }

  ({CutProgress progress, bool failed, int? cause}) _takeNumbers(
    Offset from,
    Offset to,
    CutProgress progress,
  ) {
    final hits = _along(
      from,
      to,
      numbers.length,
      (index) => numbers[index].point,
    );
    var next = progress.nextNumber;
    for (final index in hits) {
      final number = numbers[index].number;
      if (number < next) continue;
      if (number != next) {
        return (progress: progress, failed: true, cause: index);
      }
      next++;
    }
    return (
      progress: progress.copyWith(nextNumber: next),
      failed: false,
      cause: null,
    );
  }

  bool _opensAtGem(Offset point, CutProgress progress) {
    for (var i = 0; i < numbers.length; i++) {
      if (numbers[i].number < progress.nextNumber) continue;
      if (_near(numbers[i].point, point)) return true;
    }
    return false;
  }

  CutProgress? _takeLinks(Offset from, Offset to, CutProgress progress) {
    final hits = _along(from, to, links.length, (index) {
      if (progress.collectedLinks.contains(index)) return null;
      return links[index].point;
    });
    final collected = {...progress.collectedLinks, ...hits};
    final counts = <int, int>{};
    final got = <int, int>{};
    for (var i = 0; i < links.length; i++) {
      final pair = links[i].pair;
      counts[pair] = (counts[pair] ?? 0) + 1;
      if (collected.contains(i)) got[pair] = (got[pair] ?? 0) + 1;
    }
    final open = <int>{
      for (final pair in counts.keys)
        if ((got[pair] ?? 0) > 0 && (got[pair] ?? 0) < counts[pair]!) pair,
    };
    return progress.copyWith(collectedLinks: collected, openLinks: open);
  }

  Set<int> _seamsCut(Offset from, Offset to) {
    final cut = <int>{};
    for (var i = 0; i < seams.length; i++) {
      if (_overlaps(from, to, seams[i].a, seams[i].b)) cut.add(i);
    }
    return cut;
  }

  List<int> _along(
    Offset from,
    Offset to,
    int count,
    Offset? Function(int index) pointAt,
  ) {
    final hits = <(double, int)>[];
    for (var i = 0; i < count; i++) {
      final point = pointAt(i);
      if (point == null || !_onSegment(point, from, to)) continue;
      hits.add((_parameter(point, from, to), i));
    }
    hits.sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final hit in hits) hit.$2];
  }
}

/// The constraint the player is in the middle of, for the play badge.
class RuleCue {
  const RuleCue({this.color, this.number, this.link, this.seamsLeft});

  final int? color;
  final int? number;
  final int? link;
  final int? seamsLeft;

  bool get isEmpty =>
      color == null && number == null && link == null && seamsLeft == null;
}

RuleCue ruleCue(GridRules rules, CutProgress progress) {
  final open = progress.openColor;
  final color = open != null && open >= 0 && open < kRulePalette.length
      ? open
      : null;
  int? number;
  if (rules.numbers.any((mark) => mark.number >= progress.nextNumber)) {
    number = progress.nextNumber;
  }
  final link = progress.openLinks.isEmpty
      ? null
      : progress.openLinks.reduce(math.min);
  int? seamsLeft;
  if (rules.seams.isNotEmpty) {
    final left = rules.seams.length - progress.severedSeams.length;
    if (left > 0) seamsLeft = left;
  }
  return RuleCue(
    color: color,
    number: number,
    link: link,
    seamsLeft: seamsLeft,
  );
}

/// The thing that broke a failure condition, so play can flash it red.
enum FailureKind { color, number, piece, paper }

class FailureCue {
  const FailureCue(this.kind, this.index);

  final FailureKind kind;
  final int index;
}

/// True while a color or number gem is still waiting to be taken.
bool gemsRemain(GridRules rules, CutProgress progress) {
  if (progress.collectedColors.length < rules.colors.length) return true;
  for (final mark in rules.numbers) {
    if (mark.number >= progress.nextNumber) return true;
  }
  return false;
}

/// True while a number gem is still waiting to be taken.
///
/// Number gems are entry points: a new cut must start at one. Color gems are
/// only collected in groups, so a cut may start anywhere on the paper edge.
bool entryGemsRemain(GridRules rules, CutProgress progress) {
  for (final mark in rules.numbers) {
    if (mark.number >= progress.nextNumber) return true;
  }
  return false;
}

/// True when every color gem and number gem on the level has been collected.
bool collectiblesCleared(GridRules rules, CutProgress progress) {
  if (rules.colors.isEmpty && rules.numbers.isEmpty) return false;
  if (progress.collectedColors.length != rules.colors.length) return false;
  var highest = 0;
  for (final mark in rules.numbers) {
    if (mark.number > highest) highest = mark.number;
  }
  if (rules.numbers.isNotEmpty && progress.nextNumber <= highest) return false;
  return true;
}

class SegmentRuling {
  const SegmentRuling({
    required this.allowed,
    required this.progress,
    this.failed = false,
    this.cause,
  });

  final bool allowed;

  /// A failure condition. The level restarts from its original state.
  final bool failed;

  /// The gem or other mark that caused [failed].
  final FailureCue? cause;
  final CutProgress progress;
}

/// What the blade has already spent and collected during this play session.
class CutProgress {
  const CutProgress({
    this.exitsUsed = 0,
    this.lengthUsed = 0,
    this.openColor,
    this.collectedColors = const {},
    this.nextNumber = 1,
    this.collectedLinks = const {},
    this.openLinks = const {},
    this.severedSeams = const {},
  });

  final int exitsUsed;
  final double lengthUsed;
  final int? openColor;
  final Set<int> collectedColors;
  final int nextNumber;
  final Set<int> collectedLinks;
  final Set<int> openLinks;
  final Set<int> severedSeams;

  CutProgress copyWith({
    int? exitsUsed,
    double? lengthUsed,
    int? openColor,
    bool clearOpenColor = false,
    Set<int>? collectedColors,
    int? nextNumber,
    Set<int>? collectedLinks,
    Set<int>? openLinks,
    Set<int>? severedSeams,
  }) {
    return CutProgress(
      exitsUsed: exitsUsed ?? this.exitsUsed,
      lengthUsed: lengthUsed ?? this.lengthUsed,
      openColor: clearOpenColor ? null : (openColor ?? this.openColor),
      collectedColors: collectedColors ?? this.collectedColors,
      nextNumber: nextNumber ?? this.nextNumber,
      collectedLinks: collectedLinks ?? this.collectedLinks,
      openLinks: openLinks ?? this.openLinks,
      severedSeams: severedSeams ?? this.severedSeams,
    );
  }
}

Offset _offset(Object? raw) {
  final list = raw as List;
  return Offset((list[0] as num).toDouble(), (list[1] as num).toDouble());
}

List<Offset> _points(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item is List) _offset(item),
  ];
}

List<T> _marks<T>(Object? raw, T Function(Map<String, dynamic>) decode) {
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item is Map) decode(Map<String, dynamic>.from(item)),
  ];
}

const double _eps = 1e-3;

bool _near(Offset a, Offset b) => (a - b).distance <= _eps;

bool _onSegment(Offset point, Offset a, Offset b) {
  final ab = b - a;
  final len = ab.distance;
  if (len < 1e-8) return _near(point, a);
  final ap = point - a;
  final cross = (ap.dx * ab.dy - ap.dy * ab.dx).abs() / len;
  if (cross > _eps) return false;
  final t = (ap.dx * ab.dx + ap.dy * ab.dy) / (len * len);
  return t >= -_eps && t <= 1 + _eps;
}

double _parameter(Offset point, Offset a, Offset b) {
  final ab = b - a;
  final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (len2 < 1e-12) return 0;
  return ((point.dx - a.dx) * ab.dx + (point.dy - a.dy) * ab.dy) / len2;
}

bool _overlaps(Offset a, Offset b, Offset p, Offset q) {
  final ab = b - a;
  final len = ab.distance;
  final other = (q - p).distance;
  if (len < 1e-8 || other < 1e-8) return false;
  final cross =
      (ab.dx * (q.dy - p.dy) - ab.dy * (q.dx - p.dx)).abs() / (len * other);
  if (cross > _eps) return false;
  final off = ((p.dx - a.dx) * ab.dy - (p.dy - a.dy) * ab.dx).abs() / len;
  if (off > _eps) return false;
  final t0 = _parameter(p, a, b);
  final t1 = _parameter(q, a, b);
  final lo = math.max(0.0, math.min(t0, t1));
  final hi = math.min(1.0, math.max(t0, t1));
  return hi - lo > _eps;
}

bool _onBoundary(Offset point, Rect paper) {
  final insideX =
      point.dx >= paper.left - _eps && point.dx <= paper.right + _eps;
  final insideY =
      point.dy >= paper.top - _eps && point.dy <= paper.bottom + _eps;
  if (!insideX || !insideY) return false;
  final onX =
      (point.dx - paper.left).abs() <= _eps ||
      (point.dx - paper.right).abs() <= _eps;
  final onY =
      (point.dy - paper.top).abs() <= _eps ||
      (point.dy - paper.bottom).abs() <= _eps;
  return onX || onY;
}
