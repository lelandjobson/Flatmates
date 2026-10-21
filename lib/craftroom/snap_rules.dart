import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'craft_theme.dart';

/// Something on the craft room bench that can snap.
enum SnapUser {
  straightCut,
  scissors,
  folder,
  straightEdge,
  exacto,
  paperMove,
  islandMove,
}

/// What a [SnapUser] can snap to.
enum SnapTarget {
  craftGrid,
  paperVertex,
  paperEdge,
  blueprintVertex,
  blueprintEdge,
}

/// What one [SnapUser] may snap to. A [free] user never snaps, whatever its
/// [targets]. [rotationStep] is the turn it keeps to, in radians, or null to
/// turn freely.
@immutable
class SnapRule {
  const SnapRule({
    this.targets = const {},
    this.free = false,
    this.rotationStep,
  });

  final Set<SnapTarget> targets;
  final bool free;
  final double? rotationStep;

  bool allows(SnapTarget target) => !free && targets.contains(target);

  SnapRule copyWith({
    Set<SnapTarget>? targets,
    bool? free,
    double? Function()? rotationStep,
  }) => SnapRule(
    targets: targets ?? this.targets,
    free: free ?? this.free,
    rotationStep: rotationStep == null ? this.rotationStep : rotationStep(),
  );

  Map<String, dynamic> toJson() => {
    'targets': [for (final target in targets) target.name],
    'free': free,
    'rotationStep': rotationStep,
  };

