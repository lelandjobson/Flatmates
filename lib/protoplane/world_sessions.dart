import 'materials.dart';
import 'controller.dart';
import 'storage.dart';

/// Independent saves and live controllers retain each world's session history.
class WorldSessions {
  WorldSessions({ProtoplaneStorage Function(WorldPreset)? storageFactory})
    : _storageFactory =
          storageFactory ??
          ((preset) => ProtoplaneStorage(fileName: preset.fileName));
  final ProtoplaneStorage Function(WorldPreset) _storageFactory;
  final _controllers = <WorldPreset, ProtoplaneController>{};
  final _stores = <WorldPreset, ProtoplaneStorage>{};
  final _loaded = <WorldPreset>{};
  ProtoplaneController controller(WorldPreset preset) => _controllers
      .putIfAbsent(preset, () => ProtoplaneController(preset: preset));
  ProtoplaneStorage storage(WorldPreset preset) =>
      _stores.putIfAbsent(preset, () => _storageFactory(preset));
  Future<void> load(WorldPreset preset, {bool reload = false}) async {
    if (!reload && _loaded.contains(preset)) return;
    final json = await storage(preset).load((json) {
      final validator = ProtoplaneController(preset: preset);
      try {
        validator.load(json);
        if (validator.preset != preset) {
          throw const FormatException('World preset does not match save file');
        }
      } finally {
        validator.dispose();
      }
    });
    if (json != null) controller(preset).load(json);
    _loaded.add(preset);
  }

  Future<ProtoplaneController> switchFrom(
    WorldPreset current,
    WorldPreset next,
  ) async {
    controller(current).cancelGesture();
    // A fresh explicit save retries failed queued writes and propagates failure.
    await storage(current).save(controller(current).toJson());
    await load(next);
    return controller(next);
  }

  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
  }
}
