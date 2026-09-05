import 'package:flutter/material.dart';

import '../../gameplay/outlines/outline_paint.dart';
import '../../gameplay/volumes/volume_program.dart';
import '../../gameplay/volumes/volume_program_clusters.dart';
import '../../gameplay/volumes/volume_store.dart';
import '../../gameplay/walls/wall_regions.dart';
import '../../gameplay/walls/wall_store.dart';
import '../../rendering/scene/camera.dart';

/// Colored floor / region outlines and camera-rest program icons.
class VolumeProgramOverlay extends StatelessWidget {
  const VolumeProgramOverlay({
    super.key,
    required this.programs,
    required this.volumes,
    required this.walls,
    required this.regions,
    required this.camera,
    required this.viewport,
    this.listenable,
    this.hideFloorAt,
    this.iconOpacity = 1,
    this.showIcons = true,
    this.showOutlines = true,
  });

  final VolumeProgramStore programs;
  final VolumeStore volumes;
  final WallStore walls;
  final List<WallRegion> regions;
  final Camera camera;
  final Size viewport;
  final Listenable? listenable;
  final bool Function(int tx, int ty)? hideFloorAt;
  final double iconOpacity;
  final bool showIcons;
  final bool showOutlines;

  @override
  Widget build(BuildContext context) {
    final listenable = this.listenable;
    if (listenable != null) {
      return ListenableBuilder(
        listenable: listenable,
        builder: (context, _) => _paint(),
      );
    }
    return _paint();
  }

  Widget _paint() {
    return IgnorePointer(
      child: CustomPaint(
        size: viewport,
        painter: _ProgramPainter(
          programs: programs,
          volumes: volumes,
          walls: walls,
          regions: regions,
          camera: camera,
          viewport: viewport,
          hideFloorAt: hideFloorAt,
          iconOpacity: iconOpacity,
          showIcons: showIcons,
          showOutlines: showOutlines,
        ),
      ),
    );
  }
}

class _ProgramPainter extends CustomPainter {
  _ProgramPainter({
    required this.programs,
    required this.volumes,
    required this.walls,
    required this.regions,
    required this.camera,
    required this.viewport,
    this.hideFloorAt,
    required this.iconOpacity,
    required this.showIcons,
    required this.showOutlines,
  });

  final VolumeProgramStore programs;
  final VolumeStore volumes;
  final WallStore walls;
  final List<WallRegion> regions;
  final Camera camera;
  final Size viewport;
  final bool Function(int tx, int ty)? hideFloorAt;
  final double iconOpacity;
  final bool showIcons;
  final bool showOutlines;

  @override
  void paint(Canvas canvas, Size size) {
    final indoor = indoorProgramClusters(
      volumes: volumes,
      programs: programs,
      walls: walls,
    );
    final outdoor = outdoorProgramClusters(
      regions: regions,
      programs: programs,
      grid: volumes.grid,
      walls: walls,
    );
    if (showOutlines) {
      for (final cluster in indoor) {
        if (_hidden(cluster)) continue;
        final spec = programById(cluster.programId);
        if (spec == null) continue;
        paintOutlineEdges(
          canvas: canvas,
          edges: cluster.edges,
          camera: camera,
          viewport: viewport,
          color: spec.color,
          strokeWidth: 2.2,
        );
      }
      for (final cluster in outdoor) {
        final spec = programById(cluster.programId);
        if (spec == null) continue;
        paintOutlineEdges(
          canvas: canvas,
          edges: cluster.edges,
          camera: camera,
          viewport: viewport,
          color: spec.color,
          strokeWidth: 1.8,
          dashLength: 9,
          dashGap: 5,
        );
      }
    }
    if (!showIcons || iconOpacity <= 0.02) return;
    for (final cluster in [...indoor, ...outdoor]) {
      if (!cluster.outdoor && _hidden(cluster)) continue;
      _paintIcon(canvas, cluster);
    }
  }

  bool _hidden(ProgramCluster cluster) {
    final hide = hideFloorAt;
    if (hide == null) return false;
    for (final (tx, ty) in cluster.tiles) {
      if (!hide(tx, ty)) return false;
    }
    return true;
  }

  void _paintIcon(Canvas canvas, ProgramCluster cluster) {
    final spec = programById(cluster.programId);
    if (spec == null) return;
    final screen = camera.projectToScreen(cluster.centroid, viewport);
    if (screen == null) return;
    final painter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(spec.icon.codePoint),
        style: TextStyle(
          fontSize: 22,
          fontFamily: spec.icon.fontFamily,
          package: spec.icon.fontPackage,
          color: spec.color.withValues(alpha: iconOpacity),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(screen.dx - painter.width * 0.5, screen.dy - painter.height * 0.5),
    );
  }

  @override
  bool shouldRepaint(covariant _ProgramPainter oldDelegate) => true;
}
