import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'iso_camera.dart';

/// Composites static structure draws into a single rasterized [ui.Image] when
/// the camera is stable, avoiding N individual [Canvas.drawPicture] calls per
/// frame. Invalidates when camera moves, view rotates, assets change, or
/// friends occupy structure tiles.
class SceneRasterCache {
  SceneRasterCache({
    this.stabilityThresholdMs = 16,
  });

  final int stabilityThresholdMs;

  ui.Image? _cachedImage;
  Offset? _cachedOffset;

  // Cache validity keys
  Offset _lastCameraPosition = Offset.zero;
  double _lastCameraZoom = 0;
  int _lastViewIndex = -1;
  int _lastAssetVersion = -1;
  Set<String>? _lastFriendTileKeys;
  Size _lastViewportSize = Size.zero;

  // Stability tracking
  DateTime? _lastCameraChangeTime;
  bool _cameraStable = false;

  /// Whether the cache currently holds a valid composited image.
  bool get hasCache => _cachedImage != null;

  /// The cached composited image, or null if not available.
  ui.Image? get image => _cachedImage;

  /// The top-left offset of the cached image in canvas coordinates.
  Offset get offset => _cachedOffset ?? Offset.zero;

  /// Notify the cache that the camera has changed. Resets stability timer.
  void onCameraChanged() {
    _lastCameraChangeTime = DateTime.now();
    _cameraStable = false;
  }

  /// Check whether the cache is valid for the current paint state.
  /// Returns true if the cached image can be used, false if structures
  /// should be drawn individually (and optionally captured for caching).
  /// Monotonically increasing version — bump when structures change.
  int _assetVersion = 0;

  /// Call when structures are placed, removed, or the asset list changes.
  void incrementAssetVersion() {
    _assetVersion++;
  }

  bool isValid({
    required IsoCamera camera,
    required Set<String> friendTileKeys,
    required Size viewportSize,
  }) {
    // Check stability
    if (_lastCameraChangeTime != null) {
      final elapsed =
          DateTime.now().difference(_lastCameraChangeTime!).inMilliseconds;
      if (elapsed < stabilityThresholdMs) {
        _cameraStable = false;
        return false;
      }
    }
    _cameraStable = true;

    if (_cachedImage == null) return false;

    // Camera state changed
    if (camera.position != _lastCameraPosition ||
        camera.zoom != _lastCameraZoom ||
        camera.view.index != _lastViewIndex) {
      return false;
    }

    // Asset version changed (structures placed/removed)
    if (_assetVersion != _lastAssetVersion) {
      return false;
    }

    // Friends moved onto/off structure tiles
    if (_lastFriendTileKeys == null ||
        !_setsEqual(friendTileKeys, _lastFriendTileKeys!)) {
      return false;
    }

    // Viewport size changed
    if (viewportSize != _lastViewportSize) {
      return false;
    }

    return true;
  }

  /// Whether the camera has been stable long enough to attempt caching.
  bool get isCameraStable => _cameraStable;

  /// Store a freshly composited image for the given state.
  void store({
    required ui.Image image,
    required Offset imageOffset,
    required IsoCamera camera,
    required Set<String> friendTileKeys,
    required Size viewportSize,
  }) {
    _cachedImage?.dispose();
    _cachedImage = image;
    _cachedOffset = imageOffset;
    _lastCameraPosition = camera.position;
    _lastCameraZoom = camera.zoom;
    _lastViewIndex = camera.view.index;
    _lastAssetVersion = _assetVersion;
    _lastFriendTileKeys = Set.of(friendTileKeys);
    _lastViewportSize = viewportSize;
  }

  /// Invalidate and dispose the cached image.
  void invalidate() {
    _cachedImage?.dispose();
    _cachedImage = null;
    _cachedOffset = null;
    _lastFriendTileKeys = null;
  }

  /// Dispose all resources.
  void dispose() {
    invalidate();
  }

  static bool _setsEqual(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    for (final item in a) {
      if (!b.contains(item)) return false;
    }
    return true;
  }
}
