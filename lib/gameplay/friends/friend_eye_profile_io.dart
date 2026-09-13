import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../user/friend_provider.dart';
import '../recording/game_recording_io.dart';
import 'friend_eye_profile.dart';
import 'friend_instance.dart';
import 'friend_instance_store.dart';

const kEyeProfilesAssetDir = 'assets/gameplay/eye_profiles';
const kEyeAssignmentsPath = '$kEyeProfilesAssetDir/assignments.json';

/// Friend-template id → [FriendEyeProfile].
class FriendEyeProfiles {
  const FriendEyeProfiles([this.byFriendId = const {}]);

  static const empty = FriendEyeProfiles();

  final Map<String, FriendEyeProfile> byFriendId;

  FriendEyeProfile forKey(String friendId) =>
      byFriendId[friendId] ?? FriendEyeProfile.defaults;

  FriendEyeProfile forFriend(Friend friend) => forKey(eyeProfileKey(friend));

  FriendEyeProfiles withProfile(String friendId, FriendEyeProfile profile) {
    final next = Map<String, FriendEyeProfile>.from(byFriendId);
    next[friendId] = profile.clamped();
    return FriendEyeProfiles(next);
  }

  Map<String, dynamic> toJson() => {
        'friends': {
          for (final entry in byFriendId.entries) entry.key: entry.value.toJson(),
        },
      };

  factory FriendEyeProfiles.fromJson(Map<String, dynamic> json) {
    final raw = json['friends'];
    if (raw is! Map) return const FriendEyeProfiles();
    final mapped = <String, FriendEyeProfile>{};
    for (final entry in raw.entries) {
      final value = entry.value;
      if (value is! Map) continue;
      mapped['${entry.key}'] = FriendEyeProfile.fromJson(
        value.cast<String, dynamic>(),
      );
    }
    return FriendEyeProfiles(mapped);
  }
}

class FriendEyeProfileIo {
  static const _encoder = JsonEncoder.withIndent('  ');

  static Future<FriendEyeProfiles> load() async {
    final file = resolveFile();
    if (file != null && file.existsSync()) {
      try {
        return FriendEyeProfiles.fromJson(
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
        );
      } catch (_) {}
    }
    try {
      final raw = await rootBundle.loadString(kEyeAssignmentsPath);
      return FriendEyeProfiles.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return FriendEyeProfiles.empty;
    }
  }

  static Future<String> save(FriendEyeProfiles profiles) async {
    final file = resolveFile();
    if (file == null) {
      throw StateError(
        'Could not find the Flatmates repo root (pubspec.yaml). '
        'Run from the project, or check macOS sandbox entitlements.',
      );
    }
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('${_encoder.convert(profiles.toJson())}\n');
    return kEyeAssignmentsPath;
  }

  static File? resolveFile() {
    final root = GameRecordingIo.findRepoRoot();
    if (root == null) return null;
    return File(
      '${root.path}${Platform.pathSeparator}'
      '${kEyeAssignmentsPath.replaceAll('/', Platform.pathSeparator)}',
    );
  }
}

void applyEyeProfiles(FriendInstanceStore friends, FriendEyeProfiles profiles) {
  for (final instance in friends.instances) {
    instance.eyeProfile = profiles.forFriend(instance.friend);
  }
}
