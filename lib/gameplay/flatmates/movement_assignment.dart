import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../friends/friend_instance.dart';
import '../recording/game_recording_io.dart';
import 'movement_profile.dart';
import 'movement_profile_io.dart';

/// Repo-relative map of friend template id → movement pattern id.
const kMovementAssignmentsPath =
    '$kMovementProfilesAssetDir/assignments.json';

/// One movement pattern per friend type. A pattern may be shared.
class MovementAssignments {
  const MovementAssignments([this.friendToPattern = const {}]);

  static const empty = MovementAssignments();

  final Map<String, String> friendToPattern;

  String? patternIdFor(String friendId) => friendToPattern[friendId];

  List<String> friendIdsFor(String patternId) => [
        for (final entry in friendToPattern.entries)
          if (entry.value == patternId) entry.key,
      ];

  /// Points [friendId] at [patternId], replacing any previous pattern.
  MovementAssignments assign({
    required String friendId,
    required String patternId,
  }) {
    final next = Map<String, String>.from(friendToPattern);
    next[friendId] = patternId;
    return MovementAssignments(next);
  }

  MovementAssignments withoutFriend(String friendId) {
    if (!friendToPattern.containsKey(friendId)) return this;
    final next = Map<String, String>.from(friendToPattern)..remove(friendId);
    return MovementAssignments(next);
  }

  Map<String, dynamic> toJson() => {
        'friends': Map<String, String>.from(friendToPattern),
      };

  factory MovementAssignments.fromJson(Map<String, dynamic> json) {
    final raw = json['friends'];
    if (raw is! Map) return const MovementAssignments();
    final mapped = <String, String>{};
    for (final entry in raw.entries) {
      final id = entry.key.toString();
      final pattern = entry.value;
      if (id.isEmpty || pattern is! String || pattern.isEmpty) continue;
      mapped[id] = pattern;
    }
    return MovementAssignments(mapped);
  }

  @override
  bool operator ==(Object other) =>
      other is MovementAssignments &&
      _mapEquals(other.friendToPattern, friendToPattern);

  @override
  int get hashCode => Object.hashAll(
        friendToPattern.entries.map((e) => Object.hash(e.key, e.value)),
      );
}

bool _mapEquals(Map<String, String> a, Map<String, String> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}

/// Unique id for a duplicated movement pattern. Assignments stay on the original.
String movementPatternCopyId(String id, Iterable<String> taken) {
  final existing = taken.toSet();
  final base = id.endsWith('-copy') ? id : '$id-copy';
  if (!existing.contains(base)) return base;
  var n = 2;
  while (existing.contains('$base-$n')) {
    n++;
  }
  return '$base-$n';
}

String movementPatternCopyName(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return 'Copy';
  if (trimmed.toLowerCase().endsWith(' copy')) return trimmed;
  return '$trimmed copy';
}

/// Loads and writes [MovementAssignments] next to movement patterns.
class MovementAssignmentIo {
  static const _encoder = JsonEncoder.withIndent('  ');

  static Future<MovementAssignments> load() async {
    final file = resolveFile();
    if (file != null && file.existsSync()) {
      try {
        return MovementAssignments.fromJson(
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
        );
      } catch (_) {}
    }
    try {
      final raw = await rootBundle.loadString(kMovementAssignmentsPath);
      return MovementAssignments.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return MovementAssignments.empty;
    }
  }

  static Future<String> save(MovementAssignments assignments) async {
    final file = resolveFile();
    if (file == null) {
      throw StateError(
        'Could not find the Flatmates repo root (pubspec.yaml). '
        'Run from the project, or check macOS sandbox entitlements.',
      );
    }
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('${_encoder.convert(assignments.toJson())}\n');
    return kMovementAssignmentsPath;
  }

  static File? resolveFile() {
    final root = GameRecordingIo.findRepoRoot();
    if (root == null) return null;
    return File(
      '${root.path}${Platform.pathSeparator}'
      '${kMovementAssignmentsPath.replaceAll('/', Platform.pathSeparator)}',
    );
  }
}

/// Pattern assigned to [friendId], or [fallback] / default.json.
Future<MovementProfile> movementPatternForFriend(
  String friendId, {
  MovementAssignments? assignments,
  List<MovementProfile>? catalog,
  MovementProfile? fallback,
}) async {
  final map = assignments ?? await MovementAssignmentIo.load();
  final patterns = catalog ?? await MovementProfileIo.list();
  final byId = {for (final p in patterns) p.id: p};
  final patternId = map.patternIdFor(friendId);
  if (patternId != null && byId[patternId] != null) {
    return byId[patternId]!;
  }
  return fallback ??
      byId['default'] ??
      await MovementProfileIo.loadDefault();
}

/// Lookup table GameView can keep in memory.
Map<String, MovementProfile> movementPatternsByFriend({
  required MovementAssignments assignments,
  required List<MovementProfile> catalog,
  required MovementProfile fallback,
}) {
  final byId = {for (final p in catalog) p.id: p};
  final out = <String, MovementProfile>{};
  for (final friend in kBedroomFriendTemplates) {
    final patternId = assignments.patternIdFor(friend.id);
    out[friend.id] = (patternId != null ? byId[patternId] : null) ?? fallback;
  }
  return out;
}
