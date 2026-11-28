part of 'controller.dart';

extension Housing on ProtoplaneController {
  MaterialContext contextFor(String planeId) =>
      planes[planeId]?.interior == true
      ? MaterialContext.indoor
      : MaterialContext.outdoor;

  RoomReview reviewRoom(CraftObject room) {
    final source = objectPlane(room);
    final floor = planes['surface-${room.id}-floor-in-0']!;
    final blankets = <(CraftObject, Region)>[];
    final obstacles = <Region>[];
    for (final object in objects.values) {
      if (object.id == room.id) continue;
      final frame = objectPlane(object);
      if (frame.roomId != room.id ||
          !frame.interior ||
          frame.roomFace != 'floor') {
        continue;
      }
      final region = _inFrame(object.region, frame, floor);
      if (object.kind == CraftKind.inflatedCloth &&
          blanketSize(region) != 'cloth padding') {
        blankets.add((object, region));
      }
      if (object.depth > .02) obstacles.add(region);
    }
    const step = RoomReview.step, radius = .035;
    bool free(Offset p) {
      final square = rectangle(
        radius * 2,
        radius * 2,
        origin: p - const Offset(radius, radius),
      );
      if (!floor.region.containsRegion(square)) return false;
      return !obstacles.any((o) => o.overlaps(square));
    }

    final bounds = floor.region.bounds;
    final width = (bounds.width / step).ceil(),
        height = (bounds.height / step).ceil();
    Offset point(int i) => Offset(
      bounds.left + (i % width + .5) * step,
      bounds.top + (i ~/ width + .5) * step,
    );
    final walkable = <int>{
      for (var i = 0; i < width * height; i++)
        if (free(point(i))) i,
    };
    final queue = Queue<int>(), seen = <int>{};
    for (final panel in roomPanels(room, source)) {
      for (final door in room.openings.where(
        (o) => o.kind == 'door' && o.wall == panel.key,
      )) {
        final mouth = doorwayCenter(door.region);
        if (mouth == null) continue;
        final entry = floor.local(
          panel.frame.point(mouth) - panel.frame.normal * .08,
        );
        final outside = panel.frame.point(mouth) + panel.frame.normal * .08;
        if (objects.values.any((o) {
          if (o.id == room.id) return false;
          final p = objectPlane(o), local = p.local(outside);
          final height = (outside - p.origin).dot(p.normal);
          return height > -.01 && height < o.depth && o.region.contains(local);
        })) {
          continue;
        }
        for (final i in walkable) {
          if ((point(i) - entry).distance <= .09 && seen.add(i)) queue.add(i);
        }
      }
    }
    while (queue.isNotEmpty) {
      final i = queue.removeFirst(), x = i % width, y = i ~/ width;
      for (final next in [
        if (x > 0) i - 1,
        if (x + 1 < width) i + 1,
        if (y > 0) i - width,
        if (y + 1 < height) i + width,
      ]) {
        if (walkable.contains(next) && seen.add(next)) queue.add(next);
      }
    }
    final reachable = seen.map(point).toList();
    final places = <SleepingPlace>[];
    for (final (blanket, region) in blankets) {
      final near = reachable
          .where((p) => region.bounds.inflate(.13).contains(p))
          .firstOrNull;
      if (near != null) {
        places.add(
          SleepingPlace(
            blanket,
            region,
            near,
            blanketSize(region) == 'large blanket',
          ),
        );
      }
    }
    return RoomReview(
      room,
      floor,
      reachable,
      places,
      room.openings.any((o) => o.kind == 'window'),
    );
  }

  // Camera movement and previews do not change housing. Reuse the expensive
  // floor flood-fill until objects or their derived support surfaces change.
  List<RoomReview> get roomReviews {
    final current = objects.values.toList();
    if (_roomReviewsCache != null && listEquals(current, _reviewObjects)) {
      return _roomReviewsCache!;
    }
    _reviewObjects = current;
    return _roomReviewsCache = List.unmodifiable([
      for (final r in current.where((o) => o.kind == CraftKind.room))
        reviewRoom(r),
    ]);
  }

  void syncHousing({bool arrivals = true}) {
    final reviews = roomReviews;
    for (final tenant in housing.tenants.values) {
      tenant.usable = false;
      tenant.rating = 0;
    }
    for (final review in reviews) {
      final current = housing.tenants.values
          .where((t) => t.roomId == review.room.id)
          .toList();
      for (final place in review.sleepingPlaces) {
        if (!arrivals || current.any((t) => t.blanketId == place.blanket.id)) {
          continue;
        }
        final rating = review.rating(place, current.length + 1);
        final vacancies = housing.vacancies[review.room.id] ?? [];
        if (vacancies.isNotEmpty) {
          final index = vacancies.indexWhere((prior) => rating > prior);
          if (index < 0) continue;
          vacancies.removeAt(index);
        }
        final id = 'tenant-${housing.nextTenant++}';
        final tenant = Tenant(
          id,
          review.room.id,
          place.blanket.id,
          place.position,
        );
        housing.tenants[id] = tenant;
        current.add(tenant);
        housing.result = 'Cube Boy arrived';
      }
      for (final tenant in current) {
        final place = review.sleepingPlaces
            .where((p) => p.blanket.id == tenant.blanketId)
            .firstOrNull;
        if (place != null) {
          tenant.rating = review.rating(place, current.length);
          tenant.usable = true;
        }
      }
    }
  }

