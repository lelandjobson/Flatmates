import 'dart:math' as math;

import '../gridcraft/wrap_cut.dart' show FaceNeighbor;

/// How many selection groups a deal may make.
const List<int> kAsmrGroupCounts = [2, 3, 4];

/// Every face in one of 2, 3, or 4 groups.
///
/// [count] fixes how many. Otherwise the count is chosen at random from
/// [kAsmrGroupCounts], and never more than there are faces. Each group is a
/// connected stretch of the surface, grown from a seed so the faces divide
/// rather than one group taking the rest. Where the object is more separate
/// volumes than groups, a group holds more than one volume.
List<List<int>> randomFaceGroups(
  List<List<FaceNeighbor?>> adjacency, {
  required math.Random random,
  int? count,
}) {
  final n = adjacency.length;
  if (n == 0) return const [];
  final neighbors = _neighbors(adjacency);
  final components = _components(neighbors);
  final k = _wantedCount(n, random, count);
  if (components.length >= k) {
    return _merge(components, k, random);
  }
  return _grow(
    neighbors,
    components,
    _seedCounts(components, k, random),
    random,
  );
}

int _wantedCount(int faces, math.Random random, int? count) {
  if (faces <= 1) return faces;
  final cap = math.min(4, faces);
  var k = count ?? 2 + random.nextInt(kAsmrGroupCounts.length);
  if (k < 2) k = 2;
  if (k > cap) k = cap;
  return k;
}

List<List<int>> _neighbors(List<List<FaceNeighbor?>> adjacency) {
  return [
    for (final edges in adjacency)
      () {
        final seen = <int>{};
        for (final neighbor in edges) {
          final face = neighbor?.face;
          if (face != null) seen.add(face);
        }
        return seen.toList()..sort();
      }(),
  ];
}

List<List<int>> _components(List<List<int>> neighbors) {
  final n = neighbors.length;
  final seen = List<bool>.filled(n, false);
  final components = <List<int>>[];
  for (var i = 0; i < n; i++) {
    if (seen[i]) continue;
    final faces = <int>[];
    final queue = <int>[i];
    seen[i] = true;
    var head = 0;
    while (head < queue.length) {
      final at = queue[head++];
      faces.add(at);
      for (final next in neighbors[at]) {
        if (next < 0 || next >= n || seen[next]) continue;
        seen[next] = true;
        queue.add(next);
      }
    }
    faces.sort();
    components.add(faces);
  }
  return components;
}

/// [k] groups, each starting as one volume, with the volumes left over
/// dropped into a group at random.
List<List<int>> _merge(List<List<int>> components, int k, math.Random random) {
  final order = List<List<int>>.of(components)..shuffle(random);
  final groups = <List<int>>[
    for (var i = 0; i < k; i++) List<int>.of(order[i]),
  ];
  for (final extra in order.skip(k)) {
    groups[random.nextInt(groups.length)].addAll(extra);
  }
  for (final group in groups) {
    group.sort();
  }
  groups.sort((a, b) => a.first.compareTo(b.first));
  return groups;
}

/// How many seeds each volume gets. Each starts with one, and the seeds
/// still needed land on volumes that have faces left, larger ones more often.
List<int> _seedCounts(List<List<int>> components, int k, math.Random random) {
  final counts = List<int>.filled(components.length, 1);
  var left = k - components.length;
  while (left > 0) {
    var room = 0;
    for (var i = 0; i < components.length; i++) {
      room += components[i].length - counts[i];
    }
    if (room <= 0) break;
    var roll = random.nextInt(room);
    var picked = components.length - 1;
    for (var i = 0; i < components.length; i++) {
      final space = components[i].length - counts[i];
      if (roll < space) {
        picked = i;
        break;
      }
      roll -= space;
    }
    counts[picked]++;
    left--;
  }
  return counts;
}

List<List<int>> _grow(
  List<List<int>> neighbors,
  List<List<int>> components,
  List<int> seedCounts,
  math.Random random,
) {
  final n = neighbors.length;
  final label = List<int>.filled(n, -1);
  final frontiers = <List<int>>[];
  for (var c = 0; c < components.length; c++) {
    final seeds = _spreadSeeds(components[c], neighbors, seedCounts[c], random);
    for (final face in seeds) {
      label[face] = frontiers.length;
      frontiers.add([face]);
    }
  }
  final active = List<bool>.filled(frontiers.length, true);
  while (true) {
    var smallest = 1 << 30;
    final ready = <int>[];
    for (var g = 0; g < frontiers.length; g++) {
      if (!active[g]) continue;
      frontiers[g].removeWhere((face) => !_canGrow(face, label, neighbors));
      if (frontiers[g].isEmpty) {
        active[g] = false;
        continue;
      }
      final size = _count(label, g);
      if (size < smallest) {
        smallest = size;
        ready
          ..clear()
          ..add(g);
      } else if (size == smallest) {
        ready.add(g);
      }
    }
    if (ready.isEmpty) break;
    final g = ready[random.nextInt(ready.length)];
    final from = frontiers[g][random.nextInt(frontiers[g].length)];
    final options = [
      for (final face in neighbors[from])
        if (label[face] < 0) face,
    ];
    if (options.isEmpty) {
      frontiers[g].remove(from);
      continue;
    }
    final face = options[random.nextInt(options.length)];
    label[face] = g;
    frontiers[g].add(face);
  }
  _claimLeftovers(label, neighbors, components);
  final groups = <List<int>>[
    for (var g = 0; g < frontiers.length; g++)
      [
        for (var face = 0; face < n; face++)
          if (label[face] == g) face,
      ],
  ]..removeWhere((group) => group.isEmpty);
  groups.sort((a, b) => a.first.compareTo(b.first));
  return groups;
}

