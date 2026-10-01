import 'dart:convert';
import 'dart:io';

import 'blueprint.dart';

/// Folder id for loose blueprint files that sit directly under the store
/// directory. They load as one collection named [kLooseCollectionName] and
/// stay there until that collection is saved.
const String kLooseCollectionId = '~loose';

/// Display name for [kLooseCollectionId].
const String kLooseCollectionName = 'Puzzles';

const String _manifestName = 'collection.json';

/// A puzzle collection: a folder of blueprint files. The editor calls each
/// file a puzzle. [id] is the folder slug, except for [kLooseCollectionId].
class PuzzleCollection {
  const PuzzleCollection({
    required this.id,
    required this.name,
    required this.puzzles,
  });

  final String id;
  final String name;
  final List<GridBlueprint> puzzles;

  bool get loose => id == kLooseCollectionId;
}

enum LevelSaveFailure { blankName, collectionTaken, puzzleTaken }

class LevelSaveException implements Exception {
  LevelSaveException(this.failure);

  final LevelSaveFailure failure;

  @override
  String toString() => 'LevelSaveException($failure)';
}

/// Reads and writes blueprint files under [directory], defaulting to `levels/`.
///
/// The puzzle editor stores each blueprint in a puzzle-collection folder.
/// [save] overwrites the file a blueprint was loaded from, which is how play
/// saves without renaming.
///
/// Disk work is synchronous so a save finishes before the future completes.
class LevelStore {
  LevelStore({Directory? directory})
    : directory = directory ?? Directory('levels');

  final Directory directory;

  final Map<String, String> _pathById = {};

  /// Overwrites the file this blueprint was loaded from. A blueprint that has
  /// not been loaded is written as a loose file named from its id.
  Future<void> save(GridBlueprint blueprint) async {
    directory.createSync(recursive: true);
    final known = _pathById[blueprint.id];
    final file = known != null
        ? File(known)
        : File('${directory.path}/${_fileName(blueprint.id)}.json');
    _writeBlueprint(file, blueprint);
  }

  Future<List<GridBlueprint>> loadAll() async {
    final collections = await loadCollections();
    final levels = [
      for (final collection in collections) ...collection.puzzles,
    ];
    levels.sort((a, b) => a.name.compareTo(b.name));
    return levels;
  }

  Future<List<PuzzleCollection>> loadCollections() async {
    _pathById.clear();
    if (!directory.existsSync()) return const [];
    final collections = <PuzzleCollection>[];
    final loose = <GridBlueprint>[];
    for (final entity in directory.listSync(followLinks: false)) {
      if (entity is Directory) {
        final collection = _readFolder(entity);
        if (collection != null) collections.add(collection);
      } else if (entity is File && _isPuzzleFile(entity.path)) {
        final puzzle = _readBlueprint(entity);
        if (puzzle == null) continue;
        _pathById[puzzle.id] = entity.absolute.path;
        loose.add(puzzle);
      }
    }
    if (loose.isNotEmpty) {
      loose.sort(_comparePuzzles);
      collections.add(
        PuzzleCollection(
          id: kLooseCollectionId,
          name: kLooseCollectionName,
          puzzles: loose,
        ),
      );
    }
    collections.sort((a, b) => a.name.compareTo(b.name));
    return collections;
  }

