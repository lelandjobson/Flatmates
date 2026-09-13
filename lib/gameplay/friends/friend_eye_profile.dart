import 'dart:ui';

import 'friend_expression_pose.dart';

/// Tunable rest-face layout, keyed per friend template.
class FriendEyeProfile {
  const FriendEyeProfile({
    this.spacing = 1,
    this.size = 1,
    this.width = 1,
    this.height = 1,
    this.lift = 0,
  });

  static const defaults = FriendEyeProfile();

  /// How far the eyes sit apart. `1` is the authored rest pose.
  final double spacing;

  /// Uniform scale of each eye around its center.
  final double size;

  /// Extra horizontal squash / stretch after [size].
  final double width;

  /// Extra vertical squash / stretch after [size].
  final double height;

  /// Face-plane lift. Positive moves eyes up.
  final double lift;

  FriendEyeProfile copyWith({
    double? spacing,
    double? size,
    double? width,
    double? height,
    double? lift,
  }) {
    return FriendEyeProfile(
      spacing: spacing ?? this.spacing,
      size: size ?? this.size,
      width: width ?? this.width,
      height: height ?? this.height,
      lift: lift ?? this.lift,
    );
  }

  FriendEyeProfile clamped() {
    return FriendEyeProfile(
      spacing: spacing.clamp(0.35, 2.2),
      size: size.clamp(0.25, 2.8),
      width: width.clamp(0.25, 2.8),
      height: height.clamp(0.25, 2.8),
      lift: lift.clamp(-0.6, 0.6),
    );
  }

  FriendExpressionPose apply(FriendExpressionPose pose) {
    return FriendExpressionPose(
      id: pose.id,
      left: _applyEye(pose.left),
      right: _applyEye(pose.right),
    );
  }

  EyeBlob _applyEye(EyeBlob eye) {
    final origin = eye.center;
    final center = Offset(origin.dx * spacing, origin.dy + lift);
    final sx = size * width;
    final sy = size * height;
    return EyeBlob([
      for (final p in eye.ring)
        Offset(
          center.dx + (p.dx - origin.dx) * sx,
          center.dy + (p.dy - origin.dy) * sy,
        ),
    ]);
  }

  Map<String, double> toJson() => {
        'spacing': spacing,
        'size': size,
        'width': width,
        'height': height,
        'lift': lift,
      };

  factory FriendEyeProfile.fromJson(Map<String, dynamic> json) {
    double read(String key, double fallback) {
      final value = json[key];
      if (value is num) return value.toDouble();
      return fallback;
    }

    return FriendEyeProfile(
      spacing: read('spacing', 1),
      size: read('size', 1),
      width: read('width', 1),
      height: read('height', 1),
      lift: read('lift', 0),
    ).clamped();
  }

  @override
  bool operator ==(Object other) {
    return other is FriendEyeProfile &&
        other.spacing == spacing &&
        other.size == size &&
        other.width == width &&
        other.height == height &&
        other.lift == lift;
  }

  @override
  int get hashCode => Object.hash(spacing, size, width, height, lift);
}
