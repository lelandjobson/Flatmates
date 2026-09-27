import 'dart:convert';
import 'dart:io';

import 'tool_animation.dart';

/// Reads and writes tool glyphs under [directory], defaulting to
/// `tool_animations/tools.json`.
class ToolAnimationStore {
  ToolAnimationStore({Directory? directory})
    : directory = directory ?? Directory('tool_animations');

  final Directory directory;

  File get _file => File('${directory.path}/tools.json');

  Future<List<ToolAnimation>> load() async {
    final defaults = defaultToolAnimations();
    if (!await _file.exists()) return defaults;
    try {
      final json = jsonDecode(await _file.readAsString());
      if (json is! Map) return defaults;
      final list = json['tools'];
      if (list is! List) return defaults;
      final byId = <String, Map<String, dynamic>>{};
      for (final item in list) {
        if (item is! Map) continue;
        final id = item['id'];
        if (id is! String) continue;
        byId[id] = Map<String, dynamic>.from(item);
      }
      return [
        for (final tool in defaults)
          byId[tool.id] == null ? tool : tool.applyJson(byId[tool.id]!),
      ];
    } catch (_) {
      return defaults;
    }
  }

  Future<void> save(List<ToolAnimation> tools) async {
    await directory.create(recursive: true);
    await _file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'tools': [for (final tool in tools) tool.toJson()],
      }),
    );
  }
}