  /// Writes [puzzle] into the collection named [collectionName].
  ///
  /// [fromCollectionId] is the collection the puzzle already belongs to.
  /// Null means it has never been saved. When the collection slug changes,
  /// every puzzle in that collection moves, and the old folder or the loose
  /// files are deleted only after the new copies exist.
  ///
  /// The blueprint id stays put. The file name follows the puzzle name.
  Future<PuzzleCollection> savePuzzle({
    required String collectionName,
    required GridBlueprint puzzle,
    String? fromCollectionId,
  }) async {
    final collectionDisplay = collectionName.trim();
    final puzzleDisplay = puzzle.name.trim();
    if (collectionDisplay.isEmpty || puzzleDisplay.isEmpty) {
      throw LevelSaveException(LevelSaveFailure.blankName);
    }
    final named = puzzle.copyWith(name: puzzleDisplay);
    final collectionSlug = _fileName(collectionDisplay);
    final puzzleSlug = _fileName(puzzleDisplay);
    if (puzzleSlug == 'collection') {
      throw LevelSaveException(LevelSaveFailure.puzzleTaken);
    }

    final existing = await loadCollections();
    final slugOwner = existing
        .where((collection) => collection.id == collectionSlug)
        .firstOrNull;
    if (slugOwner != null && slugOwner.id != fromCollectionId) {
      throw LevelSaveException(LevelSaveFailure.collectionTaken);
    }
    final source = fromCollectionId == null
        ? null
        : existing
              .where((collection) => collection.id == fromCollectionId)
              .firstOrNull;
    final neighbors =
        source?.puzzles.where((item) => item.id != named.id) ?? const [];
    for (final other in neighbors) {
      final path = _pathById[other.id];
      final slug = path == null ? _fileName(other.name) : _fileSlug(path);
      if (slug == puzzleSlug) {
        throw LevelSaveException(LevelSaveFailure.puzzleTaken);
      }
    }

    final oldPaths = Map<String, String>.from(_pathById);
    final root = directory.absolute;
    final destDir = Directory('${root.path}/$collectionSlug');
    destDir.createSync(recursive: true);
    _writeManifest(destDir, collectionDisplay);

    if (source != null && source.id != collectionSlug) {
      for (final other in neighbors) {
        final path = oldPaths[other.id];
        if (path == null) continue;
        final dest = File('${destDir.path}/${_basename(path)}');
        dest.writeAsBytesSync(File(path).readAsBytesSync());
      }
    }

    final newPath = File('${destDir.path}/$puzzleSlug.json').absolute.path;
    _writeBlueprint(File(newPath), named);

    if (source != null && !source.loose && source.id != collectionSlug) {
      final oldDir = Directory('${root.path}/${source.id}');
      if (oldDir.absolute.parent.path == root.path && oldDir.existsSync()) {
        oldDir.deleteSync(recursive: true);
      }
    } else {
      final previous = oldPaths[named.id];
      if (previous != null && previous != newPath) _deleteFile(previous);
      if (source != null && source.loose) {
        for (final other in neighbors) {
          final path = oldPaths[other.id];
          if (path == null || _isInside(path, destDir.path)) continue;
          _deleteFile(path);
        }
      }
    }

    final stored = await loadCollections();
    return stored.firstWhere((collection) => collection.id == collectionSlug);
  }

  PuzzleCollection? _readFolder(Directory folder) {
    final manifest = File('${folder.path}/$_manifestName');
    if (!manifest.existsSync()) return null;
    final folderName = _basename(folder.path);
    final name = _readManifestName(manifest) ?? folderName;
    final puzzles = <GridBlueprint>[];
    for (final entity in folder.listSync(followLinks: false)) {
      if (entity is! File || !_isPuzzleFile(entity.path)) continue;
      final puzzle = _readBlueprint(entity);
      if (puzzle == null) continue;
      _pathById[puzzle.id] = entity.absolute.path;
      puzzles.add(puzzle);
    }
    puzzles.sort(_comparePuzzles);
    return PuzzleCollection(id: folderName, name: name, puzzles: puzzles);
  }

  void _writeManifest(Directory folder, String name) {
    File('${folder.path}/$_manifestName').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({'name': name}),
    );
  }

  String? _readManifestName(File file) {
    try {
      final json = jsonDecode(file.readAsStringSync());
      if (json is! Map) return null;
      final name = json['name'];
      if (name is! String || name.trim().isEmpty) return null;
      return name.trim();
    } catch (_) {
      return null;
    }
  }

  GridBlueprint? _readBlueprint(File file) {
    try {
      final json = jsonDecode(file.readAsStringSync());
      if (json is! Map) return null;
      return GridBlueprint.fromJson(Map<String, dynamic>.from(json));
    } catch (_) {
      return null;
    }
  }

  void _writeBlueprint(File file, GridBlueprint blueprint) {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(blueprint.toJson()),
    );
    _pathById[blueprint.id] = file.absolute.path;
  }

  void _deleteFile(String path) {
    final file = File(path);
    if (file.existsSync()) file.deleteSync();
  }
}

bool _isPuzzleFile(String path) {
  return path.endsWith('.json') && _basename(path) != _manifestName;
}

bool _isInside(String path, String dirPath) {
  final file = File(path).absolute.path;
  final dir = Directory(dirPath).absolute.path;
  return file == dir || file.startsWith('$dir${Platform.pathSeparator}');
}

String _basename(String path) => path.split(RegExp(r'[/\\]')).last;

String _fileSlug(String path) {
  final base = _basename(path);
  return base.endsWith('.json') ? base.substring(0, base.length - 5) : base;
}

int _comparePuzzles(GridBlueprint a, GridBlueprint b) {
  final byName = a.name.compareTo(b.name);
  if (byName != 0) return byName;
  return a.id.compareTo(b.id);
}

String _fileName(String id) {
  final cleaned = id
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return cleaned.isEmpty ? 'level' : cleaned;
}
