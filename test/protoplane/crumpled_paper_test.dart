import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/crumpled_paper.dart';
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/protoplane/dev_settings.dart';
import 'package:flatmates/protoplane/geometry.dart';
import 'package:flatmates/protoplane/harvest_meshes.dart';
import 'package:flatmates/protoplane/models.dart';
import 'package:flatmates/protoplane/meshes.dart';
import 'layered_terrain_test.dart' show centerId;

Future<ui.Image> crop(
  HarvestMeshCache cache,
  ProtoplaneController c,
  String id,
) async {
  final source = cache.mesh(c.planes[id]!, c.landscape).planarTexture!.source;
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawImageRect(
    cache.atlas.image!,
    source,
    const ui.Rect.fromLTWH(0, 0, 256, 256),
    ui.Paint(),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(256, 256);
  picture.dispose();
  return image;
}

Future<Uint8List> pixels(ui.Image image) async =>
    (await image.toByteData())!.buffer.asUint8List();
double difference(Uint8List a, Uint8List b) {
  var sum = 0.0;
  for (var i = 0; i < a.length; i += 4) {
    sum += (a[i] - b[i]).abs();
  }
  return sum / (a.length / 4);
}

void main() {
  test('fold settings migrate, validate and stage until Update', () {
    final settings = ProtoplaneSettings();
    final legacy = settings.toJson()
      ..remove('foldStrength')
      ..remove('foldScale')
      ..remove('bakedShadowIntensity');
    settings.load(legacy);
    expect(settings.foldStrength, 1);
    expect(settings.foldScale, 1);
    expect(settings.bakedShadowIntensity, 1);
    final draft = LandscapeStyleDraft(settings)
      ..foldStrength = 1.6
      ..foldScale = 2
      ..bakedShadowIntensity = .4;
    expect(settings.foldStrength, 1);
    draft.applyTo(settings);
    final loaded = ProtoplaneSettings()..load(settings.toJson());
    expect(loaded.foldStrength, 1.6);
    expect(loaded.foldScale, 2);
    expect(loaded.bakedShadowIntensity, .4);
    expect(
      () => ProtoplaneSettings().load(settings.toJson()..['foldScale'] = 0),
      throwsFormatException,
    );
    expect(
      () => ProtoplaneSettings().load(
        settings.toJson()..['foldStrength'] = double.nan,
      ),
      throwsFormatException,
    );
  });
  testWidgets(
    'folds bake only on natural white paper, clip holes, cache camera movement and obey controls',
    (tester) async {
      await tester.runAsync(() async {
        final c = ProtoplaneController(), cache = HarvestMeshCache();
        final images = <ui.Image>[];
        try {
          final white = centerId(c, PaperMaterial.paperWhite),
              graphite = centerId(c, PaperMaterial.graphite),
              cork = centerId(c, PaperMaterial.cork);
          cache.synchronize(c.planes.values, c.landscape);
          final smooth = await crop(cache, c, white);
          images.add(smooth);
          final smoothBytes = await pixels(smooth);
          final graphiteBefore = await crop(cache, c, graphite),
              corkBefore = await crop(cache, c, cork);
          images.addAll([graphiteBefore, corkBefore]);
          final initial = cache.rasterizedTiles;
          cache.setCrumpledPaper(await CrumpledPaperResources.load());
          final watch = Stopwatch()..start();
          cache.synchronize(c.planes.values, c.landscape);
          watch.stop();
          final count = c.landscape.terrain.tiles.values
              .where((t) => t.sheet.material == PaperMaterial.paperWhite)
              .length;
          expect(cache.rasterizedTiles - initial, count);
          expect(cache.crumpleBakes, count);
          final folded = await crop(cache, c, white);
          images.add(folded);
          final foldedBytes = await pixels(folded);
          expect(difference(smoothBytes, foldedBytes), greaterThan(3));
          final graphiteAfter = await crop(cache, c, graphite),
              corkAfter = await crop(cache, c, cork);
          images.addAll([graphiteAfter, corkAfter]);
          expect(await pixels(graphiteBefore), await pixels(graphiteAfter));
          expect(await pixels(corkBefore), await pixels(corkAfter));
          final atlas = cache.atlas.image,
              bakes = cache.crumpleBakes,
              rasters = cache.rasterizedTiles;
          for (var i = 0; i < 120; i++) {
            cache.configureCrumple(strength: 1, scale: 1, shadow: 1);
            cache.synchronize(c.planes.values, c.landscape);
          }
          expect(cache.atlas.image, same(atlas));
          expect(cache.crumpleBakes, bakes);
          expect(cache.rasterizedTiles, rasters);
          cache.configureCrumple(strength: 1, scale: 2, shadow: 1);
          cache.synchronize(c.planes.values, c.landscape);
          final large = await crop(cache, c, white);
          images.add(large);
          expect(difference(foldedBytes, await pixels(large)), greaterThan(3));
          cache.configureCrumple(strength: 1, scale: 1, shadow: 0);
          cache.synchronize(c.planes.values, c.landscape);
          final unshadowed = await crop(cache, c, white);
          images.add(unshadowed);
          expect(
            difference(foldedBytes, await pixels(unshadowed)),
            greaterThan(.1),
          );
          cache.configureCrumple(strength: 0, scale: 1, shadow: 1);
          cache.synchronize(c.planes.values, c.landscape);
          final off = await crop(cache, c, white);
          images.add(off);
          expect(await pixels(off), smoothBytes);
          cache.configureCrumple(strength: 1, scale: 1, shadow: 1);
          c.landscape.deplete(
            white,
            Region([
              const ui.Offset(.25, .25),
              const ui.Offset(.75, .25),
              const ui.Offset(.75, .75),
              const ui.Offset(.25, .75),
            ]),
          );
          cache.synchronize(c.planes.values, c.landscape);
          final cut = await crop(cache, c, white);
          images.add(cut);
          final cutBytes = await pixels(cut);
          expect(cutBytes[(128 * 256 + 128) * 4 + 3], 0);
          expect(cutBytes[(20 * 256 + 20) * 4 + 3], 255);
          final object = CraftObject(
            id: 'placed',
            planeId: white,
            kind: CraftKind.floor,
            region: c.planes[white]!.region,
            material: PaperMaterial.paperWhite,
          );
          final meshes = objectMeshes(object, c.planes[white]!);
          expect(
            meshes.every(
              (m) => m.planarTexture == null && m.surfaceTexture == null,
            ),
            isTrue,
          );
          final recorder = ui.PictureRecorder();
          // Export the real atlas output for visual inspection.
          final output = ui.Canvas(recorder);
          for (var i = 0; i < 3; i++) {
            output.drawImage(
              [smooth, folded, large][i],
              ui.Offset(i * 256.0, 0),
              ui.Paint(),
            );
          }
          final picture = recorder.endRecording();
          final comparison = await picture.toImage(768, 256);
          picture.dispose();
          images.add(comparison);
          await File(
            '${Directory.systemTemp.path}/flatmates-crumple-baked.png',
          ).writeAsBytes(
            (await comparison.toByteData(
              format: ui.ImageByteFormat.png,
            ))!.buffer.asUint8List(),
          );
          // CPU submission timing only, not device GPU frame latency.
          // ignore: avoid_print
          print(
            'Crumple atlas: $count white tiles submitted in ${watch.elapsedMilliseconds} ms; 120 cache passes added zero bakes',
          );
        } finally {
          for (final im in images) {
            im.dispose();
          }
          cache.dispose();
          c.dispose();
        }
      });
    },
  );
}
