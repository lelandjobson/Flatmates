import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../scene/camera.dart' as scene_camera;
import 'friend_expression.dart';
import 'iso_projection.dart';

/// Paints friend eyes in 2.5D as a separate pass using vector geometry.
///
/// Uses the same projection math as [IsoVectorGenerator] so eyes align with
/// the pre-rendered body sprite. Applies [FriendExpressionState] (blink,
/// expression type) at runtime.
class ExpressionPainter2D {
  ExpressionPainter2D._();

  /// Sprite size used when generating friend sprites (must match generator).
  static const Size _spriteSize = Size(
    IsoProjection.tileWidth,
    IsoProjection.tileHeight,
  );

  /// Camera distance and orthographic scale (must match iso_vector_generator).
  static const double _cameraDistance = 200.0;
  static const double _orthographicScale = 181.0;

  /// World view angle in degrees for a given world view index (matches generator).
  static double worldViewAngleDeg(int worldViewIndex, int viewCount) {
    final step = 360.0 / viewCount;
    return (45.0 - IsoProjection.baseAngleDeg - worldViewIndex * step + 720.0) %
        360.0;
  }

  /// Draw eyes on [canvas] in screen space.
  ///
  /// [config] defines eye layout; [state] defines blink and expression type.
  /// [cameraAngleRad] is the 3D camera angle in radians (same convention as
  /// iso_vector_generator). [meshRotationRad] is the friend facing in radians.
  /// [screenCenter] and [screenSize] define the rect where the body sprite is
  /// drawn (same as body draw rect).
  static void draw(
    Canvas canvas,
    FriendExpressionConfig config,
    FriendExpressionState state, {
    required double cameraAngleRad,
    required double meshRotationRad,
    required Offset screenCenter,
    required Size screenSize,
    double opacity = 1.0,
  }) {
    final mvp = _buildMVP(cameraAngleRad);
    final halfSpacing = config.eyeSpacing / 2;
    final forwardX = math.sin(meshRotationRad);
    final forwardZ = math.cos(meshRotationRad);
    final rightX = forwardZ;
    final rightZ = -forwardX;

    final gazeShift = state.gazeOffset * config.eyeRadiusX * 1.5;

    final leftEye = Vector3(
      rightX * (-halfSpacing + gazeShift) + forwardX * config.eyeForwardOffset,
      config.eyeHeight,
      rightZ * (-halfSpacing + gazeShift) + forwardZ * config.eyeForwardOffset,
    );
    final rightEye = Vector3(
      rightX * (halfSpacing + gazeShift) + forwardX * config.eyeForwardOffset,
      config.eyeHeight,
      rightZ * (halfSpacing + gazeShift) + forwardZ * config.eyeForwardOffset,
    );

    final leftScreen = _projectToScreen(leftEye, mvp, _spriteSize);
    final rightScreen = _projectToScreen(rightEye, mvp, _spriteSize);
    if (leftScreen == null || rightScreen == null) return;

    final camRightX = -math.sin(cameraAngleRad);
    final camRightZ = math.cos(cameraAngleRad);

    final leftUp = _projectToScreen(
      Vector3(leftEye.x, leftEye.y + config.eyeRadiusY, leftEye.z),
      mvp,
      _spriteSize,
    );
    final leftRight = _projectToScreen(
      Vector3(
        leftEye.x + camRightX * config.eyeRadiusX,
        leftEye.y,
        leftEye.z + camRightZ * config.eyeRadiusX,
      ),
      mvp,
      _spriteSize,
    );
    if (leftUp == null || leftRight == null) return;

    var projRX = (leftScreen - leftRight).distance;
    var projRY = (leftScreen - leftUp).distance;

    // Blink: scale vertical radius (applied first so emotions "hold" and blink modulates)
    projRY *= state.blinkOpen.clamp(0.0, 1.0);

    // Expression type: slant (anger/sadness) and squint (perplexed/wow)
    final slantRad = _slantForExpression(state.expressionType);
    final (double squintX, double squintY) = _squintForExpression(state.expressionType);
    projRX *= squintX;
    projRY *= squintY;

    // Map from sprite space to screen space
    final scaleX = screenSize.width / _spriteSize.width;
    final scaleY = screenSize.height / _spriteSize.height;
    final spriteCenter = Offset(_spriteSize.width / 2, _spriteSize.height / 2);

    final leftScreenPos = screenCenter +
        Offset(
          (leftScreen.dx - spriteCenter.dx) * scaleX,
          (leftScreen.dy - spriteCenter.dy) * scaleY,
        );
    final rightScreenPos = screenCenter +
        Offset(
          (rightScreen.dx - spriteCenter.dx) * scaleX,
          (rightScreen.dy - spriteCenter.dy) * scaleY,
        );

    final projRXScreen = projRX * scaleX;
    final projRYScreen = projRY * scaleY;

    final eyeColor = opacity < 1.0
        ? config.eyeColor.withOpacity(config.eyeColor.opacity * opacity)
        : config.eyeColor;
    final eyePaint = Paint()
      ..color = eyeColor
      ..style = PaintingStyle.fill;

    if (state.blinkOpen < 0.01) {
      // Fully closed: draw a line
      final linePaint = Paint()
        ..color = eyeColor
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;
      canvas.drawLine(leftScreenPos, leftScreenPos + Offset(projRXScreen * 2, 0), linePaint);
      canvas.drawLine(rightScreenPos, rightScreenPos + Offset(projRXScreen * 2, 0), linePaint);
      return;
    }

    _drawEye(canvas, leftScreenPos, projRXScreen, projRYScreen, slantRad, eyePaint);
    _drawEye(canvas, rightScreenPos, projRXScreen, projRYScreen, slantRad, eyePaint);
  }

