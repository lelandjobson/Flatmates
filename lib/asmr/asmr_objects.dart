import 'package:flutter/material.dart';

import '../craftroom/room_crafts.dart';
import '../gridcraft/cube_blueprint.dart' show kBoxStackId;
import '../gridcraft/folded_model.dart';
import '../gridcraft/papercrafts.dart';
import 'asmr_cube.dart';

/// Id of the cube the ASMR view opens on.
const String kAsmrCubeId = 'cube';

final Map<String, FoldedModel> _built = {};

/// One shape the ASMR view can craft.
class AsmrObject {
  const AsmrObject({required this.id, required this.name, required this.build});

  final String id;
  final String name;

  /// Builds the folded model. [model] keeps the result.
  final FoldedModel Function() build;

  FoldedModel get model => _built[id] ??= build();
}

List<AsmrObject>? _objects;

/// The cube, the double cube, and the papercrafts, in menu order.
List<AsmrObject> asmrObjects() => _objects ??= [
  const AsmrObject(id: kAsmrCubeId, name: 'Cube', build: asmrCubeModel),
  AsmrObject(
    id: kBoxStackId,
    name: 'Double cube',
    build: () => roomCraft(kBoxStackId)!.model,
  ),
  for (final design in papercraftDesigns())
    AsmrObject(
      id: design.puzzleId,
      name: design.name,
      build: () => roomCraft(design.puzzleId)!.model,
    ),
];

/// The object with [id], or null when the view does not know it.
AsmrObject? asmrObjectById(String id) {
  for (final object in asmrObjects()) {
    if (object.id == id) return object;
  }
  return null;
}

/// The object menu in the ASMR DevTools sheet.
class AsmrObjectMenu extends StatelessWidget {
  const AsmrObjectMenu({
    super.key,
    required this.objectId,
    required this.onSelected,
  });

  final String objectId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Object',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 4),
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white24),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                key: const Key('asmr-object'),
                isExpanded: true,
                isDense: true,
                dropdownColor: const Color(0xFF1A1A1A),
                iconEnabledColor: Colors.white70,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                value: objectId,
                items: [
                  for (final object in asmrObjects())
                    DropdownMenuItem(
                      value: object.id,
                      child: Text(
                        object.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                    ),
                ],
                onChanged: (id) {
                  if (id != null) onSelected(id);
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}