  void advancePhase() {
    finishGesture();
    syncHousing();
    if (housing.phase != DayPhase.evening) {
      housing.phase = DayPhase.values[housing.phase.index + 1];
      housing.result = null;
    } else {
      var rent = 0, departed = 0;
      for (final tenant in housing.tenants.values.toList()) {
        if (tenant.usable) rent += HousingBalance.rent(tenant.rating);
        if (!tenant.usable ||
            housing.roll() < HousingBalance.departure(tenant.rating)) {
          housing.tenants.remove(tenant.id);
          housing.vacancies
              .putIfAbsent(tenant.roomId, () => [])
              .add(tenant.rating);
          departed++;
        }
      }
      housing.coins += rent;
      housing.day++;
      housing.phase = DayPhase.morning;
      housing.result = '+$rent coins · $departed departures';
    }
    _undo.clear();
    _redo.clear();
    error = null;
    onCommitted?.call(toJson());
    _notifyPencil();
  }

  bool buyPaper(PaperMaterial material) {
    if (!material.craftable) return false;
    final price = material.purchasePrice;
    if (housing.coins < price) {
      report('Not enough coins');
      return false;
    }
    final before = _snapshot();
    housing.coins -= price;
    balances[material] = balances[material]! + HousingBalance.packSize;
    error = null;
    _record(before, committed: true);
    _notifyPencil();
    return true;
  }

  bool get canClaimSupplies =>
      housing.tenants.isEmpty &&
      housing.coins < HousingBalance.clothPrice &&
      (balances[PaperMaterial.paperWhite]! < HousingBalance.emergencyBuilding ||
          balances[PaperMaterial.paperGreen]! < HousingBalance.emergencyCloth);
  void claimSupplies() {
    if (!canClaimSupplies) return;
    final before = _snapshot();
    balances[PaperMaterial.paperWhite] = math.max(
      HousingBalance.emergencyBuilding,
      balances[PaperMaterial.paperWhite]!,
    );
    balances[PaperMaterial.paperGreen] = math.max(
      HousingBalance.emergencyCloth,
      balances[PaperMaterial.paperGreen]!,
    );
    _record(before, committed: true);
    _notifyPencil();
  }

  void validateHousing() {
    for (final room in objects.values.where((o) => o.kind == CraftKind.room)) {
      if (room.material != PaperMaterial.paperWhite ||
          room.depth != 1 ||
          room.drawingSpacing != .25) {
        throw const FormatException('Invalid building room');
      }
      final panels = roomPanels(room, objectPlane(room));
      final seen = <RoomOpening>[];
      for (final opening in room.openings) {
        final panel = panels.where((p) => p.key == opening.wall).firstOrNull;
        if (panel == null ||
            !panel.frame.region.containsRegion(opening.region) ||
            panel.regions.isEmpty) {
          throw const FormatException('Invalid room opening');
        }
        if (seen.any(
              (prior) =>
                  prior.wall == opening.wall &&
                  prior.region.overlaps(opening.region),
            ) ||
            (opening.kind == 'door' && doorwayCenter(opening.region) == null)) {
          throw const FormatException('Invalid room opening');
        }
        seen.add(opening);
      }
      for (final expected in roomSurfaces(room, objectPlane(room))) {
        final actual = planes[expected.id];
        if (actual == null ||
            actual.roomId != room.id ||
            actual.interior != expected.interior ||
            actual.roomFace != expected.roomFace ||
            (actual.origin - expected.origin).length > geometryEpsilon ||
            (actual.u - expected.u).length > geometryEpsilon ||
            (actual.v - expected.v).length > geometryEpsilon ||
            jsonEncode(actual.region.toJson()) !=
                jsonEncode(expected.region.toJson())) {
          throw const FormatException('Invalid room surface');
        }
      }
    }
    for (final tenant in housing.tenants.values) {
      final serial = int.tryParse(tenant.id.replaceFirst('tenant-', ''));
      if (!tenant.id.startsWith('tenant-') ||
          serial == null ||
          serial < 1 ||
          serial >= housing.nextTenant) {
        throw const FormatException('Invalid resident identity');
      }
    }
    if (housing.tenants.values.map((t) => t.blanketId).toSet().length !=
        housing.tenants.length) {
      throw const FormatException('Duplicate sleeping assignment');
    }
  }
}
