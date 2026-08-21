import 'package:flatmates/crafting/placed_paper.dart';
import 'package:flatmates/gameplay/paint/face_paint_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fill floods empty region and stops at drawn pixels', () {
    final canvas = FaceCanvas(width: 5, height: 5);
    canvas.paint(2, 0, PaperColor.yellow);
    canvas.paint(2, 1, PaperColor.yellow);
    canvas.paint(2, 2, PaperColor.yellow);
    canvas.paint(2, 3, PaperColor.yellow);
    canvas.paint(2, 4, PaperColor.yellow);

    expect(canvas.fill(0, 2, PaperColor.pink), isTrue);
    expect(canvas.colorAt(0, 2), PaperColor.pink);
    expect(canvas.colorAt(1, 4), PaperColor.pink);
    expect(canvas.colorAt(2, 2), PaperColor.yellow);
    expect(canvas.colorAt(4, 2), isNull);

    expect(canvas.fill(4, 2, PaperColor.green), isTrue);
    expect(canvas.colorAt(4, 2), PaperColor.green);
    expect(canvas.colorAt(3, 0), PaperColor.green);
    expect(canvas.colorAt(1, 0), PaperColor.pink);

    expect(canvas.fill(2, 2, PaperColor.green), isTrue);
    expect(canvas.colorAt(2, 2), PaperColor.green);
    expect(canvas.colorAt(2, 1), PaperColor.yellow);
  });
}
