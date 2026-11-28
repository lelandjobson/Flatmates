import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/protoplane/parcels.dart';
import 'package:flatmates/protoplane/dev_settings.dart';

void main() {
  test(
    'only edge neighbors are visible and purchasable, buying expands the frontier',
    () {
      final model = ProtoplaneController()..housing.coins = 10000;
      addTearDown(model.dispose);
      final parcels = model.parcels;
      final terrain = model.landscape.terrain;
      const diagonal = ParcelId(1, 1);
      expect(parcels.available(terrain), contains(diagonal));
      expect(parcels.visible(terrain), isNot(contains(diagonal)));
      expect(model.buyParcel(diagonal), isFalse);
      for (final id in parcels.visible(terrain)) {
        expect(
          id == const ParcelId(0, 0) || id.x.abs() + id.y.abs() == 1,
          isTrue,
        );
      }
      expect(model.buyParcel(const ParcelId(1, 0)), isTrue);
      expect(parcels.visible(terrain), contains(diagonal));
      expect(model.buyParcel(diagonal), isTrue);
      final distant = parcels
          .available(terrain)
          .firstWhere(
            (id) => !parcels.purchased.contains(id) && !parcels.isAdjacent(id),
          );
      expect(parcels.visible(terrain), isNot(contains(distant)));
      expect(model.buyParcel(distant), isFalse);
    },
  );

  test(
    'clearing resets purchases, and undo restores the previous parcel world',
    () {
      final model = ProtoplaneController()..housing.coins = 10000;
      addTearDown(model.dispose);
      model.setParcelSize(4);
      model.buyParcel(const ParcelId(1, 0));
      model.clearWorld();
      expect(model.parcels.size, 4);
      expect(model.parcels.purchased, {const ParcelId(0, 0)});
      model.undo();
      expect(model.parcels.purchased.contains(const ParcelId(1, 0)), isTrue);
      model.redo();
      expect(model.parcels.purchased, {const ParcelId(0, 0)});
    },
  );

  test('starter is exactly 3 by 3 and boundaries map without overlap', () {
    final p = WorldParcels();
    expect(p.bounds(const ParcelId(0, 0)), const Rect.fromLTWH(-1, -1, 3, 3));
    expect(p.owns(const Offset(-1, -1)), isTrue);
    expect(p.owns(const Offset(1.999, 1.999)), isTrue);
    expect(p.owns(const Offset(2, 0)), isFalse);
    expect(p.at(const Offset(-1.01, 0)), const ParcelId(-1, 0));
    expect(p.price, 900);
  });
  test(
    'purchases charge coins, persist, and cannot be repeated or fabricated',
    () {
      final model = ProtoplaneController()..housing.coins = 10000;
      final loaded = ProtoplaneController();
      addTearDown(model.dispose);
      addTearDown(loaded.dispose);
      final balance = Map.of(model.balances);
      Map<String, dynamic>? saved;
      model.onCommitted = (json) => saved = json;
      expect(model.buyParcel(const ParcelId(1, 0)), isTrue);
      expect(model.buyParcel(const ParcelId(1, 0)), isFalse);
      expect(model.buyParcel(const ParcelId(500, 500)), isFalse);
      expect(model.balances, balance);
      expect(model.housing.coins, 10000 - model.parcels.price);
      loaded.load(saved!);
      expect(loaded.parcels.purchased, model.parcels.purchased);
      expect(loaded.parcels.size, 3);
    },
  );
  test(
    'parcel resizing also resizes starter and survives settings roundtrip',
    () {
      final model = ProtoplaneController()..housing.coins = 10000;
      addTearDown(model.dispose);
      model.buyParcel(const ParcelId(1, 0));
      model.setParcelSize(5);
      expect(
        model.parcels.bounds(const ParcelId(0, 0)),
        const Rect.fromLTWH(-2, -2, 5, 5),
      );
      expect(model.parcels.purchased.contains(const ParcelId(1, 0)), isTrue);
      expect(model.parcels.price, 2500);
      final settings = ProtoplaneSettings()..parcelSize = 5;
      final loaded = ProtoplaneSettings()..load(settings.toJson());
      expect(loaded.parcelSize, 5);
      expect(loaded.parcelZoomNear, 16);
      expect(loaded.parcelZoomFar, 25);
      expect(
        () => WorldParcels.fromJson({
          'size': 0,
          'purchased': [
            [0, 0],
          ],
        }),
        throwsFormatException,
      );
    },
  );
  test(
    'unowned terrain cannot focus and shared drawing stays in owned tiles',
    () {
      final model = ProtoplaneController()..enableInPlaceDrawing();
      model.housing.coins = 10000;
      addTearDown(model.dispose);
      final locked = model.landscape.terrain.tiles.values.firstWhere(
        (t) => t.x == 2 && t.y == 0 && t.sheet.island == 'starter',
      );
      model.enter(locked.id);
      expect(model.activePlaneId, isNull);
      final owned = model.landscape.terrain.tiles.values.firstWhere(
        (t) => t.x == 0 && t.y == 0 && t.sheet.island == 'starter',
      );
      model.enter(owned.id);
      expect(model.activePlaneId, isNotNull);
      expect(model.activePlane!.supports.every(model.ownsTerrainTile), isTrue);
      model.leave();
      model.buyParcel(const ParcelId(1, 0));
      model.enter(locked.id);
      expect(model.activePlaneId, isNotNull);
    },
  );
}
