import 'dart:convert';
import 'dart:io';

import 'blueprint.dart';

/// Reads and writes level JSON under [directory], defaulting to `levels/`.
class LevelStore {
  LevelStore({Directory? directory}) : directory = directory ?? Directory('levels');

  final Directory directory;

  Future<void> save(GridBlueprint blueprint) async {
    await directory.create(recursive: true);
    final name = _fileName(blueprint.id);
    final file = File('${directory.path}/$name.json');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(blueprint.toJson()),
    );
  }

  Future<List<GridBlueprint>> loadAll() async {
    if (!await directory.exists()) return const [];
    final levels = <GridBlueprint>[];
    await for (final entity in directory.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final json = jsonDecode(await entity.readAsString());
        if (json is Map<String, dynamic>) {
          levels.add(GridBlueprint.fromJson(json));
        }
      } catch (_) {
        continue;
      }
    }
    levels.sort((a, b) => a.name.compareTo(b.name));
    return levels;
  }
}

String _fileName(String id) {
  final cleaned = id
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return cleaned.isEmpty ? 'level' : cleaned;
}
