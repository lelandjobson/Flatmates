import 'package:flatmates/gameplay/viewers/zoom_to_focus.dart';
import 'package:flatmates/rendering/scene/camera.dart';
import 'package:flatmates/rendering/scene/map_look_camera_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

MapLookCameraController _look({double min = 15, double distance = 42}) {
  final camera = Camera(
    name: 'zoom',
    position: Vector3(10, 20, 10),
    target: Vector3.zero(),
  );
  final look = MapLookCameraController(
    camera: camera,
    vsync: const TestVSync(),
    lookAt: Vector3.zero(),
    distance: distance,
    minDistance: min,
    maxDistance: 80,
    ladderZoom: false,
  );
  addTearDown(look.dispose);
  return look;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('game close zoom hard-stops at 12.9 when min is 15', () {
    expect(kZoomToFocusHold, const Duration(milliseconds: 200));
    final look = _look();
    expect(look.closeLimitDistance, closeTo(12.9, 1e-9));
    look.beginZoom();
    look.zoomByScale(20);
    expect(look.distance, closeTo(look.closeLimitDistance, 1e-6));
    expect(look.distance, greaterThanOrEqualTo(look.closeLimitDistance));
    expect(look.isPushingPastCloseLimit, isTrue);
  });

  test('releasing zoom clears the close-limit push', () {
    final look = _look();
    look.beginZoom();
    look.zoomByScale(20);
    expect(look.isPushingPastCloseLimit, isTrue);
    look.endZoom();
    expect(look.isPushingPastCloseLimit, isFalse);
  });

  test('zoom-out past min is not a close-limit push', () {
    final look = _look(distance: 16);
    look.beginZoom();
    look.zoomByScale(0.5);
    expect(look.distance, greaterThan(look.minDistance));
    expect(look.isPushingPastCloseLimit, isFalse);
  });
}
