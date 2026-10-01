import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'piece_glow.dart';

/// Bundled glow settings. A save writes the same path in the repo so the
/// next launch picks up the file without a rebuild.
const kPieceGlowAssetPath = 'assets/gridcraft/piece_glow.json';

/// Reads and writes [PieceGlowSettings] for the puzzle dev panel.
class PieceGlowStore {
  PieceGlowStore({File? file}) : _override = file;

  final File? _override;

  static const _encoder = JsonEncoder.withIndent('  ');

  Future<PieceGlowSettings> load() async {
    final file = _override ?? _repoFile();
    if (file != null && file.existsSync()) return _read(file);
    if (_override != null) return PieceGlowSettings.standard;
    try {
      final raw = await rootBundle.loadString(kPieceGlowAssetPath);
      return PieceGlowSettings.fromJson(jsonDecode(raw));
    } catch (_) {
      return PieceGlowSettings.standard;
    }
  }

  Future<void> save(PieceGlowSettings settings) async {
    final file = _override ?? _repoFile();
    if (file == null) {
      throw StateError(
        'Could not find the Flatmates repo root (pubspec.yaml). '
        'Run from the project, or check macOS sandbox entitlements.',
      );
    }
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('${_encoder.convert(settings.toJson())}\n');
  }

  PieceGlowSettings _read(File file) {
    try {
      return PieceGlowSettings.fromJson(jsonDecode(file.readAsStringSync()));
    } catch (_) {
      return PieceGlowSettings.standard;
    }
  }

  File? _repoFile() {
    var dir = Directory.current;
    for (var i = 0; i < 10; i++) {
      final pubspec = File('${dir.path}${Platform.pathSeparator}pubspec.yaml');
      if (pubspec.existsSync()) {
        final text = pubspec.readAsStringSync();
        if (text.contains('name: flatmates')) {
          return File(
            '${dir.path}${Platform.pathSeparator}'
            '${kPieceGlowAssetPath.replaceAll('/', Platform.pathSeparator)}',
          );
        }
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return null;
  }
}