  static SnapRule fromJson(Object? raw, SnapRule fallback) {
    if (raw is! Map) return fallback;
    final targets = raw['targets'];
    final step = raw['rotationStep'];
    return SnapRule(
      targets: targets is List
          ? {
              for (final name in targets)
                for (final target in SnapTarget.values)
                  if (target.name == name) target,
            }
          : fallback.targets,
      free: raw['free'] is bool ? raw['free'] as bool : fallback.free,
      rotationStep: raw.containsKey('rotationStep')
          ? (step is num ? step.toDouble() : null)
          : fallback.rotationStep,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SnapRule &&
      other.free == free &&
      other.rotationStep == rotationStep &&
      setEquals(other.targets, targets);

  @override
  int get hashCode =>
      Object.hash(free, rotationStep, Object.hashAllUnordered(targets));
}

const double _kQuarterTurn = math.pi / 2;
const double _kEighthTurn = math.pi / 4;

/// The craft room's starting rules. Cuts and the straight edge keep to the
/// grid; the straight edge turns in 45° steps. The folder snaps to
/// everything. The exacto is free, guided only by the straight edge. Moving
/// paper or a net island puts a corner on the grid and turns in 90° steps.
const Map<SnapUser, SnapRule> kDefaultSnapRules = {
  SnapUser.straightCut: SnapRule(targets: {SnapTarget.craftGrid}),
  SnapUser.scissors: SnapRule(targets: {SnapTarget.craftGrid}),
  SnapUser.folder: SnapRule(targets: {...SnapTarget.values}),
  SnapUser.straightEdge: SnapRule(
    targets: {SnapTarget.craftGrid},
    rotationStep: _kEighthTurn,
  ),
  SnapUser.exacto: SnapRule(free: true),
  SnapUser.paperMove: SnapRule(
    targets: {SnapTarget.craftGrid},
    rotationStep: _kQuarterTurn,
  ),
  SnapUser.islandMove: SnapRule(
    targets: {SnapTarget.craftGrid},
    rotationStep: _kQuarterTurn,
  ),
};

/// Which [SnapTarget]s each [SnapUser] may snap to.
@immutable
class SnapRules {
  const SnapRules([this.rules = kDefaultSnapRules]);

  final Map<SnapUser, SnapRule> rules;

  SnapRule operator [](SnapUser user) => rules[user] ?? const SnapRule();

  SnapRules withRule(SnapUser user, SnapRule rule) =>
      SnapRules({...rules, user: rule});

  /// [user] snapping to [target], or not.
  SnapRules toggled(SnapUser user, SnapTarget target, bool on) {
    final rule = this[user];
    final targets = {...rule.targets};
    if (on) {
      targets.add(target);
    } else {
      targets.remove(target);
    }
    return withRule(user, rule.copyWith(targets: targets));
  }

  Map<String, dynamic> toJson() => {
    for (final user in SnapUser.values) user.name: this[user].toJson(),
  };

  static SnapRules fromJson(Object? raw) {
    if (raw is! Map) return const SnapRules();
    return SnapRules({
      for (final user in SnapUser.values)
        user: SnapRule.fromJson(
          raw[user.name],
          kDefaultSnapRules[user] ?? const SnapRule(),
        ),
    });
  }
}

/// What there is to snap to, in desk units.
class SnapContext {
  const SnapContext({
    this.gridSpacing = 1,
    this.paperRings = const [],
    this.blueprintRings = const [],
    this.reach = 0.6,
  });

  final double gridSpacing;

  /// Paper outlines where they are drawn.
  final List<List<Offset>> paperRings;

  /// Net face outlines of the guide.
  final List<List<Offset>> blueprintRings;

  /// How far a vertex or an edge pulls the aim. The grid always does.
  final double reach;
}

/// [aim] moved onto the nearest point [user] may snap to, or [aim] itself
/// when the user is free or nothing allowed is in reach.
///
/// Points come first: the grid point under the aim, and any vertex within
/// [SnapContext.reach]. The nearest of those wins. An edge pulls only when
/// there is no point to take, so with the grid allowed the aim always lands
/// on a grid point or a vertex.
Offset snapPoint(
  SnapRules rules,
  SnapUser user,
  Offset aim,
  SnapContext context,
) {
  final rule = rules[user];
  if (rule.free || rule.targets.isEmpty) return aim;
  final points = <Offset>[
    if (rule.allows(SnapTarget.craftGrid))
      snapToCraftGrid(aim, context.gridSpacing),
    if (rule.allows(SnapTarget.paperVertex))
      for (final ring in context.paperRings)
        for (final vertex in ring)
          if ((vertex - aim).distance <= context.reach) vertex,
    if (rule.allows(SnapTarget.blueprintVertex))
      for (final ring in context.blueprintRings)
        for (final vertex in ring)
          if ((vertex - aim).distance <= context.reach) vertex,
  ];
  if (points.isNotEmpty) return _nearest(aim, points);
  final edges = <Offset>[
    if (rule.allows(SnapTarget.paperEdge))
      ..._edgePoints(aim, context.paperRings),
    if (rule.allows(SnapTarget.blueprintEdge))
      ..._edgePoints(aim, context.blueprintRings),
  ];
  final edge = edges.isEmpty ? null : _nearest(aim, edges);
  if (edge != null && (edge - aim).distance <= context.reach) return edge;
  return aim;
}

Offset _nearest(Offset aim, List<Offset> points) {
  var best = points.first;
  for (final point in points.skip(1)) {
    if ((point - aim).distance < (best - aim).distance) best = point;
  }
  return best;
}

Iterable<Offset> _edgePoints(Offset aim, List<List<Offset>> rings) sync* {
  for (final ring in rings) {
    for (var i = 0; i < ring.length; i++) {
      yield closestOnSegment(aim, ring[i], ring[(i + 1) % ring.length]);
    }
  }
}

/// [angle] turned to the nearest step [user] keeps to.
double snapAngle(SnapRules rules, SnapUser user, double angle) {
  final rule = rules[user];
  final step = rule.rotationStep;
  if (rule.free || step == null || step <= 0) return angle;
  return (angle / step).roundToDouble() * step;
}

/// The shift that puts one of [corners] onto a point [user] may snap to:
/// the corner that needs the least move. Zero when [user] does not snap.
Offset snapShift(
  SnapRules rules,
  SnapUser user,
  Iterable<Offset> corners,
  SnapContext context,
) {
  Offset? best;
  for (final corner in corners) {
    final shift = snapPoint(rules, user, corner, context) - corner;
    if (best == null || shift.distance < best.distance) best = shift;
  }
  return best ?? Offset.zero;
}

/// The grid point nearest [point].
Offset snapToCraftGrid(Offset point, double spacing) {
  if (spacing <= 0) return point;
  return Offset(
    (point.dx / spacing).roundToDouble() * spacing + 0.0,
    (point.dy / spacing).roundToDouble() * spacing + 0.0,
  );
}

Offset closestOnSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (len2 < 1e-12) return a;
  final t = (((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / len2).clamp(
    0.0,
    1.0,
  );
  return a + ab * t;
}

/// The craft room's snap rules, saved as they change and read back the next
/// time the view opens, like the ASMR DevTools values.
class SnapSettings extends ChangeNotifier {
  SnapSettings({
    File? file,
    SnapRules rules = const SnapRules(),
    double paperGridOpacity = kPaperGridOpacity,
  }) : _file = file ?? _defaultFile(),
       _rules = rules,
       _paperGridOpacity = paperGridOpacity.clamp(0.0, 1.0);

  /// `~/.flatmates/craft_room_snap.json`, or a temp file under tests.
  static File _defaultFile() {
    if (Platform.environment['FLUTTER_TEST'] == 'true') {
      return File(
        '${Directory.systemTemp.path}/flatmates_craft_room_snap_test.json',
      );
    }
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.systemTemp.path;
    return File('$home/.flatmates/craft_room_snap.json');
  }

  final File _file;
  SnapRules _rules;
  double _paperGridOpacity;

  SnapRules get rules => _rules;

  /// Opacity of the crafting grid where it lies on the paper.
  double get paperGridOpacity => _paperGridOpacity;

  set paperGridOpacity(double value) {
    final next = value.clamp(0.0, 1.0);
    if ((next - _paperGridOpacity).abs() < 1e-6) return;
    _paperGridOpacity = next;
    notifyListeners();
    _save();
  }

  set rules(SnapRules value) {
    _rules = value;
    notifyListeners();
    _save();
  }

  void toggle(SnapUser user, SnapTarget target, bool on) =>
      rules = _rules.toggled(user, target, on);

  void setFree(SnapUser user, bool free) =>
      rules = _rules.withRule(user, _rules[user].copyWith(free: free));

  /// Reads the saved file. Missing or unreadable files keep the defaults.
  Future<void> load() async {
    try {
      if (!await _file.exists()) return;
      final raw = jsonDecode(await _file.readAsString());
      _rules = SnapRules.fromJson(raw);
      final opacity = raw is Map ? raw['paperGridOpacity'] : null;
      if (opacity is num) {
        _paperGridOpacity = opacity.toDouble().clamp(0.0, 1.0);
      }
      notifyListeners();
    } catch (_) {}
  }

  void _save() {
    try {
      _file.parent.createSync(recursive: true);
      _file.writeAsStringSync(
        const JsonEncoder.withIndent(
          '  ',
        ).convert({..._rules.toJson(), 'paperGridOpacity': _paperGridOpacity}),
      );
    } catch (_) {}
  }
}
