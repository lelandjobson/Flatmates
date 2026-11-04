import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/appearance.dart';
import 'package:flatmates/protoplane/dev_settings.dart';

void main() {
  test('neutral appearance and old settings preserve existing colors', () {
    final a = SurfaceAppearance();
    expect(a.filter, isNull);
    final identity = [
      1,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ];
    for (var i = 0; i < 20; i++) {
      expect(a.matrix[i], closeTo(identity[i], 1e-8));
    }
    final settings = ProtoplaneSettings();
    settings.load(
      settings.toJson()
        ..remove('landscapeAppearance')
        ..remove('craftedAppearance'),
    );
    expect(settings.landscapeAppearance.neutral, isTrue);
  });
  test('brightness and contrast adjust RGB while preserving alpha', () {
    final a = SurfaceAppearance()
      ..brightness = .2
      ..contrast = 0
      ..hue = 90
      ..saturation = .4;
    final matrix = a.matrix;
    expect(matrix.sublist(15), [0, 0, 0, 1, 0]);
    expect(matrix[0], 0);
    expect(matrix[6], 0);
    expect(matrix[12], 0);
    for (final index in [4, 9, 14]) {
      expect(matrix[index], closeTo(178.5, 1e-8));
    }
    final settings = ProtoplaneSettings()..landscapeAppearance = a;
    final copy = ProtoplaneSettings()..load(settings.toJson());
    expect(copy.landscapeAppearance.toJson(), a.toJson());
    expect(copy.craftedAppearance.neutral, isTrue);
    final legacy = SurfaceAppearance.fromJson({
      'darkFade': .8,
      'lightFade': .2,
      'hue': 30,
      'saturation': .5,
    });
    expect(legacy.brightness, 0);
    expect(legacy.contrast, 1);
    expect(legacy.hue, 30);
    expect(legacy.saturation, .5);
    final high = SurfaceAppearance()..contrast = 2;
    expect(high.matrix[0], closeTo(2, 1e-8));
    expect(high.matrix[4], closeTo(-127.5, 1e-8));
    expect(
      () => SurfaceAppearance.fromJson({'contrast': -1}),
      throwsFormatException,
    );
    expect(
      () => SurfaceAppearance.fromJson({'hue': double.nan}),
      throwsFormatException,
    );
  });
}
