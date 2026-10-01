import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../gridcraft/blueprint.dart';
import '../../gridcraft/level_io.dart';

const Color _hud = Color(0xFF1A1A1A);

/// Which puzzle in which collection the player chose.
class PlayLibraryPick {
  const PlayLibraryPick({
    required this.collectionIndex,
    required this.puzzleIndex,
  });

  final int collectionIndex;
  final int puzzleIndex;
}

/// Collections on the left, that collection's puzzles on the right.
class PlayLibraryDialog extends StatefulWidget {
  const PlayLibraryDialog({
    super.key,
    required this.collections,
    required this.collectionIndex,
    required this.puzzleIndex,
  });

  final List<PuzzleCollection> collections;
  final int collectionIndex;
  final int puzzleIndex;

  @override
  State<PlayLibraryDialog> createState() => _PlayLibraryDialogState();
}

class _PlayLibraryDialogState extends State<PlayLibraryDialog> {
  late final TextEditingController _search;
  late int _selected;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController();
    _selected = widget.collectionIndex.clamp(
      0,
      math.max(0, widget.collections.length - 1),
    );
  }

  int get _lastCollection => math.max(0, widget.collections.length - 1);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final visible = <int>[
      for (var i = 0; i < widget.collections.length; i++)
        if (_collectionVisible(widget.collections[i], query)) i,
    ];
    final selected = visible.contains(_selected)
        ? _selected
        : (visible.isEmpty ? 0 : visible.first);
    final collection = widget.collections.isEmpty
        ? null
        : widget.collections[selected.clamp(0, _lastCollection)];
    final puzzles = collection == null
        ? const <int>[]
        : [
            for (var i = 0; i < collection.puzzles.length; i++)
              if (_puzzleVisible(collection, collection.puzzles[i], query)) i,
          ];
    return Dialog(
      key: const Key('grid-library'),
      backgroundColor: _hud,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 520,
        height: 420,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const Key('grid-library-search'),
                controller: _search,
                style: const TextStyle(color: Colors.white),
                cursorColor: Colors.white,
                decoration: const InputDecoration(
                  hintText: 'Search',
                  hintStyle: TextStyle(color: Colors.white38),
                  prefixIcon: Icon(Icons.search, color: Colors.white54),
                  border: InputBorder.none,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _scrollList(
                        title: 'Collections',
                        empty: 'No collections',
                        children: [
                          for (final index in visible)
                            _row(
                              key: Key(
                                'grid-collection-item-${widget.collections[index].id}',
                              ),
                              label: widget.collections[index].name,
                              selected: index == selected,
                              onTap: () => setState(() => _selected = index),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _scrollList(
                        title: 'Puzzles',
                        empty: 'No puzzles',
                        children: [
                          if (collection != null)
                            for (final index in puzzles)
                              _row(
                                key: Key(
                                  'grid-puzzle-item-${collection.puzzles[index].id}',
                                ),
                                label: collection.puzzles[index].name,
                                selected:
                                    selected == widget.collectionIndex &&
                                    index == widget.puzzleIndex,
                                onTap: () => Navigator.pop(
                                  context,
                                  PlayLibraryPick(
                                    collectionIndex: selected,
                                    puzzleIndex: index,
                                  ),
                                ),
                              ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

bool _collectionVisible(PuzzleCollection collection, String query) {
  if (query.isEmpty) return true;
  if (collection.name.toLowerCase().contains(query)) return true;
  return collection.puzzles.any(
    (puzzle) => puzzle.name.toLowerCase().contains(query),
  );
}

bool _puzzleVisible(
  PuzzleCollection collection,
  GridBlueprint puzzle,
  String query,
) {
  if (query.isEmpty || collection.name.toLowerCase().contains(query)) {
    return true;
  }
  return puzzle.name.toLowerCase().contains(query);
}

Widget _scrollList({
  required String title,
  required String empty,
  required List<Widget> children,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(title, style: const TextStyle(color: Colors.white54, fontSize: 12)),
      const SizedBox(height: 6),
      Expanded(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF111111),
            borderRadius: BorderRadius.circular(8),
          ),
          child: children.isEmpty
              ? Center(
                  child: Text(
                    empty,
                    style: const TextStyle(color: Colors.white38),
                  ),
                )
              : ListView(children: children),
        ),
      ),
    ],
  );
}

Widget _row({
  required Key key,
  required String label,
  required bool selected,
  required VoidCallback onTap,
}) {
  return Material(
    color: selected ? const Color(0xFF2E2E2E) : Colors.transparent,
    child: InkWell(
      key: key,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white),
        ),
      ),
    ),
  );
}
