import 'package:vector_math/vector_math_64.dart';

import '../tools/tool_3d.dart';
import 'volume_store.dart';

/// [Tool3d] adapter: the draft cell's box is the volume tool's work area.
class VolumeTool3d implements Tool3d {
  const VolumeTool3d(this.store);

  final VolumeStore store;

  @override
  Iterable<Vector3> get workAreaPoints {
    final cell = store.draftCell;
    if (cell == null) return const Iterable<Vector3>.empty();
    return cell.box.worldCorners(store.grid, cell.tx, cell.ty);
  }
}
