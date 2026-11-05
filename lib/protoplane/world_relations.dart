import 'dart:collection';

import 'models.dart';

enum CraftEntityKind { plane, object }

typedef CraftEntity = ({CraftEntityKind kind, String id});

CraftEntity planeEntity(String id) => (kind: CraftEntityKind.plane, id: id);
CraftEntity objectEntity(String id) => (kind: CraftEntityKind.object, id: id);

/// Directed from prerequisite/parent to dependent. These are deliberately
/// separate from navigation: support does not imply a traversable shared edge.
enum CraftRelationKind { placedOn, derivedFrom, supportedBy, attachment }

typedef CraftRelation = ({
  CraftEntity from,
  CraftEntity to,
  CraftRelationKind kind,
});

class CraftRelations {
  CraftRelations(
    Map<String, CraftPlane> planes,
    Map<String, CraftObject> objects,
  ) {
    void add(CraftEntity from, CraftEntity to, CraftRelationKind kind) {
      final edge = (from: from, to: to, kind: kind);
      (_outgoing[from] ??= []).add(edge);
      (_incoming[to] ??= []).add(edge);
    }

    for (final object in objects.values) {
      if (planes.containsKey(object.planeId)) {
        add(
          planeEntity(object.planeId),
          objectEntity(object.id),
          CraftRelationKind.placedOn,
        );
      }
      for (final id in object.attachmentIds) {
        if (objects.containsKey(id)) {
          add(
            objectEntity(object.id),
            objectEntity(id),
            CraftRelationKind.attachment,
          );
        }
      }
    }
    for (final object in objects.values) {
      final source = object.linear?.sourcePlaneId;
      if (source != null && planes.containsKey(source)) {
        add(
          planeEntity(source),
          planeEntity(object.planeId),
          CraftRelationKind.derivedFrom,
        );
      }
    }
    for (final plane in planes.values) {
      if (objects.containsKey(plane.owner)) {
        add(
          objectEntity(plane.owner!),
          planeEntity(plane.id),
          CraftRelationKind.derivedFrom,
        );
      }
      for (final id in plane.supports) {
        if (objects.containsKey(id)) {
          add(
            objectEntity(id),
            planeEntity(plane.id),
            CraftRelationKind.supportedBy,
          );
        }
      }
    }
  }

  final _outgoing = <CraftEntity, List<CraftRelation>>{};
  final _incoming = <CraftEntity, List<CraftRelation>>{};

  List<CraftRelation> outgoing(CraftEntity entity) =>
      List.unmodifiable(_outgoing[entity] ?? const []);
  List<CraftRelation> incoming(CraftEntity entity) =>
      List.unmodifiable(_incoming[entity] ?? const []);

  /// Breadth-first dependency closure, deduplicating multiply supported nodes.
  Iterable<CraftEntity> dependents(CraftEntity entity) sync* {
    final seen = {entity}, pending = Queue<CraftEntity>()..add(entity);
    while (pending.isNotEmpty) {
      for (final edge
          in _outgoing[pending.removeFirst()] ?? <CraftRelation>[]) {
        if (!seen.add(edge.to)) continue;
        yield edge.to;
        pending.add(edge.to);
      }
    }
  }
}
