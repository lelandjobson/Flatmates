import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'asmr_net.dart';
import 'asmr_paper.dart';
import 'asmr_piece.dart';

/// `~/.flatmates/asmr_session.json`. Save writes the desk here so it can be
/// opened again, or inspected when a piece is not showing.
File asmrSessionFile() => File('${_home()}/.flatmates/asmr_session.json');

/// `~/.flatmates/asmr_split_session.json`, the split view's desk, kept apart
/// so it does not overwrite the other view's.
File asmrSplitSessionFile() =>
    File('${_home()}/.flatmates/asmr_split_session.json');

String _home() =>
    Platform.environment['HOME'] ??
    Platform.environment['USERPROFILE'] ??
    Directory.systemTemp.path;

/// One saved desk: the hologram, the paper, the camera, and the straight edge.
class AsmrSession {
  const AsmrSession({
    required this.picks,
    required this.pieces,
    required this.bindings,
    required this.deskOrigin,
    required this.deskScale,
    required this.in3d,
    required this.azimuth,
    required this.elevation,
    required this.roll,
    required this.lookAt,
    required this.lookAtZ,
    required this.halfHeight,
    required this.focal,
    this.straightEdgeOn = false,
    this.straightEdgeAnchor = Offset.zero,
    this.straightEdgeAngle = 0,
    this.groups = const {},
    this.pieceGroups = const [],
  });

  final List<HologramPick> picks;
  final List<AsmrPiece> pieces;

  /// Binding picks parallel to [pieces]. Empty when that piece is not bound.
  final List<List<HologramPick>> bindings;

  /// Each selection group's letter, 0 for A, to the picks it was made with.
  final Map<int, List<HologramPick>> groups;

  /// The group letter of each piece, parallel to [pieces]. Null for paper
  /// laid with no faces selected, and for every piece of a file saved before
  /// groups, whose groups are rebuilt from [bindings].
  final List<int?> pieceGroups;
  final Offset deskOrigin;
  final double deskScale;
  final bool in3d;
  final double azimuth;
  final double elevation;
  final double roll;
  final Offset lookAt;
  final double lookAtZ;
  final double halfHeight;
  final double focal;
  final bool straightEdgeOn;
  final Offset straightEdgeAnchor;
  final double straightEdgeAngle;

  Map<String, dynamic> toJson() => {
    'picks': [for (final pick in picks) _pickJson(pick)],
    'deskOrigin': _offsetJson(deskOrigin),
    'deskScale': deskScale,
    'in3d': in3d,
    'camera': {
      'azimuth': azimuth,
      'elevation': elevation,
      'roll': roll,
      'lookAt': _offsetJson(lookAt),
      'lookAtZ': lookAtZ,
      'halfHeight': halfHeight,
      'focal': focal,
    },
    'straightEdge': {
      'on': straightEdgeOn,
      'anchor': _offsetJson(straightEdgeAnchor),
      'angle': straightEdgeAngle,
    },
    'groups': [
      for (final entry in groups.entries)
        {
          'letter': entry.key,
          'picks': [for (final pick in entry.value) _pickJson(pick)],
        },
    ],
    'pieces': [
      for (var i = 0; i < pieces.length; i++)
        {
          ..._pieceJson(
            pieces[i],
            i < bindings.length ? bindings[i] : const [],
          ),
          if (i < pieceGroups.length && pieceGroups[i] != null)
            'group': pieceGroups[i],
        },
    ],
  };

