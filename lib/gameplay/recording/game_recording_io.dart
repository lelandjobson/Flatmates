import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'game_recording.dart';

/// Loads and writes [GameRecording] JSON at [kDefaultGameRecordingPath].
class GameRecordingIo {
  static const _encoder = JsonEncoder.withIndent('  ');

  /// Prefers the live repo file so a just-written recording can be reloaded
  /// without rebuilding assets, then falls back to the bundled asset.
  static Future<GameRecording> loadDefault() async {
    final file = resolveDefaultFile();
    if (file != null && file.existsSync()) {
      return GameRecording.fromJson(
        jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
      );
    }
    final raw = await rootBundle.loadString(kDefaultGameRecordingPath);
    return GameRecording.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
  }

  /// Writes [recording] to the repo-relative default path.
  static Future<String> saveDefault(GameRecording recording) async {
    final file = resolveDefaultFile();
    if (file == null) {
      throw StateError(
        'Could not find the Flatmates repo root (pubspec.yaml). '
        'Run from the project, or check macOS sandbox entitlements.',
      );
    }
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('${_encoder.convert(recording.toJson())}\n');
    return kDefaultGameRecordingPath;
  }

  /// Walks up from [Directory.current] looking for this repo's pubspec.
  static File? resolveDefaultFile() {
    final root = findRepoRoot();
    if (root == null) return null;
    return File(
      '${root.path}${Platform.pathSeparator}'
      '${kDefaultGameRecordingPath.replaceAll('/', Platform.pathSeparator)}',
    );
  }

  static Directory? findRepoRoot() {
    var dir = Directory.current;
    for (var i = 0; i < 10; i++) {
      final pubspec = File(
        '${dir.path}${Platform.pathSeparator}pubspec.yaml',
      );
      if (pubspec.existsSync()) {
        final text = pubspec.readAsStringSync();
        if (text.contains('name: flatmates')) return dir;
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return null;
  }
}