bool _canGrow(int face, List<int> label, List<List<int>> neighbors) {
  for (final next in neighbors[face]) {
    if (label[next] < 0) return true;
  }
  return false;
}

int _count(List<int> label, int group) {
  var n = 0;
  for (final held in label) {
    if (held == group) n++;
  }
  return n;
}

/// Seeds spread over [faces], each as far from the ones already placed as
/// the surface allows.
List<int> _spreadSeeds(
  List<int> faces,
  List<List<int>> neighbors,
  int count,
  math.Random random,
) {
  if (faces.isEmpty || count <= 0) return const [];
  final allow = faces.toSet();
  final want = math.min(count, faces.length);
  final seeds = <int>[faces[random.nextInt(faces.length)]];
  var dist = _distances(seeds.first, neighbors, allow);
  while (seeds.length < want) {
    var best = -1;
    final picks = <int>[];
    for (final face in faces) {
      if (seeds.contains(face)) continue;
      final d = dist[face] ?? 0;
      if (d > best) {
        best = d;
        picks
          ..clear()
          ..add(face);
      } else if (d == best) {
        picks.add(face);
      }
    }
    if (picks.isEmpty) break;
    final seed = picks[random.nextInt(picks.length)];
    seeds.add(seed);
    final more = _distances(seed, neighbors, allow);
    for (final face in faces) {
      final d = more[face];
      if (d != null && d < (dist[face] ?? 1 << 30)) dist[face] = d;
    }
  }
  return seeds;
}

Map<int, int> _distances(
  int source,
  List<List<int>> neighbors,
  Set<int> allow,
) {
  final dist = <int, int>{source: 0};
  final queue = <int>[source];
  var head = 0;
  while (head < queue.length) {
    final at = queue[head++];
    final d = dist[at]!;
    for (final next in neighbors[at]) {
      if (!allow.contains(next) || dist.containsKey(next)) continue;
      dist[next] = d + 1;
      queue.add(next);
    }
  }
  return dist;
}

/// A face a seed could not reach takes a neighbor's group.
void _claimLeftovers(
  List<int> label,
  List<List<int>> neighbors,
  List<List<int>> components,
) {
  for (final component in components) {
    final left = [
      for (final face in component)
        if (label[face] < 0) face,
    ];
    var guard = left.length * left.length + 1;
    while (left.isNotEmpty && guard-- > 0) {
      var claimed = false;
      for (var i = left.length - 1; i >= 0; i--) {
        final face = left[i];
        int? group;
        for (final next in neighbors[face]) {
          if (label[next] >= 0) {
            group = label[next];
            break;
          }
        }
        if (group == null) continue;
        label[face] = group;
        left.removeAt(i);
        claimed = true;
      }
      if (!claimed) break;
    }
  }
}

/// Random cube groups of three, two, and one faces. The triple wraps a
/// corner: each face shares an edge with both others, so none are opposite.
List<List<int>> cubeFaceGroups(
  List<List<FaceNeighbor?>> adjacency, {
  required math.Random random,
}) {
  assert(adjacency.length == 6);
  final neighbors = _neighbors(adjacency);
  bool connected(List<int> faces) {
    final seen = <int>{faces.first};
    final queue = [faces.first];
    for (var i = 0; i < queue.length; i++) {
      for (final next in neighbors[queue[i]]) {
        if (faces.contains(next) && seen.add(next)) queue.add(next);
      }
    }
    return seen.length == faces.length;
  }

  final deals = <List<List<int>>>[];
  for (var a = 0; a < 6; a++) {
    for (var b = a + 1; b < 6; b++) {
      for (var c = b + 1; c < 6; c++) {
        final triple = [a, b, c];
        if (!neighbors[a].contains(b) ||
            !neighbors[a].contains(c) ||
            !neighbors[b].contains(c)) {
          continue;
        }
        final rest = [
          for (var f = 0; f < 6; f++)
            if (!triple.contains(f)) f,
        ];
        for (final single in rest) {
          final pair = rest.where((f) => f != single).toList();
          if (connected(pair)) {
            deals.add([
              triple,
              pair,
              [single],
            ]);
          }
        }
      }
    }
  }
  return deals[random.nextInt(deals.length)];
}
