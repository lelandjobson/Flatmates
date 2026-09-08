import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../picking/selectable.dart';
import '../../ui/game/game_tool_carousel.dart';

/// How to walk the player to the place they can fix this alert.
class AlertRemediation {
  const AlertRemediation({
    required this.mode,
    required this.lookAt,
    this.createTool,
    this.distance,
    this.select = false,
    this.tx,
    this.ty,
    this.volumeId,
    this.selectKind,
    this.openProgramPicker = false,
  });

  final GameMode mode;
  final GameCreateTool? createTool;
  final Vector3 lookAt;
  final double? distance;
  final bool select;
  final int? tx;
  final int? ty;
  final int? volumeId;
  final SelectableKind? selectKind;
  final bool openProgramPicker;
}

/// One fixable issue inside a [WorldAlert] sandwich.
class WorldAlertIssue {
  const WorldAlertIssue({
    required this.id,
    required this.requirementIcon,
    required this.remediation,
  });

  final String id;
  final IconData requirementIcon;
  final AlertRemediation remediation;
}

/// Derived issues for one world object. One pill per host.
class WorldAlert {
  const WorldAlert({
    required this.id,
    required this.hostKey,
    required this.world,
    required this.issues,
  });

  final String id;
  final String hostKey;
  final Vector3 world;
  final List<WorldAlertIssue> issues;

  WorldAlertIssue get primary => issues.first;
}
