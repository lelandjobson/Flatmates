import 'package:flatmates/asmr/asmr_scrub.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  bool feed(AsmrScrub scrub, List<Offset> points, {int stepMs = 16}) {
    var time = Duration.zero;
    var fired = false;
    for (final point in points) {
      fired = scrub.add(time, point) || fired;
      time += Duration(milliseconds: stepMs);
    }
    return fired;
  }

  test('two fast reversals are a scrub', () {
    final scrub = AsmrScrub();
    expect(
      feed(scrub, const [
        Offset(0, 0),
        Offset(48, 0),
        Offset(0, 0),
        Offset(48, 0),
      ]),
      isTrue,
    );
  });

  test('one reversal is not a scrub yet', () {
    final scrub = AsmrScrub();
    expect(
      feed(scrub, const [Offset(0, 0), Offset(48, 0), Offset(0, 0)]),
      isFalse,
    );
  });

  test('a slow zigzag is not a scrub', () {
    final scrub = AsmrScrub();
    expect(
      feed(scrub, const [
        Offset(0, 0),
        Offset(4, 0),
        Offset(0, 0),
        Offset(4, 0),
        Offset(0, 0),
      ]),
      isFalse,
    );
  });

  test('a pause breaks the scrub', () {
    final scrub = AsmrScrub();
    expect(scrub.add(Duration.zero, Offset.zero), isFalse);
    expect(
      scrub.add(const Duration(milliseconds: 16), const Offset(48, 0)),
      isFalse,
    );
    expect(scrub.add(const Duration(milliseconds: 32), Offset.zero), isFalse);
    expect(
      scrub.add(const Duration(milliseconds: 200), const Offset(48, 0)),
      isFalse,
    );
    expect(scrub.add(const Duration(milliseconds: 216), Offset.zero), isFalse);
    expect(
      scrub.add(const Duration(milliseconds: 232), const Offset(48, 0)),
      isFalse,
    );
  });
}
