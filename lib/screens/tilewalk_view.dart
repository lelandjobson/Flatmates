import 'package:flutter/material.dart';

import '../flatgram/flatgram_models.dart';
import '../flatgram/flatgram_painter.dart';
import '../tilewalk/tilewalk_models.dart';
import '../tilewalk/tilewalk_painter.dart';
import '../tilewalk/tilewalk_projector.dart';
import '../tilewalk/tilewalk_puzzles.dart';
import '../tilewalk/tilewalk_rules.dart';
import '../ui/fm_dev_back_button.dart';
import '../ui/fm_haptics.dart';
import '../ui/fm_screen.dart';

/// Top-down tile walk. Swipes move the cube. Tap a piece, then drag it.
class TilewalkView extends StatefulWidget {
  const TilewalkView({super.key});

  @override
  State<TilewalkView> createState() => _TilewalkViewState();
}

class _TilewalkViewState extends State<TilewalkView>
    with TickerProviderStateMixin {
  late final AnimationController _walk;
  late final AnimationController _pulse;

  int _index = 0;
  late TilewalkSession _session;
  String? _selectedId;

  bool _dragging = false;
  String? _dragId;
  GridPoint? _dragAnchor;
  Offset _grab = Offset.zero;
  Offset? _panStart;

  Size _boardSize = Size.zero;
  final GlobalKey _boardKey = GlobalKey();

  double _walkFromX = 0;
  double _walkFromY = 0;
  double _walkToX = 0;
  double _walkToY = 0;

  @override
  void initState() {
    super.initState();
    _walk = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _load(0);
  }

  @override
  void dispose() {
    _walk.dispose();
    _pulse.dispose();
    super.dispose();
  }

  void _load(int index) {
    final puzzle = kTilewalkPuzzles[index.clamp(0, kTilewalkPuzzles.length - 1)];
    _walk.stop();
    _walk.value = 1;
    setState(() {
      _index = index;
      _session = TilewalkSession.start(puzzle);
      _selectedId = null;
      _dragging = false;
      _dragId = null;
      _dragAnchor = null;
      _panStart = null;
      _walkFromX = puzzle.startCell.x.toDouble();
      _walkFromY = puzzle.startCell.y.toDouble();
      _walkToX = _walkFromX;
      _walkToY = _walkFromY;
    });
  }

  TilewalkProjector get _projector =>
      TilewalkProjector.fit(_boardSize, _session.puzzle.bounds);

  double get _cubeX {
    final t = Curves.easeOutCubic.transform(_walk.value);
    return _walkFromX + (_walkToX - _walkFromX) * t;
  }

  double get _cubeY {
    final t = Curves.easeOutCubic.transform(_walk.value);
    return _walkFromY + (_walkToY - _walkFromY) * t;
  }

  PlacedPiece? get _ghost {
    final id = _dragId;
    final anchor = _dragAnchor;
    if (!_dragging || id == null || anchor == null) return null;
    return PlacedPiece(
      pieceId: id,
      anchor: anchor,
      turns: _session.orientation(id),
    );
  }

  bool get _ghostValid {
    final ghost = _ghost;
    if (ghost == null) return false;
    return placementFits(
      _session,
      ghost.pieceId,
      ghost.anchor,
      ghost.turns,
    );
  }

  void _step(TilewalkStep step) {
    if (_dragging) return;
    final next = stepCube(_session, step);
    if (identical(next, _session)) return;
    final collected = next.tray.length > _session.tray.length;
    final fromX = _cubeX;
    final fromY = _cubeY;
    setState(() {
      _session = next;
      _walkFromX = fromX;
      _walkFromY = fromY;
      _walkToX = next.cube.x.toDouble();
      _walkToY = next.cube.y.toDouble();
      if (_selectedId != null && !canMoveTile(next, _selectedId!)) {
        _selectedId = null;
      }
    });
    _walk.forward(from: 0);
    if (next.won) {
      fmHaptic(FmHapticStyle.heavyImpact);
    } else if (collected) {
      fmHaptic(FmHapticStyle.lightImpact);
    } else {
      fmHaptic(FmHapticStyle.selectionClick);
    }
  }

  void _rotate(String pieceId) {
    final next = rotateTile(_session, pieceId);
    if (identical(next, _session)) return;
    setState(() => _session = next);
    fmHaptic(FmHapticStyle.selectionClick);
  }

  void _drop() {
    final id = _dragId;
    final anchor = _dragAnchor;
    if (id == null || anchor == null) {
      setState(_clearDrag);
      return;
    }
    final next = placeTile(_session, id, anchor);
    final placed = !identical(next, _session);
    setState(() {
      if (placed) {
        _session = next;
        _selectedId = id;
      }
      _clearDrag();
    });
    if (!placed) return;
    if (next.won) {
      fmHaptic(FmHapticStyle.heavyImpact);
    } else {
      fmHaptic(FmHapticStyle.lightImpact);
    }
  }

  void _clearDrag() {
    _dragging = false;
    _dragId = null;
    _dragAnchor = null;
    _panStart = null;
  }

  List<TilewalkIconMark> _marks() {
    return tilewalkIconMarks(
      projector: _projector,
      session: _session,
      selectedPieceId: _selectedId,
      hiddenPieceId: _dragging ? _dragId : null,
      ghost: _ghost,
    );
  }

  String? _pieceOnCell(GridPoint cell) {
    for (final item in _session.placed) {
      if (_dragging && item.pieceId == _dragId) continue;
      final cells = _session
          .piece(item.pieceId)
          .transformedCells(item.anchor, item.turns);
      if (cells.contains(cell)) return item.pieceId;
    }
    return null;
  }

  GridPoint? _cellAt(Offset local) {
    GridPoint? best;
    var bestDistance = 34.0;
    for (final cell in _session.puzzle.cells) {
      final center = _projector.project(cell.x + 0.5, cell.y + 0.5, 0.18);
      final distance = (center - local).distance;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = cell;
      }
    }
    return best;
  }

  void _onBoardTap(Offset local) {
    if (_session.won) return;
    for (final mark in _marks().reversed) {
      if (!mark.contains(local)) continue;
      if (mark.pickup || mark.locked) return;
      if (_selectedId == mark.pieceId) {
        _rotate(mark.pieceId);
      } else {
        setState(() => _selectedId = mark.pieceId);
        fmHaptic(FmHapticStyle.selectionClick);
      }
      return;
    }
    final cell = _cellAt(local);
    final pieceId = cell == null ? null : _pieceOnCell(cell);
    if (pieceId == null) {
      setState(() => _selectedId = null);
      return;
    }
    if (!canMoveTile(_session, pieceId)) return;
    if (_selectedId == pieceId) {
      _rotate(pieceId);
    } else {
      setState(() => _selectedId = pieceId);
      fmHaptic(FmHapticStyle.selectionClick);
    }
  }

  bool _panHitsSelected(Offset local) {
    final selected = _selectedId;
    if (selected == null || _session.tray.contains(selected)) return false;
    if (!canMoveTile(_session, selected)) return false;
    for (final mark in _marks()) {
      if (mark.pieceId == selected && !mark.pickup && mark.contains(local)) {
        return true;
      }
    }
    final cell = _cellAt(local);
    return cell != null && _pieceOnCell(cell) == selected;
  }

  void _onBoardPanStart(Offset local) {
    _panStart = local;
    if (!_panHitsSelected(local)) return;
    final placed = _session.placementOf(_selectedId!);
    if (placed == null) return;
    final corner = _projector.project(
      placed.anchor.x.toDouble(),
      placed.anchor.y.toDouble(),
      0.18,
    );
    setState(() {
      _dragging = true;
      _dragId = placed.pieceId;
      _dragAnchor = placed.anchor;
      _grab = local - corner;
    });
  }

  void _onBoardPanUpdate(Offset local) {
    if (!_dragging || _dragId == null) return;
    setState(() {
      _dragAnchor = _projector.nearestAnchor(
        local - _grab,
        _session.puzzle.bounds,
      );
    });
  }

  void _onBoardPanEnd(DragEndDetails details) {
    if (_dragging) {
      _drop();
      return;
    }
    final start = _panStart;
    _panStart = null;
    if (start == null || _session.won) return;
    final delta = details.localPosition - start;
    final velocity = details.velocity.pixelsPerSecond;
    final travel = delta.distance >= 28 ? delta : velocity;
    if (delta.distance < 28 && velocity.distance < 450) return;
    if (travel.dx.abs() >= travel.dy.abs()) {
      _step(travel.dx >= 0 ? TilewalkStep.right : TilewalkStep.left);
    } else {
      _step(travel.dy >= 0 ? TilewalkStep.down : TilewalkStep.up);
    }
  }

  Offset? _toBoard(Offset global) {
    final box = _boardKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.globalToLocal(global);
  }

  void _onTrayPanStart(FlatgramPiece piece, Offset global) {
    if (_session.won || !canMoveTile(_session, piece.id)) return;
    final local = _toBoard(global);
    if (local == null) return;
    setState(() {
      _selectedId = piece.id;
      _dragging = true;
      _dragId = piece.id;
      _grab = Offset.zero;
      _dragAnchor = _projector.nearestAnchor(local, _session.puzzle.bounds);
    });
    fmHaptic(FmHapticStyle.selectionClick);
  }

  void _onTrayPanUpdate(String pieceId, Offset global) {
    if (!_dragging || _dragId != pieceId) return;
    final local = _toBoard(global);
    if (local == null) return;
    setState(() {
      _dragAnchor = _projector.nearestAnchor(local - _grab, _session.puzzle.bounds);
    });
  }

  @override
  Widget build(BuildContext context) {
    final covered = coveredCells(_session).length;
    final total = _session.puzzle.cells.length;
    return FmScreen(
      backgroundColor: const Color(0xFF0F121A),
      overlays: const [FmDevBackButton()],
      content: Column(
        children: [
          _buildTopBar(covered, total),
          Expanded(child: _buildBoard()),
          _buildTray(),
        ],
      ),
    );
  }

  Widget _buildTopBar(int covered, int total) {
    final puzzle = _session.puzzle;
    final status = _session.won
        ? 'You made it out'
        : showDoor(_session)
            ? 'Swipe onto the door'
            : 'Swipe to walk · $covered/$total tiles';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 72),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    puzzle.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => _load(_index),
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
                  tooltip: 'Reset',
                ),
              ],
            ),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (var i = 0; i < kTilewalkPuzzles.length; i++)
                _pill(kTilewalkPuzzles[i].difficulty, i),
            ],
          ),
          Text(
            status,
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _pill(String label, int index) {
    final selected = index == _index;
    final title = label[0].toUpperCase() + label.substring(1);
    return GestureDetector(
      onTap: () => _load(index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFC107) : const Color(0xFF1E2333),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? const Color(0xFFFFC107) : Colors.white24),
        ),
        child: Text(
          title,
          style: TextStyle(
            color: selected ? Colors.black : Colors.white70,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildBoard() {
    return LayoutBuilder(
      builder: (context, constraints) {
        _boardSize = Size(constraints.maxWidth, constraints.maxHeight);
        final projector = _projector;
        return Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              key: _boardKey,
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) => _onBoardTap(details.localPosition),
              onPanStart: (details) => _onBoardPanStart(details.localPosition),
              onPanUpdate: (details) => _onBoardPanUpdate(details.localPosition),
              onPanEnd: _onBoardPanEnd,
              onPanCancel: () => setState(_clearDrag),
              child: AnimatedBuilder(
                animation: Listenable.merge([_walk, _pulse]),
                builder: (context, _) {
                  return CustomPaint(
                    painter: TilewalkPainter(
                      session: _session,
                      projector: projector,
                      cubeX: _cubeX,
                      cubeY: _cubeY,
                      selectedPieceId: _selectedId,
                      hiddenPieceId: _dragging ? _dragId : null,
                      ghost: _ghost,
                      ghostValid: _ghostValid,
                      doorPulse: _pulse.value,
                    ),
                    child: const SizedBox.expand(),
                  );
                },
              ),
            ),
            if (!_session.won)
              Positioned(
                left: 16,
                right: 16,
                bottom: 10,
                child: IgnorePointer(
                  child: Text(
                    showDoor(_session)
                        ? 'The door is open'
                        : _session.puzzle.description,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildTray() {
    final pieces = [for (final id in _session.tray) _session.piece(id)];
    return Container(
      height: 112,
      decoration: const BoxDecoration(
        color: Color(0xFF131722),
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 2),
            child: Text(
              'Tap, drag onto the floor, tap again to turn',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: pieces.isEmpty
                ? const Center(
                    child: Text(
                      'No pieces in hand',
                      style: TextStyle(
                        color: Colors.white38,
                        fontStyle: FontStyle.italic,
                        fontSize: 12,
                      ),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Row(
                      children: [
                        for (var i = 0; i < pieces.length; i++) ...[
                          if (i > 0) const SizedBox(width: 12),
                          _trayCard(pieces[i]),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _trayCard(FlatgramPiece piece) {
    final turns = _session.orientation(piece.id);
    final selected = _selectedId == piece.id;
    return GestureDetector(
      onTap: () {
        if (_session.won) return;
        if (_selectedId == piece.id) {
          _rotate(piece.id);
        } else {
          setState(() => _selectedId = piece.id);
          fmHaptic(FmHapticStyle.selectionClick);
        }
      },
      onPanStart: (details) => _onTrayPanStart(piece, details.globalPosition),
      onPanUpdate: (details) => _onTrayPanUpdate(piece.id, details.globalPosition),
      onPanEnd: (_) {
        if (_dragging && _dragId == piece.id) _drop();
      },
      onPanCancel: () {
        if (_dragging && _dragId == piece.id) setState(_clearDrag);
      },
      child: Container(
        width: 84,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF252B3B) : const Color(0xFF1B202D),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? const Color(0xFFFFC107) : Colors.white24,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CustomPaint(
                size: const Size(56, 28),
                painter: TrayPiecePainter(piece: piece, turns: turns),
              ),
              Text(
                '${turns * 90}°',
                style: const TextStyle(color: Colors.white38, fontSize: 10, height: 1.1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
