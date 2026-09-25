import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../geometry/geometry.dart';
import '../geometry/obj_parser.dart';
import '../papercut/camera.dart';
import '../papercut/craft_v1.dart';
import '../papercut/fold_pose.dart';
import '../ui/fm_dev_back_button.dart';
import '../ui/fm_screen.dart';

/// Step-through viewer for version-1 crafts: blueprint, fold animation, wireframe.
class CraftEditorView extends StatefulWidget {
  const CraftEditorView({super.key, this.crafts});

  /// When set, these crafts are listed and assets are not loaded.
  final List<CraftV1>? crafts;

  @override
  State<CraftEditorView> createState() => _CraftEditorViewState();
}

class _CraftEditorViewState extends State<CraftEditorView>
    with SingleTickerProviderStateMixin {
  List<CraftV1> _crafts = const [];
  int _craftIndex = 0;
  int _stepIndex = 0;
  bool _folding = false;
  Geometry? _folded;
  double _yaw = 0.6;
  double _pitch = 0.45;
  late final PapercutCamera _blueprintCamera;
  late final AnimationController _fold;

  CraftV1? get _craft =>
      _crafts.isEmpty ? null : _crafts[_craftIndex.clamp(0, _crafts.length - 1)];

  List<int> get _steps => _craft?.craftingSteps ?? const [];

  int? get _step => _steps.isEmpty ? null : _steps[_stepIndex.clamp(0, _steps.length - 1)];

  @override
  void initState() {
    super.initState();
    _blueprintCamera = PapercutCamera();
    _fold = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..addListener(() {
      if (mounted) setState(() {});
    });
    _loadCrafts();
  }

  @override
  void dispose() {
    _fold.dispose();
    _blueprintCamera.dispose();
    super.dispose();
  }

  Future<void> _loadCrafts() async {
    final crafts = widget.crafts ?? await CraftV1.loadAll();
    if (!mounted) return;
    setState(() {
      _crafts = crafts;
      _craftIndex = 0;
      _stepIndex = 0;
    });
    await _loadFolded();
  }

  Future<void> _loadFolded() async {
    final craft = _craft;
    if (craft == null || craft.assetDirectory.isEmpty) {
      if (mounted) setState(() => _folded = null);
      return;
    }
    try {
      final source = await rootBundle.loadString(craft.foldedAsset);
      final geometry = ObjParser.parse(
        id: craft.craft,
        name: craft.craft,
        source: source,
        center: false,
      );
      if (!mounted) return;
      setState(() => _folded = geometry);
    } catch (error) {
      debugPrint('[craft-editor] folded model: $error');
      if (mounted) setState(() => _folded = null);
    }
  }

  void _selectCraft(int index) {
    setState(() {
      _craftIndex = index;
      _stepIndex = 0;
      _folding = false;
      _folded = null;
    });
    _fold.stop();
    _fold.value = 0;
    _loadFolded();
  }

  void _stepDelta(int dir) {
    final next = _stepIndex + dir;
    if (next < 0 || next >= _steps.length) return;
    setState(() => _stepIndex = next);
    if (_folding) {
      _fold.forward(from: 0);
    }
  }

  void _toggleFold() {
    setState(() => _folding = !_folding);
    if (_folding) {
      _fold.forward(from: 0);
    } else {
      _fold.stop();
    }
  }

  double get _foldT {
    final u = _fold.value.clamp(0.0, 1.0);
    return u * u * (3 - 2 * u);
  }

  @override
  Widget build(BuildContext context) {
    final craft = _craft;
    final step = _step;
    return FmScreen(
      backgroundColor: const Color(0xFF12141A),
      overlays: const [FmDevBackButton()],
      background: Column(
        children: [
          _buildBar(craft),
          Expanded(
            child: GestureDetector(
              onPanUpdate: (details) {
                setState(() {
                  _yaw += details.delta.dx * 0.01;
                  _pitch = (_pitch + details.delta.dy * 0.01).clamp(-1.2, 1.2);
                });
              },
              child: CustomPaint(
                painter: _FoldPainter(
                  craft: craft,
                  folded: _folded,
                  step: step,
                  folding: _folding,
                  t: _folding ? _foldT : 0,
                  yaw: _yaw,
                  pitch: _pitch,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          const Divider(height: 1, color: Colors.white24),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, constraints.maxHeight);
                _frameBlueprint(craft, step, size);
                return CustomPaint(
                  painter: _BlueprintPainter(
                    craft: craft,
                    step: step,
                    camera: _blueprintCamera,
                  ),
                  child: const SizedBox.expand(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _frameBlueprint(CraftV1? craft, int? step, Size viewport) {
    if (craft == null || step == null) return;
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;
    for (final face in craft.faces) {
      if (face.craftingStep != step || face.flatLoops.isEmpty) continue;
      for (final point in face.flatLoops.first) {
        minX = math.min(minX, point.x);
        minY = math.min(minY, point.y);
        maxX = math.max(maxX, point.x);
        maxY = math.max(maxY, point.y);
      }
    }
    if (minX == double.infinity) return;
    final span = math.max(maxX - minX, maxY - minY);
    _blueprintCamera.frameSheet(
      viewport,
      sheetMm: span <= 0 ? 10 : span,
      center: Offset((minX + maxX) / 2, (minY + maxY) / 2),
    );
  }

  Widget _buildBar(CraftV1? craft) {
    final step = _step;
    final total = _steps.length;
    return Material(
      color: const Color(0xFF1A1A1A),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(72, 8, 12, 8),
        child: Row(
          children: [
            Expanded(child: _craftDropdown()),
            IconButton(
              key: const Key('craft-editor-prev'),
              onPressed: _stepIndex <= 0 ? null : () => _stepDelta(-1),
              icon: const Icon(Icons.chevron_left, color: Colors.white70),
            ),
            Text(
              step == null ? 'No steps' : 'Step $step (${_stepIndex + 1}/$total)',
              style: const TextStyle(color: Colors.white70),
            ),
            IconButton(
              key: const Key('craft-editor-next'),
              onPressed: _stepIndex >= total - 1 ? null : () => _stepDelta(1),
              icon: const Icon(Icons.chevron_right, color: Colors.white70),
            ),
            TextButton(
              key: const Key('craft-editor-fold'),
              onPressed: craft == null ? null : _toggleFold,
              child: Text(_folding ? 'Solid model' : 'Fold steps'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _craftDropdown() {
    if (_crafts.isEmpty) {
      return const Text('No crafts', style: TextStyle(color: Colors.white70));
    }
    return DropdownButtonHideUnderline(
      child: DropdownButton<int>(
        key: const Key('craft-editor-dropdown'),
        isExpanded: true,
        isDense: true,
        dropdownColor: const Color(0xFF1A1A1A),
        value: _craftIndex,
        items: [
          for (var i = 0; i < _crafts.length; i++)
            DropdownMenuItem(
              value: i,
              child: Text(
                _crafts[i].craft,
                style: const TextStyle(color: Colors.white70),
              ),
            ),
        ],
        onChanged: (index) {
          if (index == null) return;
          _selectCraft(index);
        },
      ),
    );
  }
}

class _FoldPainter extends CustomPainter {
  _FoldPainter({
    required this.craft,
    required this.folded,
    required this.step,
    required this.folding,
    required this.t,
    required this.yaw,
    required this.pitch,
  });

  final CraftV1? craft;
  final Geometry? folded;
  final int? step;
  final bool folding;
  final double t;
  final double yaw;
  final double pitch;

  @override
  void paint(Canvas canvas, Size size) {
    final points = <Vector3>[];
    if (folded != null) points.addAll(folded!.vertices);
    if (points.isEmpty && craft != null) {
      for (final face in craft!.faces) {
        for (final loop in face.flatLoops) {
          points.addAll(loop.map(rhinoToEngine));
        }
      }
    }
    if (points.isEmpty) return;
    final bounds = _bounds(points);
    final center = bounds.center;
    final radius = math.max(bounds.radius, 1.0);

    if (folded != null) {
      final paint = Paint()
        ..color = folding ? const Color(0x599BB0C8) : const Color(0xFF8EAECE)
        ..style = folding ? PaintingStyle.stroke : PaintingStyle.fill
        ..strokeWidth = 1.2;
      for (final face in folded!.faces) {
        final ring = <Offset>[];
        for (final index in face) {
          if (index < 0 || index >= folded!.vertices.length) continue;
          final screen = _project(folded!.vertices[index], size, center, radius);
          if (screen == null) continue;
          ring.add(screen);
        }
        if (ring.length < 2) continue;
        final path = Path()..addPolygon(ring, true);
        canvas.drawPath(path, paint);
      }
    }

    if (!folding || craft == null || step == null) return;
    final posed = applyFoldPose(craft!, step!, t);
    for (final face in craft!.faces) {
      final matrix = posed[face.id];
      if (matrix == null || face.flatLoops.isEmpty) continue;
      final path = Path()..fillType = PathFillType.evenOdd;
      for (final loop in face.flatLoops) {
        final ring = <Offset>[];
        for (final point in loop) {
          final engine = rhinoToEngine(matrix.transformed3(point));
          final screen = _project(engine, size, center, radius);
          if (screen == null) continue;
          ring.add(screen);
        }
        if (ring.length < 3) continue;
        path.addPolygon(ring, true);
      }
      canvas.drawPath(
        path,
        Paint()..color = _layerColor(face.layer).withValues(alpha: 0.9),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FoldPainter old) => true;

  Offset? _project(Vector3 point, Size size, Vector3 center, double radius) {
    final rel = point - center;
    final cy = math.cos(yaw);
    final sy = math.sin(yaw);
    final x1 = rel.x * cy - rel.z * sy;
    final z1 = rel.x * sy + rel.z * cy;
    final cx = math.cos(pitch);
    final sx = math.sin(pitch);
    final y2 = rel.y * cx - z1 * sx;
    final z2 = rel.y * sx + z1 * cx;
    final depth = z2 + radius * 3;
    if (depth < 1) return null;
    final scale = size.shortestSide * 0.38 / radius;
    return Offset(
      size.width / 2 + x1 * scale * (radius * 2.2) / depth,
      size.height / 2 - y2 * scale * (radius * 2.2) / depth,
    );
  }
}

class _BlueprintPainter extends CustomPainter {
  _BlueprintPainter({
    required this.craft,
    required this.step,
    required this.camera,
  });

  final CraftV1? craft;
  final int? step;
  final PapercutCamera camera;

  @override
  void paint(Canvas canvas, Size size) {
    if (craft == null || step == null) return;
    for (final face in craft!.faces) {
      if (face.craftingStep != step || face.flatLoops.isEmpty) continue;
      final path = Path()..fillType = PathFillType.evenOdd;
      for (final loop in face.flatLoops) {
        final ring = _project(loop, size);
        if (ring == null || ring.length < 3) continue;
        path.addPolygon(ring, true);
      }
      canvas.drawPath(
        path,
        Paint()..color = _layerColor(face.layer).withValues(alpha: 0.65),
      );
      final outline = _project(face.flatLoops.first, size);
      if (outline != null && outline.length >= 2) {
        canvas.drawPath(
          Path()..addPolygon(outline, true),
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
      }
    }
    for (final edge in craft!.edges) {
      if (edge.craftingStep != step) continue;
      if (!edge.isFold && !edge.isCut) continue;
      final ring = _project(edge.curve, size);
      if (ring == null || ring.length < 2) continue;
      canvas.drawPoints(
        PointMode.polygon,
        ring,
        Paint()
          ..color = edge.isFold ? const Color(0xFFFF4444) : const Color(0xFF4488FF)
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
    }
  }

  List<Offset>? _project(List<Vector3> points, Size size) {
    final ring = <Offset>[];
    for (final point in points) {
      final screen = camera.camera.projectToScreen(
        Vector3(point.x, point.y, 0),
        size,
      );
      if (screen == null) return null;
      ring.add(screen);
    }
    return ring;
  }

  @override
  bool shouldRepaint(covariant _BlueprintPainter old) => true;
}

Color _layerColor(String layer) {
  final name = layer.split('::').last;
  var hash = 0;
  for (final code in name.codeUnits) {
    hash = (hash * 33 + code) & 0xFFFFFF;
  }
  final hue = (hash % 360).toDouble();
  return HSLColor.fromAHSL(1, hue, 0.45, 0.62).toColor();
}

class _Bounds {
  _Bounds(this.center, this.radius);

  final Vector3 center;
  final double radius;
}

_Bounds _bounds(List<Vector3> points) {
  var minX = double.infinity;
  var minY = double.infinity;
  var minZ = double.infinity;
  var maxX = -double.infinity;
  var maxY = -double.infinity;
  var maxZ = -double.infinity;
  for (final point in points) {
    minX = math.min(minX, point.x);
    minY = math.min(minY, point.y);
    minZ = math.min(minZ, point.z);
    maxX = math.max(maxX, point.x);
    maxY = math.max(maxY, point.y);
    maxZ = math.max(maxZ, point.z);
  }
  final center = Vector3(
    (minX + maxX) / 2,
    (minY + maxY) / 2,
    (minZ + maxZ) / 2,
  );
  var radius = 1.0;
  for (final point in points) {
    radius = math.max(radius, (point - center).length);
  }
  return _Bounds(center, radius);
}
