import 'dart:math' as math;
import 'dart:ui' show Color;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Colors;
import '../geometry/prefabs/prefab_factory.dart';
import '../rendering/iso/friend_expression.dart';

/// Stats for a friend
class FriendStats {
  const FriendStats({
    required this.tileSpeed,
    this.viewRadius = 2,
  });

  /// How many tiles per second the friend can move
  final double tileSpeed;

  /// Chebyshev vision radius in tiles. `2` sees two tiles in every direction.
  final int viewRadius;

  FriendStats copyWith({double? tileSpeed, int? viewRadius}) {
    return FriendStats(
      tileSpeed: tileSpeed ?? this.tileSpeed,
      viewRadius: viewRadius ?? this.viewRadius,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FriendStats &&
          runtimeType == other.runtimeType &&
          tileSpeed == other.tileSpeed &&
          viewRadius == other.viewRadius;

  @override
  int get hashCode => Object.hash(tileSpeed, viewRadius);
}

/// Represents a friend available to the player
class Friend {
  const Friend({
    required this.id,
    required this.name,
    required this.geometryType,
    required this.stats,
    required this.color,
    this.expressionName,
  });

  final String id;
  final String name;
  final GeometryPrefabs geometryType;
  final FriendStats stats;

  /// Display colour for this friend (used for sprite tint, path colour, etc.)
  final Color color;

  /// Optional name of a registered expression in [ExpressionRegistry].
  /// When set, [expression] resolves via the registry; when null, falls back
  /// to the geometry-type default.
  final String? expressionName;

  /// Resolve this friend's expression config.
  ///
  /// Priority:
  /// 1. Registry lookup by [expressionName] (if set)
  /// 2. Geometry-type default via [FriendExpressionConfig.forGeometry]
  FriendExpressionConfig? get expression {
    if (expressionName != null) {
      final registered = ExpressionRegistry.get(expressionName!);
      if (registered != null) return registered;
    }
    return FriendExpressionConfig.forGeometry(geometryType);
  }

  Friend copyWith({
    String? id,
    String? name,
    GeometryPrefabs? geometryType,
    FriendStats? stats,
    Color? color,
    String? expressionName,
    bool clearExpressionName = false,
  }) {
    return Friend(
      id: id ?? this.id,
      name: name ?? this.name,
      geometryType: geometryType ?? this.geometryType,
      stats: stats ?? this.stats,
      color: color ?? this.color,
      expressionName: clearExpressionName
          ? null
          : (expressionName ?? this.expressionName),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Friend &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          geometryType == other.geometryType &&
          stats == other.stats &&
          color == other.color &&
          expressionName == other.expressionName;

  @override
  int get hashCode =>
      id.hashCode ^
      name.hashCode ^
      geometryType.hashCode ^
      stats.hashCode ^
      color.hashCode ^
      expressionName.hashCode;

  @override
  String toString() =>
      'Friend(id: $id, name: $name, geometryType: $geometryType, '
      'stats: $stats, expressionName: $expressionName)';
}

/// Abstract provider for managing friends
abstract class FriendProvider extends ChangeNotifier {
  List<Friend> get friends;

  Friend? getFriendById(String id) {
    try {
      return friends.firstWhere((friend) => friend.id == id);
    } catch (_) {
      return null;
    }
  }
}

/// Mock implementation of FriendProvider with default friends
class MockFriendProvider extends FriendProvider {
  MockFriendProvider() : _friends = _createDefaultFriends();

  List<Friend> _friends;

  @override
  List<Friend> get friends => List.unmodifiable(_friends);

  void addFriend(Friend friend) {
    _friends = [..._friends, friend];
    notifyListeners();
  }

  void removeFriend(String id) {
    _friends = _friends.where((friend) => friend.id != id).toList();
    notifyListeners();
  }

  void updateFriend(Friend friend) {
    final index = _friends.indexWhere((f) => f.id == friend.id);
    if (index != -1) {
      _friends = List.from(_friends)..[index] = friend;
      notifyListeners();
    }
  }

  static List<Friend> _createDefaultFriends() {
    return [
      Friend(
        id: 'a7f3e8d2-4b6c-4a9f-8e2d-5c1b3a7f9e4d',
        name: 'Frogman',
        geometryType: GeometryPrefabs.frog,
        stats: const FriendStats(tileSpeed: 10.0),
        color: Colors.lightBlueAccent,
      ),
      Friend(
        id: 'b2c9f5e1-7a3d-4f8b-9c6e-1d4a8b2f7e3c',
        name: 'Cubeboy',
        geometryType: GeometryPrefabs.cube,
        stats: const FriendStats(tileSpeed: 10.0),
        color: Colors.lightGreenAccent,
      ),
      Friend(
        id: 'c3d0a6f2-8b4e-5g9c-0d7f-2e5b9c3a8f1d',
        name: 'Conico',
        geometryType: GeometryPrefabs.cone,
        stats: const FriendStats(tileSpeed: 10.0),
        color: Colors.amberAccent,
      ),
    ];
  }

  /// Generate a new random GUID for creating friends
  static String generateGuid() {
    final random = math.Random();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return _formatGuidBytes(bytes);
  }

  static String _formatGuidBytes(List<int> bytes) {
    String twoHex(int value) => value.toRadixString(16).padLeft(2, '0');
    final sections = <List<int>>[
      bytes.sublist(0, 4),
      bytes.sublist(4, 6),
      bytes.sublist(6, 8),
      bytes.sublist(8, 10),
      bytes.sublist(10, 16),
    ];
    final buffer = StringBuffer();
    for (var i = 0; i < sections.length; i++) {
      if (i > 0) buffer.write('-');
      for (final byte in sections[i]) {
        buffer.write(twoHex(byte));
      }
    }
    return buffer.toString();
  }
}
