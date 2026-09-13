import 'package:flatmates/gameplay/friends/emotion_tone.dart';
import 'package:flatmates/gameplay/friends/friend_desire.dart';
import 'package:flatmates/gameplay/friends/friend_feeling.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every emotion tone has a swatch', () {
    for (final tone in EmotionTone.values) {
      final swatch = emotionSwatch(tone);
      expect(swatch.fill.a, greaterThan(0));
      expect(swatch.stroke.a, greaterThan(0));
      expect(swatch.percolate.a, greaterThan(0));
    }
  });

  test('feelings catalog has typical moods and lookup', () {
    expect(kFeelings.length, greaterThanOrEqualTo(8));
    expect(feelingById('sad')?.icon, '💔');
    expect(feelingById('happy')?.tone, EmotionTone.happy);
    expect(feelingById('missing'), isNull);
    final ids = {for (final feeling in kFeelings) feeling.id};
    expect(ids.length, kFeelings.length);
  });

  test('desires catalog has ten named wants and lookup', () {
    expect(kDesires.length, 10);
    expect(desireById('snack')?.icon, '🍪');
    expect(desireById('nap')?.tone, EmotionTone.sleepy);
    expect(desireById('missing'), isNull);
    final ids = {for (final desire in kDesires) desire.id};
    expect(ids.length, kDesires.length);
  });
}
