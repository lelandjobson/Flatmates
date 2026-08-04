import 'dart:math' as math;

import '../geometry/geometry.dart';
import '../geometry/tessellation.dart';
import 'mesh.dart';

/// A collection of meshes that are rendered together with adaptive tessellation
/// to ensure correct depth-sorted rendering of overlapping geometry.
///
/// The tessellation subdivides large faces of larger meshes to match the
/// granularity of the smallest mesh in the group, making the Painter's
/// Algorithm depth sort accurate for all face combinations.
///
/// Usage:
/// ```dart
/// final group = RenderGroup(id: 'body-and-eyes');
/// group.meshIds.addAll(['body', 'eye-left', 'eye-right']);
/// // Later, in the renderer:
/// final tessGeo = group.getTessellatedGeometry(mesh, allMeshes);
/// ```
class RenderGroup {
  RenderGroup({required this.id});

  final String id;

  /// Global scale factor applied to the tessellation target edge.
  ///
  /// Values > 1 produce larger (coarser) tessellated faces; values < 1 produce
  /// finer subdivision. The default is 1.0 (no scaling).
  static double tessellationScale = 1.0;

  /// IDs of meshes belonging to this group.
  final List<String> meshIds = [];

  /// Cached tessellated geometries keyed by mesh ID.
  final Map<String, _CacheEntry> _cache = {};

  /// Invalidate the tessellation cache for all meshes in this group.
  void invalidateCache() => _cache.clear();

  /// Invalidate the cache for a single mesh.
  void invalidateMesh(String meshId) => _cache.remove(meshId);

  /// Compute the target edge length for this group based on the smallest
  /// mesh's smallest AABB dimension.
  ///
  /// Returns `double.infinity` if no valid bounds can be computed (meaning
  /// no tessellation is needed).
  double computeTargetEdge(List<Mesh> meshes) {
    var smallest = double.infinity;

    for (final mesh in meshes) {
      if (!meshIds.contains(mesh.id)) continue;
      final bounds = worldSpaceBounds(mesh.geometry, mesh.scale);
      final dim = smallestDimension(bounds);
      if (dim > 0) {
        smallest = math.min(smallest, dim);
      }
    }

    return smallest;
  }

  /// Get the tessellated geometry for [mesh], using the cache if valid.
  ///
  /// The [allMeshes] list is used to compute the target edge length across
  /// all meshes in the group.
  ///
  /// If [mesh] doesn't need tessellation (all edges already small enough),
  /// the original geometry is returned as-is (no allocation).
  Geometry getTessellatedGeometry(Mesh mesh, List<Mesh> allMeshes) {
    final targetEdge = computeTargetEdge(allMeshes);
    if (!targetEdge.isFinite || targetEdge <= 0) {
      return mesh.geometry;
    }

    // Apply the global tessellation scale factor.
    final scaledTarget = targetEdge * tessellationScale;

    // Compute the floor cap: 1/100th of this mesh's own smallest dimension.
    final ownBounds = worldSpaceBounds(mesh.geometry, mesh.scale);
    final ownSmallest = smallestDimension(ownBounds);
    final floorEdge = ownSmallest / 100.0;
    final maxEdge = math.max(scaledTarget, floorEdge);

    // Check cache validity.
    final cached = _cache[mesh.id];
    if (cached != null &&
        cached.geometryId == mesh.geometry.id &&
        cached.maxEdge == maxEdge) {
      return cached.tessellated;
    }

    // Account for mesh scale when tessellating in local space.
    // Use the max scale component as a conservative estimate.
    final maxScale = math.max(
      mesh.scale.x.abs(),
      math.max(mesh.scale.y.abs(), mesh.scale.z.abs()),
    );
    final localMaxEdge = maxScale > 1e-6 ? maxEdge / maxScale : maxEdge;

    final tessellated = tessellateGeometry(mesh.geometry, localMaxEdge);

    _cache[mesh.id] = _CacheEntry(
      geometryId: mesh.geometry.id,
      maxEdge: maxEdge,
      tessellated: tessellated,
    );

    return tessellated;
  }
}

class _CacheEntry {
  const _CacheEntry({
    required this.geometryId,
    required this.maxEdge,
    required this.tessellated,
  });

  final String geometryId;
  final double maxEdge;
  final Geometry tessellated;
}