  static void _drawEye(
    Canvas canvas,
    Offset center,
    double rx,
    double ry,
    double slantRad,
    Paint paint,
  ) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    if (slantRad != 0) canvas.rotate(slantRad);
    canvas.scale(rx, ry);
    canvas.drawOval(const Rect.fromLTWH(-1, -1, 2, 2), paint);
    canvas.restore();
  }

  static double _slantForExpression(ExpressionType type) {
    switch (type) {
      case ExpressionType.anger:
        return 0.15; // Downward slant (scowling)
      case ExpressionType.sadness:
        return -0.15; // Opposite of anger (outer corners down)
      case ExpressionType.smile:
        return -0.1; // Slight upward slant
      case ExpressionType.indifference:
      case ExpressionType.neutral:
      case ExpressionType.perplexed:
      case ExpressionType.wow:
        return 0.0;
    }
  }

  /// Squint multipliers (scaleX, scaleY) for eye shape per expression.
  /// Applied after blink so emotions hold and blink still closes eyes.
  static (double, double) _squintForExpression(ExpressionType type) =>
      squintMultipliersForExpression(type);

  static Matrix4 _buildMVP(double cameraAngleRad) {
    final cameraPos = Vector3(
      _cameraDistance * math.cos(cameraAngleRad),
      _cameraDistance * 0.6,
      _cameraDistance * math.sin(cameraAngleRad),
    );
    final camera = scene_camera.Camera(
      name: 'expr-cam',
      position: cameraPos,
      target: Vector3.zero(),
      projection: scene_camera.ProjectionType.orthographic,
      orthographicScale: _orthographicScale,
      near: 0.1,
      far: 1000,
    );
    final aspect = _spriteSize.width / _spriteSize.height;
    final projection = camera.projectionMatrix(aspect);
    final view = camera.viewMatrix;
    return projection * view;
  }

  static Offset? _projectToScreen(Vector3 worldPos, Matrix4 mvp, Size size) {
    final clip = _transformPosition(mvp, worldPos);
    if (clip.w.abs() <= 1e-3) return null;
    final ndcX = clip.x / clip.w;
    final ndcY = clip.y / clip.w;
    if (!ndcX.isFinite || !ndcY.isFinite) return null;
    final screenX = (ndcX * 0.5 + 0.5) * size.width;
    final screenY = (1 - (ndcY * 0.5 + 0.5)) * size.height;
    return Offset(screenX, screenY);
  }

  static Vector4 _transformPosition(Matrix4 matrix, Vector3 position) {
    final s = matrix.storage;
    return Vector4(
      s[0] * position.x + s[4] * position.y + s[8] * position.z + s[12],
      s[1] * position.x + s[5] * position.y + s[9] * position.z + s[13],
      s[2] * position.x + s[6] * position.y + s[10] * position.z + s[14],
      s[3] * position.x + s[7] * position.y + s[11] * position.z + s[15],
    );
  }
}
