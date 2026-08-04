import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart';

import '../geometry/transformable.dart';

class DirectionalLight extends Transformable {
  DirectionalLight({
    required this.color,
    required this.intensity,
    required Vector3 direction,
    Vector3? position,
  }) : direction = direction.normalized(),
       super(position: position);

  final Color color;
  final double intensity;
  final Vector3 direction;
}
