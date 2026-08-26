import 'package:vector_math/vector_math_64.dart';

import 'friend_instance.dart';

/// Session-only placed friends in the 3D GameView.
class FriendInstanceStore {
  final List<FriendInstance> instances = [];

  FriendInstance? byId(String id) {
    for (final instance in instances) {
      if (instance.id == id) return instance;
    }
    return null;
  }

  void add(FriendInstance instance) => instances.add(instance);

  bool remove(String id) {
    final before = instances.length;
    instances.removeWhere((instance) => instance.id == id);
    return instances.length != before;
  }

  void translate(String id, Vector3 delta) {
    final instance = byId(id);
    if (instance == null) return;
    instance.position.add(delta);
  }

  void restore(Iterable<FriendInstance> next) {
    instances
      ..clear()
      ..addAll(next);
  }
}
