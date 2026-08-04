import 'dart:ui' show lerpDouble;

/// The three zoom level domains, ordered from furthest out to closest in.
enum ZoomDomain { far, medium, close }

/// Immutable configuration that divides the camera zoom range into three
/// equal domains separated by two threshold values.
class ZoomDomainConfig {
  const ZoomDomainConfig({
    required this.minZoom,
    required this.maxZoom,
  });

  final double minZoom;
  final double maxZoom;

  double get _range => maxZoom - minZoom;

  /// Zoom value at the boundary between [ZoomDomain.far] and [ZoomDomain.medium].
  double get farMediumEdge => minZoom + _range / 3.0;

  /// Zoom value at the boundary between [ZoomDomain.medium] and [ZoomDomain.close].
  double get mediumCloseEdge => minZoom + 2.0 * _range / 3.0;

  ZoomDomain domainFor(double zoom) {
    if (zoom < farMediumEdge) return ZoomDomain.far;
    if (zoom < mediumCloseEdge) return ZoomDomain.medium;
    return ZoomDomain.close;
  }
}

/// Per-domain rendering rules that control opacity, visibility, and scale.
class ZoomRenderGuidelines {
  const ZoomRenderGuidelines({
    required this.structureOpacity,
    required this.ingredientDecorationOpacity,
    required this.foliageOpacity,
    required this.showFriendsInsideStructures,
    required this.friendInsideScale,
  });

  final double structureOpacity;
  final double ingredientDecorationOpacity;
  final double foliageOpacity;
  final bool showFriendsInsideStructures;
  final double friendInsideScale;

  static const far = ZoomRenderGuidelines(
    structureOpacity: 1.0,
    ingredientDecorationOpacity: 0.7,
    foliageOpacity: 1.0,
    showFriendsInsideStructures: false,
    friendInsideScale: 0.75,
  );

  static const medium = ZoomRenderGuidelines(
    structureOpacity: 1.0,
    ingredientDecorationOpacity: 0.5,
    foliageOpacity: 1.0,
    showFriendsInsideStructures: false,
    friendInsideScale: 0.75,
  );

  static const close = ZoomRenderGuidelines(
    structureOpacity: 0.5,
    ingredientDecorationOpacity: 0.2,
    foliageOpacity: 1.0,
    showFriendsInsideStructures: false,
    friendInsideScale: 0.75,
  );

  static const Map<ZoomDomain, ZoomRenderGuidelines> defaults = {
    ZoomDomain.far: far,
    ZoomDomain.medium: medium,
    ZoomDomain.close: close,
  };

  static ZoomRenderGuidelines forDomain(ZoomDomain domain) =>
      defaults[domain]!;

  /// Hitbox inflation factor for a given zoom domain. Not interpolated -- snaps
  /// at domain boundaries so players get predictably larger tap targets when
  /// zoomed out.
  static double hitboxScaleForDomain(ZoomDomain domain) {
    switch (domain) {
      case ZoomDomain.far:
        return 1.5;
      case ZoomDomain.medium:
        return 1.25;
      case ZoomDomain.close:
        return 1.0;
    }
  }

  /// Linearly interpolate between two guideline sets. [t] ranges from 0.0
  /// (fully [a]) to 1.0 (fully [b]).
  static ZoomRenderGuidelines lerp(
    ZoomRenderGuidelines a,
    ZoomRenderGuidelines b,
    double t,
  ) {
    return ZoomRenderGuidelines(
      structureOpacity: lerpDouble(
        a.structureOpacity,
        b.structureOpacity,
        t,
      )!,
      ingredientDecorationOpacity: lerpDouble(
        a.ingredientDecorationOpacity,
        b.ingredientDecorationOpacity,
        t,
      )!,
      foliageOpacity: lerpDouble(
        a.foliageOpacity,
        b.foliageOpacity,
        t,
      )!,
      showFriendsInsideStructures:
          t < 0.5 ? a.showFriendsInsideStructures : b.showFriendsInsideStructures,
      friendInsideScale: lerpDouble(
        a.friendInsideScale,
        b.friendInsideScale,
        t,
      )!,
    );
  }
}
