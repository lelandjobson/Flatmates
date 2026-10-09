import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../flatgram/flatgram_constraints.dart';
import '../flatgram/flatgram_models.dart';
import '../flatgram/flatgram_painter.dart';
import '../flatgram/flatgram_puzzles.dart';
import '../ui/fm_dev_back_button.dart';
import '../ui/fm_haptics.dart';
import '../ui/fm_screen.dart';

/// Single-view Flatgram puzzle game.
///
/// Features a blueprint board with subregions and NYT Pips-style constraints,
/// dot grid background, drag-to-board transforms, bottom piece tray,
/// and victory evaluation only when all spaces are occupied.
class FlatgramView extends StatefulWidget {
  const FlatgramView({super.key});

  @override
  State<FlatgramView> createState() => _FlatgramViewState();
}

class _FlatgramViewState extends State<FlatgramView>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _rotationController;
  late final Animation<double> _rotationAnimation;
  final FlatgramRuleEngine _ruleEngine = FlatgramRuleEngine();

  int _selectedPuzzleIndex = 0;
  late FlatgramPuzzle _puzzle;
  final List<PlacedPiece> _placed = [];
  final Map<String, FlatgramPiece> _pieces = {};

  String? _selectedPieceId;

  // Board layout math
  final double _cellSize = 54.0;
  Offset _boardOffset = Offset.zero;
  double _canvasHeight = 800.0;

  // Dragging & tap rotation state
  PlacedPiece? _potentialDragPlacement;
  FlatgramPiece? _dragPiece;
  GridPoint? _dragAnchor;
  Offset? _dragVisualAnchor;
  bool _isDragging = false;
  Offset? _dragStartPos;
  PlacedPiece? _draggedOriginalPlacement;
  Offset _dragGrabOffsetPx = Offset.zero;

  // 0.25-second animated rotation
  String? _rotatingPieceId;
  int _rotationStartTurns = 0;

  bool _puzzleWon = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _rotationAnimation = CurvedAnimation(
      parent: _rotationController,
      curve: Curves.easeOutCubic,
    );
    _rotationController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _finishRotation();
      }
    });

    _loadPuzzle(_selectedPuzzleIndex);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rotationController.dispose();
    super.dispose();
  }

  void _loadPuzzle(int index) {
    _rotatingPieceId = null;
    _rotationController.stop();
    setState(() {
      _selectedPuzzleIndex = index.clamp(0, kFlatgramPuzzles.length - 1);
      _puzzle = kFlatgramPuzzles[_selectedPuzzleIndex];
      _placed.clear();
      _placed.addAll(_puzzle.initialPlaced);
      _pieces.clear();
      for (final p in _puzzle.pieces) {
        _pieces[p.id] = p;
      }
      _selectedPieceId = null;
      _dragPiece = null;
      _dragAnchor = null;
      _dragVisualAnchor = null;
      _isDragging = false;
      _potentialDragPlacement = null;
      _draggedOriginalPlacement = null;
      _puzzleWon = false;
    });
  }

  FlatgramEvaluation _evaluate() {
    return _ruleEngine.evaluate(
      board: _puzzle.board,
      pieces: _pieces.values.toList(),
      placed: _placed,
      constraints: _puzzle.constraints,
    );
  }

  void _checkVictory(FlatgramEvaluation evaluation) {
    if (evaluation.isWon && !_puzzleWon) {
      _puzzleWon = true;
      fmHaptic(kFmHapticBigClick);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showVictoryDialog();
      });
    }
  }

  void _showVictoryDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final hasNext = _selectedPuzzleIndex < kFlatgramPuzzles.length - 1;
        return AlertDialog(
          backgroundColor: const Color(0xFF1E2230),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Colors.amber, width: 1.5),
          ),
          title: const Row(
            children: [
              Icon(Icons.stars_rounded, color: Colors.amber, size: 28),
              SizedBox(width: 8),
              Text(
                'Flatgram Solved!',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'All ${_puzzle.board.cellCount} spaces are filled, and all ${_puzzle.constraints.length} rules are satisfied.',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Difficulty: ${_puzzle.difficulty.toUpperCase()} • ${_puzzle.title}',
                  style: const TextStyle(
                    color: Colors.amberAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _loadPuzzle(_selectedPuzzleIndex);
              },
              child: const Text('Replay', style: TextStyle(color: Colors.white60)),
            ),
            if (hasNext)
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () {
                  Navigator.of(context).pop();
                  _loadPuzzle(_selectedPuzzleIndex + 1);
                },
                child: const Text(
                  'Next Puzzle →',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              )
            else
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
          ],
        );
      },
    );
  }

  void _startPieceRotation(String pieceId) {
    if (_rotatingPieceId != null) {
      _finishRotation();
    }

    final idx = _placed.indexWhere((p) => p.pieceId == pieceId);
    if (idx < 0) return;

    final placed = _placed[idx];
    setState(() {
      _selectedPieceId = pieceId;
      _rotatingPieceId = pieceId;
      _rotationStartTurns = placed.turns;
    });

    fmHaptic(FmHapticStyle.selectionClick);
    _rotationController.forward(from: 0.0);
  }

  void _finishRotation() {
    if (_rotatingPieceId == null) return;
    final pieceId = _rotatingPieceId!;
    final startTurns = _rotationStartTurns;
    _rotatingPieceId = null;
    _rotationController.stop();

    final idx = _placed.indexWhere((p) => p.pieceId == pieceId);
    if (idx >= 0) {
      final current = _placed[idx];
      final nextTurns = (startTurns + 1) % 4;
      _placed[idx] = current.copyWith(turns: nextTurns);
    }

    _checkVictory(_evaluate());
    setState(() {});
  }

  void _resetPuzzle() {
    _rotatingPieceId = null;
    _rotationController.stop();
    setState(() {
      _placed.clear();
      _placed.addAll(_puzzle.initialPlaced);
      _selectedPieceId = null;
      _dragPiece = null;
      _dragAnchor = null;
      _dragVisualAnchor = null;
      _isDragging = false;
      _potentialDragPlacement = null;
      _draggedOriginalPlacement = null;
      _puzzleWon = false;
    });
    fmHaptic(FmHapticStyle.mediumImpact);
  }

  // Pointer interactions on canvas: tap to rotate, drag to reposition
  void _onPointerDown(PointerDownEvent event) {
    if (_rotatingPieceId != null) {
      _finishRotation();
    }

    _dragStartPos = event.localPosition;
    final local = event.localPosition - _boardOffset;
    final gridX = (local.dx / _cellSize).floor();
    final gridY = (local.dy / _cellSize).floor();
    final clickedCell = GridPoint(gridX, gridY);

    // Hit test placed pieces
    PlacedPiece? hitPlaced;
    for (final p in _placed.reversed) {
      final piece = _pieces[p.pieceId];
      if (piece == null) continue;
      final cells = piece.transformedCells(p.anchor, p.turns);
      if (cells.contains(clickedCell)) {
        hitPlaced = p;
        break;
      }
    }

    if (hitPlaced != null) {
      _potentialDragPlacement = hitPlaced;
      final initialAnchorScreen = Offset(
        _boardOffset.dx + hitPlaced.anchor.x * _cellSize,
        _boardOffset.dy + hitPlaced.anchor.y * _cellSize,
      );
      _dragGrabOffsetPx = event.localPosition - initialAnchorScreen;
      _isDragging = false;
      setState(() {
        _selectedPieceId = hitPlaced!.pieceId;
      });
    } else {
      _potentialDragPlacement = null;
      setState(() {
        _selectedPieceId = null;
      });
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_isDragging && _dragPiece != null) {
      final screenPos = event.localPosition;
      final currentAnchorScreenPos = screenPos - _dragGrabOffsetPx;
      final boardLocal = currentAnchorScreenPos - _boardOffset;
      final candidateAnchor = GridPoint(
        (boardLocal.dx / _cellSize).round(),
        (boardLocal.dy / _cellSize).round(),
      );

      setState(() {
        _dragVisualAnchor = currentAnchorScreenPos;
        _dragAnchor = candidateAnchor;
      });
      return;
    }

    if (!_isDragging &&
        _potentialDragPlacement != null &&
        _dragStartPos != null) {
      final dist = (event.localPosition - _dragStartPos!).distance;
      if (dist >= 6.0) {
        final targetPlaced = _potentialDragPlacement!;
        final piece = _pieces[targetPlaced.pieceId];
        if (piece != null) {
          final screenPos = event.localPosition;
          final currentAnchorScreenPos = screenPos - _dragGrabOffsetPx;
          final boardLocal = currentAnchorScreenPos - _boardOffset;
          final candidateAnchor = GridPoint(
            (boardLocal.dx / _cellSize).round(),
            (boardLocal.dy / _cellSize).round(),
          );

          setState(() {
            _isDragging = true;
            _selectedPieceId = targetPlaced.pieceId;
            _dragPiece = piece.copyWith(turns: targetPlaced.turns);
            _dragAnchor = candidateAnchor;
            _dragVisualAnchor = currentAnchorScreenPos;
            _draggedOriginalPlacement = targetPlaced;
            _potentialDragPlacement = null;
          });
          fmHaptic(FmHapticStyle.selectionClick);
        }
      }
    }
  }

  void _dropPiece(Offset screenPos) {
    if (!_isDragging || _dragPiece == null) {
      _isDragging = false;
      return;
    }

    final piece = _dragPiece!;
    final original = _draggedOriginalPlacement;
    final anchor = _dragAnchor;

    // Check if dropped into tray area (bottom 130px of canvas)
    final droppedInTray = screenPos.dy > (_canvasHeight - 130);

    if (droppedInTray) {
      // Returned to tray
      setState(() {
        if (original != null) {
          _placed.removeWhere((p) => p.pieceId == original.pieceId);
          _selectedPieceId = null;
        }
      });
      fmHaptic(FmHapticStyle.lightImpact);
    } else if (anchor != null) {
      // Sticks anywhere in the crafting view!
      setState(() {
        if (original != null) {
          _placed.removeWhere((p) => p.pieceId == original.pieceId);
        }
        _placed.add(PlacedPiece(
          pieceId: piece.id,
          anchor: anchor,
          turns: piece.turns,
        ));
        _selectedPieceId = piece.id;
      });
      fmHaptic(FmHapticStyle.selectionClick);
      _checkVictory(_evaluate());
    }

    setState(() {
      _isDragging = false;
      _dragPiece = null;
      _dragAnchor = null;
      _dragVisualAnchor = null;
      _draggedOriginalPlacement = null;
      _potentialDragPlacement = null;
    });
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_isDragging) {
      _dropPiece(event.localPosition);
      return;
    }

    if (_potentialDragPlacement != null) {
      final pieceId = _potentialDragPlacement!.pieceId;
      _potentialDragPlacement = null;
      _dragStartPos = null;
      _startPieceRotation(pieceId);
      return;
    }

    setState(() {
      _isDragging = false;
      _dragPiece = null;
      _dragAnchor = null;
      _dragVisualAnchor = null;
      _draggedOriginalPlacement = null;
      _potentialDragPlacement = null;
    });
  }

  // Tray drag to board
  void _startDraggingFromTray(
    FlatgramPiece piece,
    Offset globalPos,
    BoxConstraints constraints,
  ) {
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    final local = box != null ? box.globalToLocal(globalPos) : globalPos;

    final bounds = piece.localBounds(piece.turns);
    // Center the piece on the finger/cursor when dragged out from the tray
    final grabOffsetPx = Offset(
      bounds.center.dx * _cellSize,
      bounds.center.dy * _cellSize,
    );
    _dragGrabOffsetPx = grabOffsetPx;

    final currentAnchorScreenPos = local - grabOffsetPx;
    final boardLocal = currentAnchorScreenPos - _boardOffset;
    final candidateAnchor = GridPoint(
      (boardLocal.dx / _cellSize).round(),
      (boardLocal.dy / _cellSize).round(),
    );

    setState(() {
      _selectedPieceId = piece.id;
      _dragPiece = piece;
      _dragAnchor = candidateAnchor;
      _dragVisualAnchor = currentAnchorScreenPos;
      _dragStartPos = local;
      _draggedOriginalPlacement = null;
      _isDragging = true;
    });
    fmHaptic(FmHapticStyle.selectionClick);
  }



  @override
  Widget build(BuildContext context) {
    final placedIds = _placed.map((p) => p.pieceId).toSet();
    final trayPieces =
        _puzzle.pieces.where((p) => !placedIds.contains(p.id)).toList();

    final evaluation = _evaluate();
    final boardCellsCount = _puzzle.board.cellCount;
    final occupiedCount = evaluation.isFullyCovered
        ? boardCellsCount
        : (boardCellsCount - evaluation.uncoveredCells.length);

    final satisfiedRulesCount =
        evaluation.constraintResults.where((r) => r.satisfied).length;

    return FmScreen(
      backgroundColor: const Color(0xFF0F121A),
      content: LayoutBuilder(
        builder: (context, constraints) {
          _canvasHeight = constraints.maxHeight;
          // Center board in upper 65% of screen
          final boardBounds = _puzzle.board.computeBounds();
          final boardPixelW = boardBounds.width * _cellSize;
          final boardPixelH = boardBounds.height * _cellSize;

          final availableH = constraints.maxHeight - 170; // above tray
          _boardOffset = Offset(
            (constraints.maxWidth - boardPixelW) / 2 - boardBounds.left * _cellSize,
            (availableH - boardPixelH) / 2 + 50 - boardBounds.top * _cellSize,
          );

          return Stack(
            fit: StackFit.expand,
            children: [
              // Canvas area
              Positioned.fill(
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: _onPointerDown,
                  onPointerMove: _onPointerMove,
                  onPointerUp: _onPointerUp,
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_pulseController, _rotationAnimation]),
                    builder: (context, _) {
                      final rotationAngle = _rotatingPieceId != null
                          ? _rotationAnimation.value * (math.pi / 2)
                          : 0.0;
                      return CustomPaint(
                        painter: FlatgramPainter(
                          board: _puzzle.board,
                          placedPieces: _placed,
                          pieceCatalog: _pieces,
                          constraints: _puzzle.constraints,
                          evaluation: evaluation,
                          selectedPieceId: _selectedPieceId,
                          dragPiece: _dragPiece,
                          dragAnchor: _dragAnchor,
                          dragVisualAnchor: _dragVisualAnchor,
                          cellSize: _cellSize,
                          boardOffset: _boardOffset,
                          pulseValue: _pulseController.value,
                          rotatingPieceId: _rotatingPieceId,
                          rotationAngle: rotationAngle,
                        ),
                      );
                    },
                  ),
                ),
              ),

              // Top HUD
              Positioned(
                top: 8,
                left: 12,
                right: 12,
                child: _buildTopBar(
                  occupiedCount: occupiedCount,
                  totalCells: boardCellsCount,
                  satisfiedRules: satisfiedRulesCount,
                  totalRules: _puzzle.constraints.length,
                  isFull: evaluation.isFullyCovered,
                  isWon: evaluation.isWon,
                ),
              ),

              // Bottom Tray with available pieces
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildBottomTray(trayPieces, constraints),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTopBar({
    required int occupiedCount,
    required int totalCells,
    required int satisfiedRules,
    required int totalRules,
    required bool isFull,
    required bool isWon,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const FmDevBackButton(),
            const SizedBox(width: 8),
            // Difficulty pills
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF1E2333),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white24, width: 1.0),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _difficultyPill('Easy', 0),
                  _difficultyPill('Medium', 1),
                  _difficultyPill('Hard', 2),
                ],
              ),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.rule_folder_outlined, color: Colors.white70),
              tooltip: 'Puzzle Rules',
              onPressed: _showRulesSheet,
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
              tooltip: 'Reset Board',
              onPressed: _resetPuzzle,
            ),
          ],
        ),
        const SizedBox(height: 6),
        // Title & status readout
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF171B26).withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isWon
                  ? Colors.amber
                  : (isFull ? Colors.cyanAccent : Colors.white12),
              width: 1.2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _puzzle.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 10),
              Container(width: 1, height: 14, color: Colors.white24),
              const SizedBox(width: 10),
              Text(
                'Spaces: $occupiedCount/$totalCells',
                style: TextStyle(
                  color: isFull ? Colors.greenAccent : Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 10),
              Container(width: 1, height: 14, color: Colors.white24),
              const SizedBox(width: 10),
              Text(
                isFull
                    ? '$satisfiedRules/$totalRules Rules Satisfied'
                    : 'Fill board to verify rules',
                style: TextStyle(
                  color: isFull
                      ? (isWon ? Colors.amberAccent : Colors.orangeAccent)
                      : Colors.white54,
                  fontSize: 12,
                  fontWeight: isFull ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _difficultyPill(String title, int index) {
    final isSelected = _selectedPuzzleIndex == index;
    return GestureDetector(
      onTap: () {
        if (!isSelected) {
          fmHaptic(FmHapticStyle.selectionClick);
          _loadPuzzle(index);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? Colors.amber : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          title,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white70,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildBottomTray(
    List<FlatgramPiece> trayPieces,
    BoxConstraints constraints,
  ) {
    return Container(
      height: 125,
      decoration: BoxDecoration(
        color: const Color(0xFF131722),
        border: const Border(
          top: BorderSide(color: Colors.white12, width: 1.0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                const Icon(Icons.grid_view_rounded, size: 14, color: Colors.white54),
                const SizedBox(width: 6),
                Text(
                  'PIECE TRAY (${trayPieces.length} available)',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
                const Spacer(),
                const Text(
                  'Drag onto board • Tap to turn',
                  style: TextStyle(color: Colors.white38, fontSize: 10),
                ),
              ],
            ),
          ),
          Expanded(
            child: trayPieces.isEmpty
                ? const Center(
                    child: Text(
                      'All pieces placed on board',
                      style: TextStyle(
                        color: Colors.white38,
                        fontStyle: FontStyle.italic,
                        fontSize: 12,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    scrollDirection: Axis.horizontal,
                    itemCount: trayPieces.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 14),
                    itemBuilder: (context, index) {
                      final piece = trayPieces[index];
                      return _buildTrayPieceCard(piece, constraints);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrayPieceCard(FlatgramPiece piece, BoxConstraints constraints) {
    final isSelected = _selectedPieceId == piece.id;

    return GestureDetector(
      onTap: () {
        // Rotate piece in tray
        final nextTurns = (piece.turns + 1) % 4;
        setState(() {
          _pieces[piece.id] = piece.copyWith(turns: nextTurns);
          _selectedPieceId = piece.id;
        });
        fmHaptic(FmHapticStyle.selectionClick);
      },
      onPanStart: (details) {
        _startDraggingFromTray(piece, details.globalPosition, constraints);
      },
      onPanUpdate: (details) {
        if (_isDragging && _dragPiece?.id == piece.id) {
          final RenderBox? box = context.findRenderObject() as RenderBox?;
          final local = box != null
              ? box.globalToLocal(details.globalPosition)
              : details.globalPosition;
          final currentAnchorScreenPos = local - _dragGrabOffsetPx;
          final boardLocal = currentAnchorScreenPos - _boardOffset;
          final candidateAnchor = GridPoint(
            (boardLocal.dx / _cellSize).round(),
            (boardLocal.dy / _cellSize).round(),
          );

          setState(() {
            _dragVisualAnchor = currentAnchorScreenPos;
            _dragAnchor = candidateAnchor;
          });
        }
      },
      onPanEnd: (details) {
        if (_isDragging && _dragPiece?.id == piece.id) {
          final RenderBox? box = context.findRenderObject() as RenderBox?;
          final local = box != null
              ? box.globalToLocal(details.globalPosition)
              : details.globalPosition;
          _dropPiece(local);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF252B3B) : const Color(0xFF1B202D),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? Colors.amber : Colors.white24,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CustomPaint(
              size: const Size(64, 38),
              painter: TrayPiecePainter(
                piece: piece,
                turns: piece.turns,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.sync_rounded, size: 11, color: Colors.white38),
                const SizedBox(width: 2),
                Text(
                  '${piece.turns * 90}°',
                  style: const TextStyle(color: Colors.white38, fontSize: 9.5),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showRulesSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161A26),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.rule_rounded, color: Colors.amber, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    '${_puzzle.title} Rules',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _puzzle.description,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const Divider(color: Colors.white24, height: 24),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _puzzle.constraints.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final c = _puzzle.constraints[i];
                    return Row(
                      children: [
                        if (c.badgeLabel != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: c.badgeColor ?? Colors.amber,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              c.badgeLabel!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            c.description ?? c.type,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

