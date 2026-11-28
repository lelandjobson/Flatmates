import 'dart:ui';
import 'geometry.dart';
import 'models.dart';
import 'housing_balance.dart';
export 'housing_balance.dart';

enum DayPhase { morning, afternoon, evening }

class Tenant {
  Tenant(
    this.id,
    this.roomId,
    this.blanketId,
    this.position, {
    this.rating = 0,
    this.usable = false,
  });
  final String id, roomId, blanketId;
  final Offset position;
  int rating;
  bool usable;
  Map<String, dynamic> toJson() => {
    'id': id,
    'room': roomId,
    'blanket': blanketId,
    'position': [position.dx, position.dy],
    'rating': rating,
    'usable': usable,
  };
  factory Tenant.fromJson(Map<String, dynamic> j) => Tenant(
    j['id'],
    j['room'],
    j['blanket'],
    Offset(
      (j['position'][0] as num).toDouble(),
      (j['position'][1] as num).toDouble(),
    ),
    rating: j['rating'],
    usable: j['usable'],
  );
}

class HousingState {
  int day = 1, coins = 0, seed = 1729, nextTenant = 1;
  DayPhase phase = DayPhase.morning;
  final Map<String, Tenant> tenants = {};
  final Map<String, List<int>> vacancies = {};
  String? result;
  Map<String, dynamic> toJson() => {
    'day': day,
    'phase': phase.name,
    'coins': coins,
    'seed': seed,
    'nextTenant': nextTenant,
    'tenants': tenants.values.map((t) => t.toJson()).toList(),
    'vacancies': {
      for (final entry in vacancies.entries)
        entry.key: List<int>.of(entry.value),
    },
    'result': result,
  };
  static HousingState fromJson(dynamic j) {
    final state = HousingState();
    if (j == null) return state;
    state.day = j['day'];
    state.coins = j['coins'];
    state.seed = j['seed'];
    state.nextTenant = j['nextTenant'];
    if (!DayPhase.values.any((p) => p.name == j['phase'])) {
      throw const FormatException('Invalid day phase');
    }
    state.phase = DayPhase.values.byName(j['phase']);
    state.result = j['result'];
    for (final raw in j['tenants']) {
      final t = Tenant.fromJson(raw);
      if (state.tenants.containsKey(t.id)) {
        throw const FormatException('Duplicate tenant');
      }
      state.tenants[t.id] = t;
    }
    for (final entry in (j['vacancies'] as Map).entries) {
      state.vacancies[entry.key] = (entry.value as List).cast<int>();
    }
    if (state.day < 1 ||
        state.coins < 0 ||
        state.seed < 0 ||
        state.seed > 0x7fffffff ||
        state.nextTenant < 1 ||
        state.tenants.values.any(
          (t) =>
              t.rating < 0 ||
              t.rating > 100 ||
              !t.position.dx.isFinite ||
              !t.position.dy.isFinite,
        ) ||
        state.vacancies.values.expand((v) => v).any((v) => v < 0 || v > 100)) {
      throw const FormatException('Invalid housing state');
    }
    return state;
  }

  double roll() {
    seed = (48271 * (seed == 0 ? 1 : seed)) % 0x7fffffff;
    return seed / 0x80000000;
  }
}

class SleepingPlace {
  SleepingPlace(this.blanket, this.region, this.position, this.large);
  final CraftObject blanket;
  final Region region;
  final Offset position;
  final bool large;
}

class RoomReview {
  RoomReview(
    this.room,
    this.floor,
    this.reachable,
    this.sleepingPlaces,
    this.hasWindow,
  );
  final CraftObject room;
  final CraftPlane floor;
  final List<Offset> reachable;
  final List<SleepingPlace> sleepingPlaces;
  final bool hasWindow;
  static const step = .0625;
  int rating(SleepingPlace place, int occupants) =>
      HousingBalance.baseRating +
      (place.large ? HousingBalance.largeBonus : 0) +
      (hasWindow ? HousingBalance.windowBonus : 0) +
      (reachable.length * step * step >=
              HousingBalance.spacePerResident * occupants
          ? HousingBalance.spaceBonus
          : 0);
}
