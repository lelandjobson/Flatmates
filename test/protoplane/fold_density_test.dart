import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/protoplane/crumpled_paper.dart';
import 'package:flatmates/protoplane/dev_settings.dart';
import 'package:flatmates/protoplane/harvest_meshes.dart';

void main() {
  test('fold distribution settings migrate, validate and stage', () {
    final settings = ProtoplaneSettings();
    final old = settings.toJson()
      ..remove('foldDensity')
      ..remove('foldDistribution');
    settings.load(old);
    expect(settings.foldDensity, .65);
    expect(settings.foldDistribution, FoldDistribution.pockets);
    final draft = LandscapeStyleDraft(settings)
      ..foldDensity = .4
      ..foldDistribution = FoldDistribution.scattered;
    expect(settings.foldDensity, .65);
    draft.applyTo(settings);
    final restored = ProtoplaneSettings()..load(settings.toJson());
    expect(restored.foldDensity, .4);
    expect(restored.foldDistribution, FoldDistribution.scattered);
    for (final invalid in [-.1, 1.1, double.nan]) {
      expect(
        () => settings.load(restored.toJson()..['foldDensity'] = invalid),
        throwsFormatException,
      );
    }
    expect(
      () => settings.load(restored.toJson()..['foldDistribution'] = 'missing'),
      throwsFormatException,
    );
  });
  testWidgets('density pockets are stable across tiles, monotonic and cached', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final c = ProtoplaneController(), cache = HarvestMeshCache();
      final images = <ui.Image>[];
      try {
        cache.setCrumpledPaper(await CrumpledPaperResources.load());
        Future<ui.Image> bake(double density, FoldDistribution style) async {
          cache.configureCrumple(
            strength: 1,
            scale: 1,
            shadow: 1,
            density: density,
            distribution: style,
          );
          cache.synchronize(c.planes.values, c.landscape);
          final recorder = ui.PictureRecorder();
          // Four tiles in each direction make the distribution visible at world scale.
          final out = ui.Canvas(recorder);
          for (var y = -2; y < 2; y++) {
            for (var x = -2; x < 2; x++) {
              final p = c.planes['ground-starter-paperWhite-$x-$y']!;
              final source = cache.mesh(p, c.landscape).planarTexture!.source;
              out.drawImageRect(
                cache.atlas.image!,
                source,
                ui.Rect.fromLTWH((x + 2) * 128.0, (y + 2) * 128.0, 128, 128),
                ui.Paint(),
              );
            }
          }
          final picture = recorder.endRecording();
          final image = await picture.toImage(512, 512);
          picture.dispose();
          images.add(image);
          return image;
        }

        final smooth = await bake(0, FoldDistribution.pockets);
        final base = (await smooth.toByteData())!.buffer.asUint8List();
        Future<int> changed(ui.Image image) async {
          final bytes = (await image.toByteData())!.buffer.asUint8List();
          var count = 0;
          for (var i = 0; i < bytes.length; i += 4) {
            if ((bytes[i] - base[i]).abs() > 3) count++;
          }
          return count;
        }

        final sparse = await bake(.3, FoldDistribution.pockets);
        final pockets = await bake(.55, FoldDistribution.pockets);
        final full = await bake(1, FoldDistribution.pockets);
        expect(await changed(sparse), lessThan(await changed(pockets)));
        expect(await changed(pockets), lessThan(await changed(full)));
        final scattered = await bake(.55, FoldDistribution.scattered);
        expect(
          (await scattered.toByteData())!.buffer.asUint8List(),
          isNot((await pockets.toByteData())!.buffer.asUint8List()),
        );
        final bakes = cache.crumpleBakes, atlas = cache.atlas.image;
        for (var i = 0; i < 120; i++) {
          cache.configureCrumple(
            strength: 1,
            scale: 1,
            shadow: 1,
            density: .55,
            distribution: FoldDistribution.scattered,
          );
          cache.synchronize(c.planes.values, c.landscape);
        }
        expect(cache.crumpleBakes, bakes);
        expect(cache.atlas.image, same(atlas));
        final repeat = await bake(.55, FoldDistribution.pockets);
        expect(
          (await repeat.toByteData())!.buffer.asUint8List(),
          (await pockets.toByteData())!.buffer.asUint8List(),
        );
        final recorder = ui.PictureRecorder();
        final out = ui.Canvas(recorder);
        for (final (i, image) in [full, pockets, scattered].indexed) {
          out.drawImage(image, ui.Offset(i * 512.0, 0), ui.Paint());
        }
        final picture = recorder.endRecording();
        final comparison = await picture.toImage(1536, 512);
        picture.dispose();
        images.add(comparison);
        final path = '${Directory.systemTemp.path}/flatmates-fold-density.png';
        await File(path).writeAsBytes(
          (await comparison.toByteData(
            format: ui.ImageByteFormat.png,
          ))!.buffer.asUint8List(),
        );
        // ignore: avoid_print
        print('Fold comparison: $path');
      } finally {
        for (final image in images) {
          image.dispose();
        }
        cache.dispose();
        c.dispose();
      }
    });
  });
}
