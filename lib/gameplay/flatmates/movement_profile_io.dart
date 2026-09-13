import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../recording/game_recording_io.dart';
import 'movement_profile.dart';

/// Repo-relative folder for named movement profiles.
const kMovementProfilesAssetDir = 'assets/gameplay/movement_profiles';

/// Bundled default profile written by the movement lab.
const kDefaultMovementProfilePath =
    '$kMovementProfilesAssetDir/default.json';

/// Loads and writes [MovementProfile] JSON next to the recordings IO helper.
class MovementProfileIo {
  static const _encoder = JsonEncoder.withIndent('  ');

  /// Prefers the live repo file, then the bundled asset, then [MovementProfile.hop].
  static Future<MovementProfile> loadDefault() async {
    final fromId = await loadById('default');
    if (fromId != null) return fromId;
    final fromAsset = await loadFromAsset(kDefaultMovementProfilePath);
    if (fromAsset != null) return fromAsset;
    return MovementProfile.hop.copyWith(id: 'default', name: 'Default');
  }

  static Future<MovementProfile?> loadById(String id) async {
    final file = resolveFile('$id.json');
    if (file != null && file.existsSync()) {
      return MovementProfile.fromJson(
        jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
      );
    }
    return loadFromAsset('$kMovementProfilesAssetDir/$id.json');
  }

  static Future<MovementProfile?> loadFromAsset(String assetPath) async {
    try {
      final raw = await rootBundle.loadString(assetPath);
      return MovementProfile.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  /// Bundle first, then overlay any repo files so a just-written profile wins.
  static Future<List<MovementProfile>> list() async {
    final found = <String, MovementProfile>{};
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      for (final key in manifest.listAssets()) {
        if (!key.startsWith('$kMovementProfilesAssetDir/')) continue;
        if (!key.endsWith('.json')) continue;
        if (key.endsWith('assignments.json')) continue;
        final profile = await loadFromAsset(key);
        if (profile != null) found[profile.id] = profile;
      }
    } catch (_) {}

    final dir = resolveDir();
    if (dir != null && dir.existsSync()) {
      for (final entity in dir.listSync()) {
        if (entity is! File || !entity.path.endsWith('.json')) continue;
        if (entity.path.endsWith('assignments.json')) continue;
        try {
          final profile = MovementProfile.fromJson(
            jsonDecode(entity.readAsStringSync()) as Map<String, dynamic>,
          );
          found[profile.id] = profile;
        } catch (_) {}
      }
    }

    if (found.isEmpty) found[MovementProfile.hop.id] = MovementProfile.hop;
    final list = found.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  /// Writes [profile] to `assets/gameplay/movement_profiles/<id>.json`.
  static Future<String> save(MovementProfile profile) async {
    final file = resolveFile('${profile.id}.json');
    if (file == null) {
      throw StateError(
        'Could not find the Flatmates repo root (pubspec.yaml). '
        'Run from the project, or check macOS sandbox entitlements.',
      );
    }
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('${_encoder.convert(profile.toJson())}\n');
    return '$kMovementProfilesAssetDir/${profile.id}.json';
  }

  static Directory? resolveDir() {
    final root = GameRecordingIo.findRepoRoot();
    if (root == null) return null;
    return Directory(
      '${root.path}${Platform.pathSeparator}'
      '${kMovementProfilesAssetDir.replaceAll('/', Platform.pathSeparator)}',
    );
  }

  static File? resolveFile(String name) {
    final dir = resolveDir();
    if (dir == null) return null;
    return File('${dir.path}${Platform.pathSeparator}$name');
  }
}
