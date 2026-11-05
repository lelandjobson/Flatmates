import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

typedef WorldValidator = void Function(Map<String, dynamic>);

/// Native application-local storage. Tests supply a temporary directory.
/// A failed load locks writes until an explicit successful reload; malformed
/// data is never replaced by a fresh empty world as a side effect of startup.
class ProtoplaneStorage {
  ProtoplaneStorage({
    Future<Directory> Function()? directory,
    this.fileName = 'world-paper.json',
  }) : _directory = directory ?? getApplicationSupportDirectory;
  final String fileName;
  final Future<Directory> Function() _directory;
  Future<void> _pending = Future.value();
  String? _lastValid;
  bool _writable = false;
  String? recoveryMessage;

  Future<File> _file() async {
    final dir = Directory('${(await _directory()).path}/protoplane_concept');
    await dir.create(recursive: true);
    return File('${dir.path}/$fileName');
  }

  Future<Map<String, dynamic>?> load(WorldValidator validate) async {
    _writable = false;
    recoveryMessage = null;
    final file = await _file();
    final backup = File('${file.path}.backup');
    if (!await file.exists() && !await backup.exists()) {
      _writable = true;
      return null;
    }
    Object? failure;
    for (final candidate in [file, backup]) {
      if (!await candidate.exists()) continue;
      try {
        final raw = await candidate.readAsString();
        final json = jsonDecode(raw) as Map<String, dynamic>;
        validate(json);
        _lastValid = raw;
        if (candidate.path != file.path) {
          if (await file.exists()) {
            await file.copy(
              '${file.path}.damaged-${DateTime.now().microsecondsSinceEpoch}',
            );
          }
          recoveryMessage = 'Recovered the previous save';
        }
        _writable = true;
        return json;
      } catch (e) {
        failure = e;
      }
    }
    throw FormatException(
      'Cannot load saved world; original files retained',
      failure,
    );
  }

  Future<void> save(Map<String, dynamic> json) {
    final raw = jsonEncode(json);
    final next = _pending.then((_) async {
      if (!_writable) throw StateError('Reload the saved world before saving');
      final file = await _file();
      if (_lastValid != null) {
        final tempBackup = File('${file.path}.backup.tmp');
        await tempBackup.writeAsString(_lastValid!, flush: true);
        await tempBackup.rename('${file.path}.backup');
      }
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(raw, flush: true);
      await temp.rename(file.path);
      _lastValid = raw;
    });
    // One failed write must not poison later explicit retries.
    _pending = next.catchError((Object _) {});
    return next;
  }

  Future<void> get flushed => _pending;
}