  static AsmrSession? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final camera = raw['camera'];
    final edge = raw['straightEdge'];
    if (camera is! Map) return null;
    final groups = <int, List<HologramPick>>{};
    final storedGroups = raw['groups'];
    if (storedGroups is List) {
      for (final entry in storedGroups) {
        if (entry is! Map || entry['letter'] is! num) continue;
        final picks = _picks(entry['picks']);
        if (picks.isEmpty) continue;
        groups[(entry['letter'] as num).toInt()] = picks;
      }
    }
    final pieces = <AsmrPiece>[];
    final bindings = <List<HologramPick>>[];
    final pieceGroups = <int?>[];
    final stored = raw['pieces'];
    if (stored is List) {
      for (final entry in stored) {
        if (entry is! Map) continue;
        final piece = _piece(entry);
        if (piece == null) continue;
        pieces.add(piece);
        bindings.add(_picks(entry['binding']));
        final group = entry['group'];
        pieceGroups.add(
          group is num && groups.containsKey(group.toInt())
              ? group.toInt()
              : null,
        );
      }
    }
    return AsmrSession(
      picks: _picks(raw['picks']),
      pieces: pieces,
      bindings: bindings,
      groups: groups,
      pieceGroups: pieceGroups,
      deskOrigin: _offset(raw['deskOrigin']) ?? Offset.zero,
      deskScale: _num(raw['deskScale']) ?? 1,
      in3d: raw['in3d'] != false,
      azimuth: _num(camera['azimuth']) ?? 0,
      elevation: _num(camera['elevation']) ?? 0,
      roll: _num(camera['roll']) ?? 0,
      lookAt: _offset(camera['lookAt']) ?? Offset.zero,
      lookAtZ: _num(camera['lookAtZ']) ?? 0,
      halfHeight: _num(camera['halfHeight']) ?? 1,
      focal: _num(camera['focal']) ?? 50,
      straightEdgeOn: edge is Map && edge['on'] == true,
      straightEdgeAnchor: edge is Map
          ? _offset(edge['anchor']) ?? Offset.zero
          : Offset.zero,
      straightEdgeAngle: edge is Map ? _num(edge['angle']) ?? 0 : 0,
    );
  }

  void write(File file) {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(toJson()),
    );
  }

  static AsmrSession? read(File file) {
    if (!file.existsSync()) return null;
    final raw = jsonDecode(file.readAsStringSync());
    return fromJson(raw);
  }
}

/// The picks that rebuild [net].
List<HologramPick> picksOfNet(AsmrNet net) => [
  for (final face in net.faces) HologramPick(face.face, from: face.parent),
];

Map<String, dynamic> _pickJson(HologramPick pick) => {
  'face': pick.face,
  if (pick.from != null) 'from': pick.from,
};

List<HologramPick> _picks(Object? raw) {
  if (raw is! List) return const [];
  final picks = <HologramPick>[];
  for (final entry in raw) {
    if (entry is! Map || entry['face'] is! num) continue;
    picks.add(
      HologramPick(
        (entry['face'] as num).toInt(),
        from: entry['from'] is num ? (entry['from'] as num).toInt() : null,
      ),
    );
  }
  return picks;
}

Map<String, dynamic> _pieceJson(
  AsmrPiece piece,
  List<HologramPick> binding,
) => {
  'id': piece.id,
  'paper': piece.paper.id,
  'ring': [for (final p in piece.ring) _offsetJson(p)],
  'holes': [
    for (final hole in piece.holes) [for (final p in hole) _offsetJson(p)],
  ],
  'position': _offsetJson(piece.position),
  'angle': piece.angle,
  'liberated': piece.liberated,
  'scores': [
    for (final score in piece.scores) [for (final p in score) _offsetJson(p)],
  ],
  if (binding.isNotEmpty)
    'binding': [for (final pick in binding) _pickJson(pick)],
};

AsmrPiece? _piece(Map raw) {
  final id = raw['id'];
  final paperId = raw['paper'];
  if (id is! String || paperId is! String) return null;
  AsmrPaper? paper;
  for (final candidate in kAsmrPapers) {
    if (candidate.id == paperId) paper = candidate;
  }
  if (paper == null) return null;
  final ring = _ring(raw['ring']);
  if (ring.length < 3) return null;
  return AsmrPiece(
    id: id,
    paper: paper,
    ring: ring,
    holes: [
      if (raw['holes'] is List)
        for (final hole in raw['holes'] as List)
          if (_ring(hole).length >= 3) _ring(hole),
    ],
    position: _offset(raw['position']) ?? Offset.zero,
    angle: _num(raw['angle']) ?? 0,
    liberated: raw['liberated'] == true,
    scores: [
      if (raw['scores'] is List)
        for (final score in raw['scores'] as List)
          if (_ring(score).length >= 2) _ring(score),
    ],
  );
}

List<Offset> _ring(Object? raw) {
  if (raw is! List) return const [];
  return [for (final p in raw) ?_offset(p)];
}

List<double> _offsetJson(Offset p) => [p.dx, p.dy];

Offset? _offset(Object? raw) {
  if (raw is! List || raw.length < 2) return null;
  final x = _num(raw[0]);
  final y = _num(raw[1]);
  if (x == null || y == null) return null;
  return Offset(x, y);
}

double? _num(Object? raw) => raw is num ? raw.toDouble() : null;
