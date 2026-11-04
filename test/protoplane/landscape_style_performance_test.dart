import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flatmates/landscape/color_texture_catalog.dart';
import 'package:flatmates/protoplane/dev_settings.dart';
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/protoplane/harvest_meshes.dart';

void main() {
  testWidgets('landscape slider updates retain the existing atlas', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final image = await ColorTextureCatalog.load(ColorTextureCatalog.white);
      final model = ProtoplaneController(), cache = HarvestMeshCache();
      try {
        final settings = ProtoplaneSettings();
        void configure() => cache.configureStyle(
          fill: settings.landscapeAppearance,
          grain: settings.paperTextureAppearance,
          strength: settings.paperTextureStrength,
          repeat: settings.paperTextureRepeat,
        );
        cache.setPaperTexture(image);
        configure();
        final draft = LandscapeStyleDraft(settings);
        cache.synchronize(model.planes.values, model.landscape);
        final before = cache.rasterizedTiles;
        final atlas = cache.atlas.image;
        final clock = Stopwatch()..start();
        for (var i = 0; i < 16; i++) {
          draft.strength = i / 16;
          draft.repeat = .5 + i / 8;
          draft.grain.brightness = i / 100;
          draft.grain.contrast = 1 + i / 100;
          configure();
          cache.synchronize(model.planes.values, model.landscape);
        }
        clock.stop();
        // Report CPU update/raster time, not device GPU frame latency.
        debugPrint(
          'Landscape slider CPU: ${clock.elapsedMicroseconds} us / 16 updates; ${cache.rasterizedTiles - before} tiles rasterized',
        );
        expect(cache.rasterizedTiles, before);
        expect(identical(cache.atlas.image, atlas), isTrue);
        expect(settings.paperTextureStrength, .6);
        final applyClock = Stopwatch()..start();
        draft.applyTo(settings);
        configure();
        cache.synchronize(model.planes.values, model.landscape);
        applyClock.stop();
        expect(cache.rasterizedTiles - before, 64);
        debugPrint(
          'Landscape Update CPU: ${applyClock.elapsedMicroseconds} us; ${cache.rasterizedTiles - before} tiles rasterized once',
        );
        draft.grain.brightness = .9;
        expect(settings.paperTextureAppearance.brightness, .15);
      } finally {
        cache.dispose();
        image?.dispose();
        model.dispose();
      }
    });
  });
}
