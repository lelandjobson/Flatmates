import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../gridcraft/blueprint.dart';
import '../gridcraft/celebrate.dart';
import '../gridcraft/craft_plane.dart';
import '../gridcraft/edit.dart';
import '../gridcraft/fold.dart';
import '../gridcraft/folded_model.dart';
import '../gridcraft/level_io.dart';
import '../gridcraft/model_painter.dart';
import '../gridcraft/painter.dart';
import '../gridcraft/criteria.dart';
import '../gridcraft/paper_stack.dart';
import '../gridcraft/placement.dart';
import '../gridcraft/puzzle_advance.dart';
import '../gridcraft/rules.dart';
import '../gridcraft/scrap.dart';
import '../gridcraft/scissor.dart';
import '../gridcraft/scissor_glyph.dart';
import '../gridcraft/tool_animation.dart';
import '../gridcraft/tool_animation_io.dart';
import '../gridcraft/tool_flight.dart';
import '../gridcraft/twin_ls.dart';
import '../papercut/camera.dart';
import '../papercut/craft_v1.dart';
import '../papercut/models.dart';
import '../papercut/paper.dart';
import '../papercut/split.dart';
import '../ui/game/dev_tools_button.dart';
import '../ui/game/grid_dev_panel.dart';
import '../ui/craft_palette.dart';
import '../ui/game/game_tool_carousel.dart';
import '../ui/game/view_crosshair.dart';
import '../ui/fm_dev_back_button.dart';
import '../ui/grid/piece_inventory.dart';
import '../ui/grid/play_library_dialog.dart';
import '../ui/rotation_gizmo.dart';
import '../ui/fm_haptics.dart';
import '../ui/fm_safe_area.dart';
import '../ui/fm_screen.dart';

enum _GridTool { select, scissors, folder, holePunch }

/// Inventory and model paper, saved with each undo step.
class _OffDesk {
  const _OffDesk({
    required this.pieces,
    required this.stowed,
    required this.placements,
  });

  final Map<String, PapercutPiece> pieces;
  final List<String> stowed;
  final List<PiecePlacement> placements;
}

/// Flat crafting on the sheet, or the folded model in 3D.
enum _ViewMode { flat, model }

/// Screen side of a tap, measured from the crosshair. Up is toward the top.
enum _CutSide { up, down, left, right }

/// Taps inside the crosshair disc keep going forward. Anything past it uses
/// the larger axis of the offset, so a click beside the crosshair is left
/// or right rather than another forward cut.
const double _kCrosshairCutRadius = 28;

const Duration _kTurnDuration = Duration(milliseconds: 600);
const Duration _kSplitDuration = Duration(milliseconds: 750);
const Duration _kFoldDuration = Duration(milliseconds: 700);
const Duration _kCreaseDuration = Duration(milliseconds: 300);
const Duration _kFoldHold = Duration(milliseconds: 750);
const double _kFoldHoldSlop = 12;
const double _kFoldBarHalf = 96;
const Duration _kFoldSettleDuration = Duration(milliseconds: 280);
const Duration _kFadeDuration = Duration(milliseconds: 400);
const Duration _kTallyDuration = Duration(seconds: 3);
const Duration _kFocusDuration = Duration(milliseconds: 320);
const Duration _kCelebrateDuration = Celebration.duration;
const Duration _kAdvanceDuration = Duration(milliseconds: 780);

/// The camera dollies in the first half. The ghost folds up across all of it.
const Duration _kModeDuration = Duration(milliseconds: 600);
const Duration _kWrapDuration = Duration(milliseconds: 900);
const Duration _kDoubleTap = Duration(milliseconds: 320);
const double _kDoubleTapSlop = 32;

/// The inventory opens once the camera has rested this long on a face.
const Duration _kSettle = Duration(milliseconds: 250);
const Duration _kPreselectFade = Duration(milliseconds: 180);

/// Target index for the desk, the world sheet the 2D view crafts on. Model
/// faces are 0 and up.
const int _kDesk = -1;

/// Desk paper in 3D, when the desk is not focused.
const Color _kDeskGrey = Color(0xFF9E9E9E);
const double _kDeskOpacity = 0.1;

/// Paper on a model face floats this far off it, in grid units.
const double _kPaperLift = 0.04;

/// Opening 3D view: in front of the model, a little to the left, looking down.
const double _kModelTurn = -1.9;
const double _kModelTilt = 0.55;
const double _kMaxTilt = 85 * math.pi / 180;

/// After a wrap the camera backs out past the model framing, then turns once
/// around it. The lap keeps its tilt in this range so the turn reads.
const Duration _kBackOutDuration = Duration(milliseconds: 450);
const double _kBackOutMargin = 1.25;
const Duration _kLapDuration = Duration(milliseconds: 1700);
const double _kLapTiltMin = 0.3;
const double _kLapTiltMax = 0.9;
const int _kWrapPoints = 100;

/// The rotate icon and ring stay this far inside the view, clear of the top
/// bar and the model bar.
const EdgeInsets _kGimbalInset = EdgeInsets.fromLTRB(16, 170, 16, 120);
const Duration _kScorePopDuration = Duration(milliseconds: 700);

/// Plays one level of a blueprint. Authoring lives in the puzzle editor.
class GridPuzzleView extends StatefulWidget {
  const GridPuzzleView({
    super.key,
    this.store,
    this.initial,
    this.returnToEditor = false,
    this.crafts,
  });

  final LevelStore? store;

  /// Folded-model sources. Null loads every bundled craft.
  final List<CraftV1>? crafts;

  /// Blueprint opened from the puzzle editor. Unsaved edits win over a file.
  final GridBlueprint? initial;

  /// Back returns to the editor instead of the dev menu.
  final bool returnToEditor;

  @override
  State<GridPuzzleView> createState() => _GridPuzzleViewState();
}

class _GridPuzzleViewState extends State<GridPuzzleView>
    with TickerProviderStateMixin {
  final LevelStore _store = LevelStore(bundle: rootBundle);
  late PapercutCamera _camera;
  late AnimationController _flash;
  late AnimationController _failAnim;
  late AnimationController _turnAnim;
  late AnimationController _splitAnim;
  late AnimationController _celebrateAnim;
  late AnimationController _advanceAnim;
  late AnimationController _foldAnim;
  late AnimationController _creaseAnim;
  late AnimationController _foldSettle;
  Timer? _foldHold;
  late AnimationController _fadeAnim;
  late AnimationController _tallyAnim;
  late AnimationController _rollNudge;
  late AnimationController _flightAnim;
  late AnimationController _focusAnim;
  late AnimationController _modeAnim;
  late AnimationController _flyAnim;
  late AnimationController _wrapAnim;

  /// Back-out and lap after a wrap, for [_lapIsland].
  late AnimationController _lapAnim;
  int? _lapIsland;
  bool _lapBackedOut = false;
  double _lapTurn = 0;
  double _lapTilt = _kModelTilt;

  /// Islands that already scored, so undoing and wrapping again adds nothing.
  final Set<int> _scoredIslands = {};
  late AnimationController _scorePop;
  _ViewMode _mode = _ViewMode.flat;
  Map<String, CraftV1> _crafts = const {};
  GridStep? _modelStep;
  FoldedModel? _modelCache;
  List<Decal> _decals = const [];
  CameraPose? _flatPose;

  /// Orbit pose to return to when face focus ends, after the camera flew onto
  /// the face.
  CameraPose? _orbitPose;
  int? _focusFace;

  /// Face under the reticle. Focus holds it on the focused face.
  int? _preselect;

  /// Face index to 0–1 preselect fill, easing toward [_preselect].
  final ValueNotifier<Map<int, double>> _preselectFill = ValueNotifier(
    const {},
  );
  late final Ticker _preselectTicker;
  Duration _preselectElapsed = Duration.zero;

  /// The camera has rested for [_kSettle], so the inventory is offered.
  bool _settled = false;
  Timer? _settleTimer;

  /// Camera at the last move, so a notification without one keeps the rest.
  Vector3? _restEye;
  Vector3? _restTarget;
  double _restHalf = 0;

  /// Inventory piece being dragged, where it would land on the face.
  PiecePlacement? _dropping;
  final ValueNotifier<bool> _dropShown = ValueNotifier(false);
  final GlobalKey _dropKey = GlobalKey();

  /// One finger in focus that missed the paper slides the camera along the
  /// face from this plane point.
  Offset? _planeGrab;
  Vector3? _viewGrab;

  /// Piece being slid and turned on the focused face.
  PiecePlacement? _placing;

  /// Placed pieces in order. Matching ones are wrapped; the rest lie loose.
  final List<PiecePlacement> _placements = [];

  /// Paper off the desk, by id: stowed in the inventory or on the model. The
  /// sheet holds only desk paper, so tools never reach these.
  final Map<String, PapercutPiece> _offDesk = {};

  /// Inventory, in the order pieces were stowed.
  final List<String> _stowed = [];
  final List<_OffDesk> _undoOffDesk = [];

  /// 0 while the desk paper is grey in 3D, 1 with it shown as paper.
  late AnimationController _deskAnim;

  /// Desk paper dragged in desk focus: its id, the plane point grabbed, and
  /// its separation then.
  String? _deskDragId;
  Offset? _deskGrab;
  Offset _deskGrabFrom = Offset.zero;

  /// Desk paper is held over the inventory and would be stowed on release.
  bool _overInventory = false;
  final GlobalKey _inventoryKey = GlobalKey();
  int? _wrapIsland;
  bool _placeDragging = false;

  /// The piece in hand shows its rotation ring while it is this one. Turns
  /// are taken from [_gimbalFrom] while the paper is still at [_gimbalLast].
  String? _gimbalPiece;
  PiecePlacement? _gimbalFrom;
  PiecePlacement? _gimbalLast;
  Offset? _placeGrab;
  Offset _placeGrabOffset = Offset.zero;
  DateTime? _lastTapTime;
  Offset? _lastTapAt;
  final ToolFlight _flight = ToolFlight();
  Offset _focusFrom = Offset.zero;
  Offset _focusTo = Offset.zero;
  bool _armingCut = false;
  Offset? _armedFrom;
  Offset? _armedTo;
  Offset? _modelEnd;
  double? _cutRoll;
  ToolAnimation _scissors = ScissorToolAnimation();
  final FocusNode _keys = FocusNode();
  List<Offset> _splitFrom = const [];
  List<Offset> _splitTo = const [];
  List<CelebrationPlayback> _celebrations = const [];
  Set<int> _liberated = {};
  bool _won = false;
  bool _collectionWon = false;
  bool _advancing = false;
  double _rollFrom = 0;
  double _rollTo = 0;
  GridStep? _turnFromStep;
  PapercutSheet? _turnFromSheet;
  ScissorMarch? _turnFromMarch;
  PapercutSheet? _turnFromBase;
  Offset? _turnOrigin;
  bool _turnClockwise = true;

  List<PuzzleCollection> _collections = const [];
  int _collectionIndex = 0;
  int _puzzleIndex = 0;
  GridStep? _incomingStep;
  PapercutSheet? _incomingSheet;
  Offset _advanceFrom = Offset.zero;
  Offset _advanceTo = Offset.zero;
  double _advanceFromHeight = 0;
  double _advanceToHeight = 0;
  late GridBlueprint _blueprint;
  GridStep _baseline = twinLsBlueprint().steps.first;
  int _stepIndex = 0;
  late PapercutSheet _sheet;
  ScissorMarch? _march;
  PapercutSheet? _marchBase;
  String? _bladePieceId;
  final List<PapercutSheet> _undo = [];
  final List<CutProgress> _undoProgress = [];
  final List<Set<int>> _undoLiberated = [];
  CutProgress _progress = const CutProgress();

  /// Screen sides tapped while a stroke is still traveling. Null is forward.
  final List<_CutSide?> _cutQueue = [];

  _GridTool _tool = _GridTool.scissors;

  /// Camera pose the level opened with. Failure restores it on its own,
  /// apart from resetting the puzzle.
  Offset _startLook = Offset.zero;
  double _startHalfHeight = 150;
  double _startRoll = 0;
  int _folderUses = 0;
  int _punchUses = 0;
  PunchShape _punchShape = PunchShape.circle;
  double _punchSize = 1;
  List<int?> _collisionLeft = const [];
  Set<int> _touching = {};
  int? _foldBend;

  /// Sheet to show once the unfold swing finishes. While it plays, [_sheet]
  /// keeps the fold and [_foldBend] runs backward.
  PapercutSheet? _unfoldTo;

  /// A scored crease is swinging 10% and back. The last joint is temporary.
  bool _creaseTwitch = false;

  /// Hold-to-fold. The preview joint is the last fold until it commits or returns.
  bool _foldingMode = false;
  bool _foldPreviewJoint = false;
  bool _settlingFold = false;
  bool _pointerDown = false;
  double _foldSigned = 0;
  double _settleFrom = 0;
  double _settleTo = 0;
  FolderGuide? _folderGuideDown;
  Offset? _foldAnchor;
  Offset? _foldScreenAxis;
  int? _picked;
  final _stacks = PaperStackPick();
  int? _dragPiece;
  bool _dragNudged = false;
  Offset? _dragSample;
  Offset? _dragFree;
  double? _rulerX;
  bool _rolling = false;
  Offset? _strokeDirection;
  bool _needsFrame = true;
  double _rollStart = 0;
  double _moved = 0;
  Offset? _gestureDown;
  double _gestureScale = 1;

  /// A pinch, trackpad zoom, or second finger. Stays set until every pointer
  /// is up, so the gesture's later scale-end is not a cut or a fold.
  bool _zoomed = false;
  int _canvasPointers = 0;
  bool _devToolsOpen = false;
  bool _showTapDebug = false;

  /// The camera keeps the blade in the reticle and travels with it.
  /// Off, a cut zooms to fit and the camera stays put until that use ends.
  bool _cameraFollowsTool = true;

  /// A cut rolls the sheet so the stroke points up. Off unless DevTools
  /// turns it on; the camera can still follow the blade.
  bool _cameraRotates = false;

  /// True while the camera travels to the end of an opening stroke, so it
  /// meets the blade there instead of chasing the paper edge.
  bool _meeting = false;
  ScrapTallyStyle _tallyStyle = ScrapTallyStyle.shrink;
  int _collectionScore = 0;
  final GlobalKey _scoreKey = GlobalKey();
  Set<String> _fading = const {};
  bool _tallying = false;
  List<Offset> _tallyCells = const [];
  List<CellWindow> _tallyWindows = const [];
  Set<String> _tallyIds = const {};
  int _tallyAwarded = 0;
  Offset? _debugTap;
  String _debugSide = '';
  Size _viewport = Size.zero;

  LevelStore get _levelsStore => widget.store ?? _store;

  GridStep get _step => _blueprint.steps[_stepIndex];

  bool get _locked => _march?.locked ?? false;

  /// Scissors are in a use: placed on the paper, or a stroke is still running.
  bool get _scissorUse =>
      _tool == _GridTool.scissors && (_march != null || _cutting);

  /// Camera stays at the fitted sheet until the scissor use ends.
  bool get _fixedToolCamera => !_cameraFollowsTool && _scissorUse;

  @override
  void initState() {
    super.initState();
    _camera = PapercutCamera()..addListener(_onCamera);
    _blueprint = widget.initial ?? twinLsBlueprint();
    _flash = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    )..repeat(reverse: true);
    _failAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    )..addStatusListener(_onFailStatus);
    _turnAnim = AnimationController(vsync: this, duration: _kTurnDuration)
      ..addListener(_onTurnTick)
      ..addStatusListener(_onTurnStatus);
    _splitAnim = AnimationController(vsync: this, duration: _kSplitDuration)
      ..addListener(_onSplitTick)
      ..addStatusListener(_onSplitStatus);
    _celebrateAnim = AnimationController(
      vsync: this,
      duration: _kCelebrateDuration,
    )..addStatusListener(_onCelebrateStatus);
    _advanceAnim = AnimationController(vsync: this, duration: _kAdvanceDuration)
      ..addListener(_onAdvanceTick)
      ..addStatusListener(_onAdvanceStatus);
    _foldAnim = AnimationController(vsync: this, duration: _kFoldDuration)
      ..addStatusListener(_onFoldStatus);
    _creaseAnim = AnimationController(vsync: this, duration: _kCreaseDuration)
      ..addStatusListener(_onCreaseStatus);
    _foldSettle = AnimationController(
      vsync: this,
      duration: _kFoldSettleDuration,
    )..addStatusListener(_onFoldSettle);
    _fadeAnim = AnimationController(vsync: this, duration: _kFadeDuration)
      ..addStatusListener(_onFadeStatus);
    _tallyAnim = AnimationController(vsync: this, duration: _kTallyDuration)
      ..addListener(_onTallyTick)
      ..addStatusListener(_onTallyStatus);
    _rollNudge = AnimationController(vsync: this, duration: _kTurnDuration)
      ..addListener(_onRollNudge);
    _flightAnim = AnimationController(vsync: this, duration: kArriveDuration)
      ..addListener(_followCut)
      ..addStatusListener(_onFlightStatus);
    _focusAnim = AnimationController(vsync: this, duration: _kFocusDuration)
      ..addListener(_onFocusTick)
      ..addStatusListener(_onFocusStatus);
    _modeAnim = AnimationController(vsync: this, duration: _kModeDuration)
      ..addListener(_onModeTick);
    _flyAnim = AnimationController(
      vsync: this,
      duration: PapercutCamera.flyDuration,
    )..addListener(_onFlyTick);
    _wrapAnim = AnimationController(vsync: this, duration: _kWrapDuration)
      ..addStatusListener(_onWrapStatus);
    _lapAnim =
        AnimationController(
            vsync: this,
            duration: _kBackOutDuration + _kLapDuration,
          )
          ..addListener(_onLapTick)
          ..addStatusListener(_onLapStatus);
    _scorePop = AnimationController(vsync: this, duration: _kScorePopDuration);
    _preselectTicker = createTicker(_onPreselectTick);
    _deskAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _loadStep(0, _blueprint);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _keys.requestFocus();
      _syncFlight();
    });
    _refreshCollections();
    _loadToolAnimations();
    _loadCrafts();
  }

  Future<void> _loadCrafts() async {
    final crafts = widget.crafts ?? await CraftV1.loadAll();
    if (!mounted) return;
    setState(() {
      _crafts = {for (final craft in crafts) craft.craft: craft};
      _modelStep = null;
    });
  }

  Future<void> _loadToolAnimations() async {
    final tools = await ToolAnimationStore().load();
    if (!mounted) return;
    ToolAnimation? scissors;
    for (final tool in tools) {
      if (tool.id == 'scissors') scissors = tool;
    }
    final chosen = scissors;
    if (chosen == null) return;
    setState(() => _scissors = chosen);
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    _preselectTicker.dispose();
    _preselectFill.dispose();
    _dropShown.dispose();
    _deskAnim.dispose();
    _modeAnim.dispose();
    _flyAnim.dispose();
    _wrapAnim.dispose();
    _lapAnim.dispose();
    _scorePop.dispose();
    _focusAnim.dispose();
    _flightAnim.dispose();
    _rollNudge.dispose();
    _keys.dispose();
    _splitAnim.dispose();
    _advanceAnim.dispose();
    _celebrateAnim.dispose();
    _foldAnim.dispose();
    _foldHold?.cancel();
    _foldSettle.dispose();
    _creaseAnim.dispose();
    _fadeAnim.dispose();
    _tallyAnim.dispose();
    _turnAnim.dispose();
    _failAnim.dispose();
    _flash.dispose();
    _camera.removeListener(_onCamera);
    _camera.dispose();
    super.dispose();
  }

  void _onCamera() {
    _syncFlight();
    if (_inModel) _cameraMoved();
    if (mounted) setState(() {});
  }

  PuzzleCollection? get _collection {
    if (_collections.isEmpty) return null;
    final index = _collectionIndex.clamp(0, _collections.length - 1);
    return _collections[index];
  }

  String get _collectionName => _collection?.name ?? 'Collection';

  GridBlueprint? get _nextPuzzle {
    final collection = _collection;
    if (collection == null) return null;
    final next = _puzzleIndex + 1;
    if (next < 0 || next >= collection.puzzles.length) return null;
    return collection.puzzles[next];
  }

  Future<void> _refreshCollections() async {
    final saved = await _levelsStore.loadCollections();
    if (!mounted) return;
    final collections = _playCollections(saved);
    final found = _findPuzzle(collections, _blueprint.id);
    setState(() {
      _collections = collections;
      if (found != null) {
        _collectionIndex = found.$1;
        _puzzleIndex = found.$2;
        _keepLivePuzzle(found.$1, found.$2);
      } else if (widget.initial != null &&
          widget.initial!.id == _blueprint.id) {
        _collections = [
          PuzzleCollection(
            id: 'unsaved',
            name: 'Unsaved',
            puzzles: [_blueprint],
          ),
          ...collections,
        ];
        _collectionIndex = 0;
        _puzzleIndex = 0;
      } else if (collections.isNotEmpty &&
          collections.first.puzzles.isNotEmpty) {
        _collectionIndex = 0;
        _puzzleIndex = 0;
        if (_blueprint.id != collections.first.puzzles.first.id) {
          _loadStep(0, collections.first.puzzles.first);
        }
      }
    });
  }

  /// Hidden collections and puzzles stay out of play. Twin Ls fills in when
  /// nothing else is left to play.
  List<PuzzleCollection> _playCollections(List<PuzzleCollection> stored) {
    final saved = [for (final collection in stored) ?collection.playable];
    if (saved.isNotEmpty) return saved;
    return [
      PuzzleCollection(
        id: 'twin-ls',
        name: 'Twin Ls',
        puzzles: [twinLsBlueprint()],
      ),
      ...saved,
    ];
  }

  (int, int)? _findPuzzle(List<PuzzleCollection> collections, String id) {
    for (var c = 0; c < collections.length; c++) {
      final puzzles = collections[c].puzzles;
      for (var p = 0; p < puzzles.length; p++) {
        if (puzzles[p].id == id) return (c, p);
      }
    }
    return null;
  }

  void _keepLivePuzzle(int collectionIndex, int puzzleIndex) {
    final collection = _collections[collectionIndex];
    final puzzles = [...collection.puzzles];
    puzzles[puzzleIndex] = _blueprint;
    _collections[collectionIndex] = PuzzleCollection(
      id: collection.id,
      name: collection.name,
      puzzles: puzzles,
    );
  }

  Future<void> _openLibrary() async {
    if (_collections.isEmpty) return;
    final pick = await showDialog<PlayLibraryPick>(
      context: context,
      builder: (context) => PlayLibraryDialog(
        collections: _collections,
        collectionIndex: _collectionIndex,
        puzzleIndex: _puzzleIndex,
      ),
    );
    if (pick == null || !mounted) return;
    final collection = _collections[pick.collectionIndex];
    final puzzle = collection.puzzles[pick.puzzleIndex];
    if (puzzle.id == _blueprint.id &&
        pick.collectionIndex == _collectionIndex) {
      return;
    }
    setState(() {
      if (pick.collectionIndex != _collectionIndex) _collectionScore = 0;
      _collectionIndex = pick.collectionIndex;
      _puzzleIndex = pick.puzzleIndex;
      _loadStep(0, puzzle);
    });
  }

  void _loadStep(int index, GridBlueprint blueprint, {bool frame = true}) {
    if (_turnAnim.isAnimating) _turnAnim.stop();
    if (_splitAnim.isAnimating) _splitAnim.stop();
    _stopCelebrate();
    _stopFold();
    _stopFade();
    _stopTally();
    if (_flightAnim.isAnimating) _flightAnim.stop();
    _endMeeting();
    if (_focusAnim.isAnimating) _focusAnim.stop();
    _armingCut = false;
    _armedFrom = null;
    _armedTo = null;
    _modelEnd = null;
    _cutRoll = null;
    _flight.reset();
    _strokeDirection = null;
    _turnFromStep = null;
    _won = false;
    _collectionWon = false;
    _advancing = false;
    _incomingStep = null;
    _incomingSheet = null;
    if (_advanceAnim.isAnimating) _advanceAnim.stop();
    _leaveModelNow();
    _liberated = {};
    _blueprint = blueprint;
    _stepIndex = index.clamp(0, blueprint.steps.length - 1);
    _baseline = _step;
    _sheet = _freshSheet(_step);
    _march = null;
    _marchBase = null;
    _bladePieceId = null;
    _undo.clear();
    _undoProgress.clear();
    _undoLiberated.clear();
    _progress = const CutProgress();
    _cutQueue.clear();
    _folderUses = 0;
    _punchUses = 0;
    _collisionLeft = [
      for (var i = 0; i < _step.polygons.length; i++) _step.collisionOf(i),
    ];
    _touching = {};
    if (_step.tools != null &&
        _tool == _GridTool.scissors &&
        !_step.tools!.allows(CraftTool.scissors)) {
      _tool = _GridTool.select;
    }
    _picked = null;
    _stacks.clear();
    _dragPiece = null;
    _rulerX = _snap(_step.paper.center.dx, _step.gridSpacing);
    if (frame) {
      _needsFrame = true;
      _frame();
      _rememberStart();
    } else {
      _needsFrame = false;
    }
    _syncFlight();
  }

  /// Records the camera pose once the level is actually on screen.
  void _rememberStart() {
    if (_viewport.width < 2 || _viewport.height < 2) return;
    _startLook = _camera.lookAt;
    _startHalfHeight = _camera.framedHalfHeightMm;
    _startRoll = _camera.roll;
  }

  /// Puts the camera back where the level opened, without touching the puzzle.
  void _resetStartingPosition() {
    if (_rollNudge.isAnimating) _rollNudge.stop();
    _camera.setRoll(_startRoll);
    _camera.moveLook(lookAt: _startLook, halfHeight: _startHalfHeight);
  }

  PapercutSheet _freshSheet(GridStep step) {
    final paper = step.paper;
    return PapercutSheet(
      pieces: [
        PapercutPiece(
          id: 'paper',
          color: kPapercutYellow,
          vertices: [
            paper.topLeft,
            paper.topRight,
            paper.bottomRight,
            paper.bottomLeft,
          ],
        ),
      ],
    );
  }

  void _frame() {
    final paper = _step.paper;
    _camera.frameSheet(
      _viewport,
      sheetMm: math.max(paper.width, paper.height),
      center: paper.center,
    );
  }

  /// Fits the sheet and holds the camera there for the rest of the tool use.
  void _lockToolCamera() {
    if (_cameraFollowsTool) return;
    if (_rollNudge.isAnimating) _rollNudge.stop();
    _frame();
    if (mounted) setState(() {});
  }

  void _setCameraFollowsTool(bool value) {
    if (_cameraFollowsTool == value) return;
    setState(() => _cameraFollowsTool = value);
    if (value) {
      _pinScissor();
      return;
    }
    _endMeeting();
    if (_armingCut) {
      _armingCut = false;
      if (_focusAnim.isAnimating) _focusAnim.stop();
    }
    if (_rollNudge.isAnimating) _rollNudge.stop();
    if (_scissorUse) _lockToolCamera();
  }

  void _setCameraRotates(bool value) {
    if (_cameraRotates == value) return;
    setState(() => _cameraRotates = value);
    if (value) return;
    _cutRoll = null;
    if (_rollNudge.isAnimating) _rollNudge.stop();
  }

  double _snap(double value, double spacing) =>
      (value / spacing).roundToDouble() * spacing;

  Offset _snapOffset(Offset value) {
    final spacing = _step.gridSpacing;
    if (spacing <= 1e-9) return value;
    return Offset(_snap(value.dx, spacing), _snap(value.dy, spacing));
  }

  /// Drops a scissor march, a cut in flight, and anything queued behind it.
  void _abandonOtherTools() {
    _endMeeting();
    if (_focusAnim.isAnimating) _focusAnim.stop();
    if (_flightAnim.isAnimating) _flightAnim.stop();
    if (_rollNudge.isAnimating && _cutRoll != null) _rollNudge.stop();
    _armingCut = false;
    _armedFrom = null;
    _armedTo = null;
    _modelEnd = null;
    _cutRoll = null;
    _strokeDirection = null;
    _cutQueue.clear();
    _march = null;
    _marchBase = null;
    _bladePieceId = null;
    _flight.reset();
  }

  bool get _entryGemsRemain => entryGemsRemain(_step.rules, _progress);

  /// Nearest number gem the blade may still enter through.
  Offset? _openGemNear(Offset world) {
    final rules = _step.rules;
    final reach = _step.gridSpacing * 1.5;
    Offset? best;
    var bestDistance = reach;
    void consider(Offset point) {
      final distance = (point - world).distance;
      if (distance >= bestDistance) return;
      bestDistance = distance;
      best = point;
    }

    for (final mark in rules.numbers) {
      if (mark.number < _progress.nextNumber) continue;
      consider(mark.point);
    }
    return best;
  }

  bool get _cutting => _flight.phase == ToolFlightPhase.cut || _armingCut;

  /// True after the first stroke, when side taps choose the next cut.
  bool get _directing {
    final march = _march;
    return march != null && march.path.length > 1;
  }

  void _onScissorTap(Offset world) {
    if (_cutting || _failing || _won) return;
    if (_march == null) {
      if (_entryGemsRemain) {
        final gem = _openGemNear(world);
        if (gem == null) return;
        final edge = _nearestEdge(gem);
        setState(() {
          _marchBase = _sheet;
          _march = placeAtEntry(gem, _step.paper);
          _bladePieceId = edge == null
              ? (_sheet.pieces.isEmpty ? null : _sheet.pieces.first.id)
              : _sheet.pieces[edge.index].id;
        });
      } else {
        final edge = _nearestEdge(world);
        if (edge == null) return;
        final placed = _placeOn(edge);
        if (placed == null) return;
        setState(() {
          _marchBase = _sheet;
          _march = placed;
          _bladePieceId = _sheet.pieces[edge.index].id;
        });
      }
    }
    final ghost = _scissorGhost(world);
    if (ghost == null) {
      if (_cameraFollowsTool) {
        _pinScissor();
      } else if (_march != null) {
        _lockToolCamera();
      }
      _syncFlight();
      return;
    }
    _startCut(world);
    if (_march != null && !_cameraFollowsTool) _lockToolCamera();
  }

  void _startCut([Offset? aim]) {
    final ghost = _scissorGhost(aim ?? _aimWorld());
    if (ghost == null) return;
    _beginStroke(ghost.$1, ghost.$2);
  }

  bool _beginStroke(Offset modelFrom, Offset modelTo) {
    if (!_liveRules.allows(modelFrom, modelTo, _progress, paper: _step.paper)) {
      return false;
    }
    final from = _shown(modelFrom);
    final to = _shown(modelTo);
    final delta = to - from;
    if (delta.distance < 1e-6) return false;
    unawaited(fmHaptic(FmHapticStyle.lightImpact));
    _strokeDirection = delta / delta.distance;
    _modelEnd = modelTo;
    _armedFrom = from;
    _armedTo = to;
    if (!_cameraFollowsTool) {
      _armingCut = false;
      _cutRoll = null;
      _flight.beginCut(
        from: from,
        to: to,
        direction: _strokeDirection!,
        t: _flightAnim.value,
        present: (_march?.path.length ?? 1) <= 1,
      );
      _playFlight(kCutDuration);
      return true;
    }
    _cutRoll = _cameraRotates
        ? PapercutCamera.rollForScreenUp(
            modelTo - modelFrom,
            near: _rollNudge.isAnimating ? _rollTo : _camera.roll,
          )
        : null;
    final opening = (_march?.path.length ?? 1) <= 1;
    if (opening) {
      _flight.beginCut(
        from: from,
        to: to,
        direction: _strokeDirection!,
        t: _flightAnim.value,
        present: true,
      );
      _meetCut(to);
      _playFlight(kCutDuration);
      final target = _cutRoll;
      _cutRoll = null;
      if (target != null && (target - _camera.roll).abs() > 1e-3) {
        _animateRollTo(target);
      }
      return true;
    }
    _armingCut = true;
    _animateFocus(from);
    return true;
  }

  /// Sends [lookAt] to the end of the opening stroke over the same time the
  /// blade travels, so the reticle and the scissors arrive together.
  void _meetCut(Offset end) {
    _meeting = true;
    _focusFrom = _camera.lookAt;
    _focusTo = end;
  }

  void _startMeeting() {
    if (!_meeting || _focusAnim.isAnimating) return;
    if ((_focusFrom - _focusTo).distance < 1e-3) return;
    _focusAnim.duration = kCutDuration;
    _focusAnim.forward(from: 0);
  }

  void _endMeeting() {
    if (!_meeting) return;
    _meeting = false;
    if (_focusAnim.isAnimating) _focusAnim.stop();
    _focusAnim.duration = _kFocusDuration;
  }

  /// Eases [lookAt] onto [point]. A point already under the crosshair finishes
  /// immediately. The cut itself starts when this arrival completes.
  void _animateFocus(Offset point) {
    if ((_camera.lookAt - point).distance < 1e-3) {
      if (_focusAnim.isAnimating) _focusAnim.stop();
      _camera.focusOn(point);
      _finishFocus();
      return;
    }
    _focusFrom = _camera.lookAt;
    _focusTo = point;
    _focusAnim.forward(from: 0);
  }

  void _onFocusTick() {
    if (_meeting) {
      final t = Curves.easeInOut.transform(_focusAnim.value);
      _camera.focusOn(Offset.lerp(_focusFrom, _focusTo, t)!);
      return;
    }
    if (!_armingCut || !_cameraFollowsTool) return;
    final t = Curves.easeInOutCubic.transform(_focusAnim.value);
    _camera.focusOn(Offset.lerp(_focusFrom, _focusTo, t)!);
  }

  void _onFocusStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (_meeting) {
      _camera.focusOn(_focusTo);
      return;
    }
    _finishFocus();
  }

  void _finishFocus() {
    if (!_armingCut) return;
    final from = _armedFrom;
    final to = _armedTo;
    final direction = _strokeDirection;
    _armingCut = false;
    if (from == null || to == null || direction == null) return;
    final target = _cutRoll;
    _cutRoll = null;
    final turning = target != null && (target - _camera.roll).abs() > 1e-3;
    _flight.beginCut(
      from: from,
      to: to,
      direction: direction,
      t: _flightAnim.value,
      present: (_march?.path.length ?? 1) <= 1,
    );
    _playFlight(kCutDuration);
    if (turning) _animateRollTo(target);
  }

  Offset _screenUp() =>
      rotateGridPointBy(const Offset(0, 1), Offset.zero, -_camera.roll);

  /// Cut heading fixed to the paper. Camera roll does not change it.
  ///
  /// With no march yet, a point on a piece faces into that piece. Near
  /// blueprint linework the heading follows that edge, so a diagonal stroke
  /// is not met on a slant and a gem does not aim at the sheet center.
  Offset _paperHeading(Offset from, {PapercutPiece? piece, Offset? aim}) {
    final march = _march?.direction;
    if (march != null && march.distance > 1e-6) return march;
    if (aim != null) {
      final along = headingAlongLinework(aim: aim, from: from, step: _step);
      if (along != null) return along;
    }
    final owner = piece ?? _bladePiece();
    return openingHeading(
      from,
      _step.paper,
      ring: owner?.vertices,
      holes: owner?.holes ?? const [],
    );
  }

  Offset? _lightOrigin() {
    final pose = _flight.pose(_flightAnim.value);
    if (pose.visible > 0.2) return pose.tip;
    if (!_cameraFollowsTool) {
      final tracked = _trackedToolWorld();
      if (tracked != null) return tracked;
    }
    return _aimWorld();
  }

  /// Blade position the fixed camera measures taps from.
  ///
  /// A seated blade is the march point, which begins on the paper edge.
  /// During a stroke it is the moving tip.
  Offset? _trackedToolWorld() {
    if (_tool != _GridTool.scissors) return null;
    if (_flight.phase == ToolFlightPhase.cut) {
      return _flight.pose(_flightAnim.value).tip;
    }
    final march = _march;
    if (march == null) return null;
    return _shown(march.position);
  }

  Offset? _trackedToolScreen() {
    final world = _trackedToolWorld();
    if (world == null) return null;
    return _project(world);
  }

  Offset _lightDirection() {
    final pose = _flight.pose(_flightAnim.value);
    if (pose.visible > 0.2 && pose.direction.distance > 1e-6) {
      return pose.direction;
    }
    final march = _march?.direction;
    if (march != null && march.distance > 1e-6) return march;
    return _screenUp();
  }

  PapercutPiece? _bladePiece() {
    final id = _bladePieceId;
    if (id == null) return null;
    for (final piece in _sheet.pieces) {
      if (piece.id == id) return piece;
    }
    return null;
  }

  Offset _shown(Offset model) {
    final blade = _bladePiece();
    if (blade != null) return model + blade.separation;
    for (final piece in _sheet.pieces) {
      if (ownsPoint(piece.vertices, model)) return model + piece.separation;
    }
    return model;
  }

  void _pinScissor() {
    if (!_cameraFollowsTool) return;
    final march = _march;
    if (march == null || _viewport.width < 2) return;
    _camera.focusOn(_shown(march.position));
  }

  /// Keeps the crosshair on the blade while a stroke is in progress.
  void _followCut() {
    if (!_cameraFollowsTool || _meeting) return;
    if (_flight.phase != ToolFlightPhase.cut || _viewport.width < 2) return;
    _camera.focusOn(_flight.pose(_flightAnim.value).tip);
  }

  PieceEdgeTarget? _nearestEdge(Offset aim) => closestPieceEdge(
    aim: aim,
    pieces: _sheet.pieces,
    spacing: _step.gridSpacing,
  );

  /// Outlines of the piece being cut, plus the blueprint. Sibling pieces stay
  /// out of the ray: in model space they still cover the area that was cut out.
  List<List<Offset>> _bladeOutlines(PapercutPiece? piece) {
    if (piece == null) return cutOutlines(_step, _sheet);
    return [
      for (var i = 0; i < _step.polygons.length; i++)
        if (_step.isRingClosed(i)) _step.polygons[i],
      piece.vertices,
      ...piece.holes,
    ];
  }

  ScissorMarch? _placeOn(PieceEdgeTarget edge) {
    final piece = _sheet.pieces[edge.index];
    final onPiece = placeOnRing(edge.model, piece.vertices);
    if (onPiece != null) return onPiece;
    for (final hole in piece.holes) {
      final onHole = placeOnRing(edge.model, hole);
      if (onHole != null) return onHole;
    }
    return placeScissor(edge.model, _step.paper);
  }

  /// Maps a point on the drawn paper back to grid space.
  Offset _toModel(Offset aim) {
    for (final piece in _sheet.pieces) {
      if (piece.separation == Offset.zero) continue;
      final shown = [
        for (final vertex in piece.vertices) vertex + piece.separation,
      ];
      if (ownsPoint(shown, aim)) return aim - piece.separation;
    }
    return aim;
  }

  GridRules get _liveRules {
    final cap = _step.scissorLengthBudget;
    if (cap == _step.rules.maxLength) return _step.rules;
    if (cap == null) return _step.rules.copyWith(clearLength: true);
    return _step.rules.copyWith(maxLength: cap);
  }

  bool _skipPenciled(Offset a, Offset b) {
    return penciledRidesPennedNeighbor(
      _step.polygons,
      _step.edgeStyles,
      a,
      b,
      closed: _step.ringClosed,
    );
  }

  bool _canSpend(CraftTool tool, num used) {
    final filter = _step.tools;
    if (filter == null) return true;
    if (!filter.allows(tool)) return false;
    final cap = filter.budget(tool);
    if (cap == null) return true;
    return used + 1 <= cap + 1e-6;
  }

  bool _failed = false;
  bool _failing = false;
  FailureCue? _failureCue;

  void _failLevel(FailureCue cue) {
    if (_failing) return;
    _failing = true;
    _failed = true;
    setState(() => _failureCue = cue);
    _failAnim.forward(from: 0);
  }

  void _onFailStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _commitFailure();
  }

  void _commitFailure() {
    final origin = _baseline;
    final steps = [..._blueprint.steps];
    steps[_stepIndex] = origin;
    _turnAnim.stop();
    _splitAnim.stop();
    _stopCelebrate();
    _stopFold();
    _stopFade();
    _stopTally();
    if (_flightAnim.isAnimating) _flightAnim.stop();
    _endMeeting();
    if (_focusAnim.isAnimating) _focusAnim.stop();
    _flight.reset();
    _resetPuzzle(origin, steps);
    _resetStartingPosition();
  }

  /// Restores the sheet, cuts, folds, collectibles, and tool counts.
  /// The camera stays where it is.
  void _resetPuzzle(GridStep origin, List<GridStep> steps) {
    setState(() {
      _blueprint = _blueprint.copyWith(steps: steps);
      _sheet = _freshSheet(origin);
      _clearOffDesk();
      _march = null;
      _marchBase = null;
      _bladePieceId = null;
      _undo.clear();
      _undoProgress.clear();
      _undoLiberated.clear();
      _progress = const CutProgress();
      _cutQueue.clear();
      _folderUses = 0;
      _punchUses = 0;
      _collisionLeft = [
        for (var i = 0; i < origin.polygons.length; i++) origin.collisionOf(i),
      ];
      _touching = {};
      _strokeDirection = null;
      _modelEnd = null;
      _picked = null;
      _stacks.clear();
      _dragPiece = null;
      _failureCue = null;
      _failing = false;
      _failed = false;
      _won = false;
      _liberated = {};
    });
    _armingCut = false;
    _syncFlight();
  }

  void _noteTouch(Offset a, Offset b) {
    final now = piecesTouched(
      _step.polygons,
      a,
      b,
      closed: _step.ringClosed,
    ).toSet();
    final released = _touching.difference(now);
    _touching = now;
    for (final index in released) {
      if (_spendTouch(index)) return;
    }
  }

  void _releaseTouches() {
    final released = Set<int>.of(_touching);
    _touching = {};
    for (final index in released) {
      if (_spendTouch(index)) return;
    }
  }

  bool _spendTouch(int index) {
    if (index < 0 || index >= _collisionLeft.length) return false;
    final left = _collisionLeft[index];
    if (left == null) return false;
    final next = left - 1;
    _collisionLeft[index] = next;
    if (next <= 0 && !blueprintPieceCutOut(_step.polygons[index], _sheet)) {
      _failLevel(FailureCue(FailureKind.piece, index));
      return true;
    }
    return false;
  }

  /// Cutting a hits piece free while its count is still positive fails the level.
  bool _failIfRemovedEarly() {
    if (_failed) return true;
    for (var i = 0; i < _step.polygons.length; i++) {
      if (!_step.isRingClosed(i)) continue;
      final left = i < _collisionLeft.length ? _collisionLeft[i] : null;
      if (!paperRemovedEarly(
        left,
        cutOut: blueprintPieceCutOut(_step.polygons[i], _sheet),
      )) {
        continue;
      }
      _failLevel(FailureCue(FailureKind.piece, i));
      return true;
    }
    return false;
  }

  PapercutSheet _withMirrors(PapercutSheet sheet, List<Offset> path) {
    final perm = _step.permutation;
    if (!perm.mirrorX && !perm.mirrorY) return sheet;
    var current = sheet;
    for (final image in mirroredPolylines(
      path,
      _step.paper.center,
      mirrorX: perm.mirrorX,
      mirrorY: perm.mirrorY,
    )) {
      final next = cutThroughFolds(
        current,
        image,
        thickCut: _step.attachment.thickCut,
        blueprintPieces: _step.closedPolygons,
      );
      if (next != null) current = next;
    }
    return current;
  }

  FailureCue? _mirrorCause(Offset from, Offset to) {
    final perm = _step.permutation;
    if (!perm.mirrorX && !perm.mirrorY) return null;
    for (final image in mirroredPolylines(
      [from, to],
      _step.paper.center,
      mirrorX: perm.mirrorX,
      mirrorY: perm.mirrorY,
    )) {
      final ruling = _liveRules.consider(
        image.first,
        image.last,
        _progress,
        paper: _step.paper,
      );
      if (ruling.failed) return ruling.cause;
      final pierced = piercedBlueprint(_step, image.first, image.last);
      if (pierced != null) return FailureCue(FailureKind.piece, pierced);
    }
    return null;
  }

  bool _mirrorsBlocked(Offset from, Offset to) {
    final perm = _step.permutation;
    if (!perm.mirrorX && !perm.mirrorY) return false;
    for (final image in mirroredPolylines(
      [from, to],
      _step.paper.center,
      mirrorX: perm.mirrorX,
      mirrorY: perm.mirrorY,
    )) {
      final ruling = _liveRules.consider(
        image.first,
        image.last,
        _progress,
        paper: _step.paper,
      );
      if (!ruling.allowed && !ruling.failed) return true;
    }
    return false;
  }

  /// True when the cut split a piece off. Null when the cut did not apply.
  bool? _commitMarch() {
    if (_failing || _won) return null;
    final march = _march;
    final base = _marchBase;
    if (march == null || base == null) return null;
    _failed = false;
    final direction = _strokeDirection ?? _paperHeading(march.position);
    final end = march.previewEnd(
      _step,
      base,
      direction: direction,
      closed: _bladeOutlines(_bladePiece()),
      skipCollinear: _skipPenciled,
    );
    if (end == null ||
        cutRidesBoundary(march.position, end, _paperEdges(_bladePiece()))) {
      return null;
    }
    final ruling = _liveRules.consider(
      march.position,
      end,
      _progress,
      paper: _step.paper,
    );
    if (!ruling.allowed) return null;
    if (ruling.failed) {
      _failLevel(ruling.cause ?? const FailureCue(FailureKind.color, 0));
      return null;
    }
    final pierced = piercedBlueprint(_step, march.position, end);
    if (pierced != null) {
      _failLevel(FailureCue(FailureKind.piece, pierced));
      return null;
    }
    final mirror = _mirrorCause(march.position, end);
    if (mirror != null) {
      _failLevel(mirror);
      return null;
    }
    if (_mirrorsBlocked(march.position, end)) return null;
    final commit = commitScissor(
      march: march,
      step: _step,
      base: base,
      direction: direction,
      closed: _bladeOutlines(_bladePiece()),
    );
    _strokeDirection = null;
    _modelEnd = null;
    _cutRoll = null;
    if (commit == null) return null;
    final settled = _dropCelebrated(
      _withMirrors(commit.sheet, [...march.path, end]),
    );
    _stopCelebrate();
    _pushUndo();
    _progress = ruling.progress;
    final split = commit.march == null;
    final fresh = split
        ? classifyFreshPieces(
            before: base,
            after: settled,
            closedRings: _step.closedPolygons,
          )
        : null;
    if (fresh != null && _step.discardFailure && fresh.discardsBlueprint) {
      final index = settled.pieces.indexWhere(
        (piece) => piece.id == fresh.smallest?.id,
      );
      setState(() {
        _sheet = settled;
        _march = null;
        _marchBase = null;
        _bladePieceId = null;
      });
      _failLevel(FailureCue(FailureKind.paper, index < 0 ? 0 : index));
      return null;
    }
    final freed = split ? _newlyFreed(base, settled) : const <PapercutPiece>[];
    final winning = _wouldWin(settled);
    // Pieces step apart unless the discard failure is on. Then the carrier
    // stays where it was cut and scrap fades instead of stepping away.
    final spread = split && !_step.discardFailure
        ? layoutAfterSplit(
            base,
            settled,
            _step.gridSpacing,
            finished: {for (final piece in freed) piece.id},
            winning: winning,
          )
        : settled;
    setState(() {
      _sheet = split ? settled : spread;
      _march = commit.march;
      if (split) {
        _marchBase = null;
        _bladePieceId = null;
      }
    });
    _noteTouch(march.position, end);
    if (_failed || _failIfRemovedEarly()) return null;
    if (!split) {
      _pinScissor();
      _playCutCelebration();
      return false;
    }
    _releaseTouches();
    if (_failed || _failIfRemovedEarly()) return null;
    _splitFrom = [for (final piece in settled.pieces) piece.separation];
    _splitTo = [for (final piece in spread.pieces) piece.separation];
    final separates =
        _splitFrom.length == _splitTo.length &&
        [
          for (var i = 0; i < _splitFrom.length; i++)
            _splitFrom[i] != _splitTo[i],
        ].any((moved) => moved);
    _playCutCelebration();
    if (!winning &&
        fresh != null &&
        _step.discardFailure &&
        fresh.scraps.isNotEmpty) {
      _startFade({for (final piece in fresh.scraps) piece.id});
    }
    if (separates) {
      _splitAnim.forward(from: 0);
    } else {
      _splitAnim.stop();
    }
    return true;
  }

  PapercutSheet _dropCelebrated(PapercutSheet sheet) {
    if (_celebrations.isEmpty) return sheet;
    final ids = {
      for (final play in _celebrations)
        if (play.burst) play.pieceId,
    };
    if (ids.isEmpty) return sheet;
    return sheet.copyWith(
      pieces: [
        for (final piece in sheet.pieces)
          if (!ids.contains(piece.id)) piece,
      ],
    );
  }

  List<PapercutPiece> _newlyFreed(PapercutSheet before, PapercutSheet after) {
    final found = <PapercutPiece>[];
    final seen = <String>{};
    for (var i = 0; i < _step.polygons.length; i++) {
      if (!_step.isRingClosed(i)) continue;
      final now = paperMatchingRing(_step.polygons[i], after);
      if (now == null || !seen.add(now.id)) continue;
      final then = paperMatchingRing(_step.polygons[i], before);
      if (then != null && then.id == now.id) continue;
      found.add(now);
    }
    return found;
  }

  bool _gemsSatisfied() {
    final rules = _step.rules;
    if (rules.colors.isEmpty && rules.numbers.isEmpty) return true;
    return collectiblesCleared(rules, _progress);
  }

  bool _wouldWin(PapercutSheet sheet) {
    if (_won || _failed) return false;
    final liberated = {..._liberated, ...liberatedPieceIndexes(_step, sheet)};
    return piecesLiberated(_step, liberated) && _gemsSatisfied();
  }

  double get _celebrateSeconds {
    final span = _celebrateAnim.duration ?? Celebration.duration;
    return _celebrateAnim.value * span.inMicroseconds / 1000000;
  }

  /// Records freed blueprint pieces. A won level counts the leftover paper
  /// into the collection score.
  void _playCutCelebration() {
    if (_won || _failed) return;
    _liberated.addAll(liberatedPieceIndexes(_step, _sheet));
    if (!piecesLiberated(_step, _liberated) || !_gemsSatisfied()) return;
    setState(() => _won = true);
    _beginTally();
    if (!_tallying) _presentNext();
  }

  void _startFade(Set<String> ids) {
    if (ids.isEmpty) return;
    _fading = ids;
    _fadeAnim.forward(from: 0);
  }

  void _stopFade() {
    if (_fadeAnim.isAnimating) _fadeAnim.stop();
    _fading = const {};
  }

  void _onFadeStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || _fading.isEmpty) return;
    if (!mounted) return;
    final gone = _fading;
    setState(() {
      _fading = const {};
      _sheet = _sheet.copyWith(
        pieces: [
          for (final piece in _sheet.pieces)
            if (!gone.contains(piece.id)) piece,
        ],
      );
    });
  }

  /// Frames the authored sheet and removes leftover paper cell by cell
  /// over 3 seconds.
  void _beginTally() {
    final finished = _liberatedPieceIds();
    final cells = leftoverCells(
      pieces: _sheet.pieces,
      freedIds: finished,
      spacing: _step.gridSpacing,
    );
    if (cells.isEmpty) return;
    final paper = _step.paper;
    final span = math.max(paper.width, paper.height);
    _camera.moveLook(
      lookAt: paper.center,
      halfHeight: _camera.halfHeightForSheet(
        _viewport,
        sheetMm: math.max(span, _step.gridSpacing),
      ),
    );
    _tallyCells = cells;
    _tallyWindows = tallySchedule(cells.length);
    _tallyAwarded = 0;
    _tallyIds = {
      for (final piece in _sheet.pieces)
        if (!finished.contains(piece.id)) piece.id,
    };
    setState(() => _tallying = true);
    _tallyAnim.forward(from: 0);
  }

  void _stopTally() {
    if (_tallyAnim.isAnimating) _tallyAnim.stop();
    _tallying = false;
    _tallyCells = const [];
    _tallyWindows = const [];
    _tallyIds = const {};
    _tallyAwarded = 0;
  }

  void _onTallyTick() {
    if (!_tallying) return;
    final seconds = _tallyAnim.value * _kTallyDuration.inMilliseconds / 1000;
    final done = tallyFinished(_tallyWindows, seconds);
    final gain = done - _tallyAwarded;
    if (gain <= 0 || !mounted) return;
    setState(() {
      _tallyAwarded = done;
      _collectionScore += gain;
    });
  }

  void _onTallyStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !_tallying) return;
    if (!mounted) return;
    final gone = _tallyIds;
    setState(() {
      final pending = _tallyWindows.length - _tallyAwarded;
      if (pending > 0) _collectionScore += pending;
      _tallying = false;
      _tallyCells = const [];
      _tallyWindows = const [];
      _tallyIds = const {};
      _sheet = _sheet.copyWith(
        pieces: [
          for (final piece in _sheet.pieces)
            if (!gone.contains(piece.id)) piece,
        ],
      );
    });
    if (!_celebrateAnim.isAnimating) _presentNext();
  }

  /// The finished puzzle stays on screen. The next one is parked off to the
  /// right, then the camera travels to it. The last puzzle in the collection
  /// ends on the victory screen instead.
  void _presentNext() {
    if (_advancing || _collectionWon) return;
    final next = _nextPuzzle;
    final step = next == null || next.steps.isEmpty ? null : next.steps.first;
    if (next == null || step == null) {
      setState(() => _collectionWon = true);
      return;
    }
    final right = screenRight(_camera.roll);
    final shift = placeNextPuzzle(
      occupied: drawnPiecePoints(_sheet.pieces),
      nextPaper: step.paper,
      lookAt: _camera.lookAt,
      right: right,
      halfWidth: visibleHalfWidth(
        framedHalfHeight: _camera.framedHalfHeightMm,
        viewport: _viewport,
      ),
      padding: math.max(2, step.gridSpacing * 2),
    );
    final sheetMm = math.max(step.paper.width, step.paper.height);
    _advanceFrom = _camera.lookAt;
    _advanceTo = step.paper.center + shift;
    _advanceFromHeight = _camera.framedHalfHeightMm;
    _advanceToHeight = _camera.halfHeightForSheet(_viewport, sheetMm: sheetMm);
    setState(() {
      _advancing = true;
      _incomingStep = shiftStep(step, shift);
      _incomingSheet = shiftSheet(_freshSheet(step), shift);
    });
    _advanceAnim.forward(from: 0);
  }

  void _onAdvanceTick() {
    final t = Curves.easeInOutCubic.transform(_advanceAnim.value);
    _camera.moveLook(
      lookAt: Offset.lerp(_advanceFrom, _advanceTo, t)!,
      halfHeight:
          _advanceFromHeight + (_advanceToHeight - _advanceFromHeight) * t,
    );
  }

  void _onAdvanceStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !_advancing) return;
    final collection = _collection;
    if (collection == null) return;
    final nextIndex = _puzzleIndex + 1;
    if (nextIndex >= collection.puzzles.length) return;
    final puzzle = collection.puzzles[nextIndex];
    final center = puzzle.steps.isEmpty
        ? _camera.lookAt
        : puzzle.steps.first.paper.center;
    setState(() {
      _puzzleIndex = nextIndex;
      _loadStep(0, puzzle, frame: false);
    });
    _camera.moveLook(lookAt: center, halfHeight: _advanceToHeight);
    _rememberStart();
  }

  /// Paper pieces that already match a freed blueprint ring.
  Set<String> _liberatedPieceIds() {
    final ids = <String>{};
    for (final index in _liberated) {
      if (index < 0 || index >= _step.polygons.length) continue;
      final piece = paperMatchingRing(_step.polygons[index], _sheet);
      if (piece != null) ids.add(piece.id);
    }
    return ids;
  }

  bool _isCelebrating(String id) {
    for (final play in _celebrations) {
      if (play.pieceId == id) return true;
    }
    return false;
  }

  void _stopCelebrate() {
    if (_celebrateAnim.isAnimating) _celebrateAnim.stop();
    _celebrations = const [];
  }

  void _onCelebrateStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    final bursting = {
      for (final play in _celebrations)
        if (play.burst) play.pieceId,
    };
    _celebrations = const [];
    if (!mounted) return;
    if (bursting.isNotEmpty) {
      setState(() {
        _sheet = _sheet.copyWith(
          pieces: [
            for (final piece in _sheet.pieces)
              if (!bursting.contains(piece.id)) piece,
          ],
        );
      });
    }
    if (_won && !_tallying && !_celebrateAnim.isAnimating) _presentNext();
  }

  void _onSplitTick() {
    if (_splitFrom.length != _sheet.pieces.length ||
        _splitTo.length != _sheet.pieces.length) {
      return;
    }
    final t = Curves.easeOutCubic.transform(_splitAnim.value);
    setState(() {
      _sheet = _sheet.copyWith(
        pieces: [
          for (var i = 0; i < _sheet.pieces.length; i++)
            _sheet.pieces[i].copyWith(
              separation: Offset.lerp(_splitFrom[i], _splitTo[i], t)!,
            ),
        ],
      );
    });
  }

  void _stopFold() {
    _cancelFoldHold();
    if (_foldAnim.isAnimating) _foldAnim.stop();
    if (_foldSettle.isAnimating) _foldSettle.stop();
    final dropJoint = _creaseTwitch || _foldPreviewJoint;
    _creaseTwitch = false;
    _foldingMode = false;
    _foldPreviewJoint = false;
    _settlingFold = false;
    _foldSigned = 0;
    if (_creaseAnim.isAnimating) _creaseAnim.stop();
    if (dropJoint && _sheet.folds.isNotEmpty) {
      _sheet = _sheet.copyWith(
        folds: _sheet.folds.sublist(0, _sheet.folds.length - 1),
      );
    }
    _foldBend = null;
    _unfoldTo = null;
  }

  void _cancelFoldHold() {
    _foldHold?.cancel();
    _foldHold = null;
  }

  void _armFoldHold() {
    _cancelFoldHold();
    if (_tool != _GridTool.folder || _folderGuideDown == null) return;
    if (_foldAnim.isAnimating || _creaseAnim.isAnimating || _settlingFold) {
      return;
    }
    _foldHold = Timer(_kFoldHold, _enterFoldingMode);
  }

  void _enterFoldingMode() {
    _foldHold = null;
    if (!mounted || !_pointerDown || _tool != _GridTool.folder) return;
    final guide = _folderGuideDown;
    if (guide == null || _foldingMode || _settlingFold) return;
    final axis = _screenAxisOfCreaseNormal(guide);
    final flap = guide.flap ?? _fallbackFlap(guide);
    if (axis == null || flap == null) return;
    final side = sideOfLine(flap, guide.line.$1, guide.line.$2);
    if (side.abs() < 1e-4) return;
    unawaited(fmHaptic(FmHapticStyle.mediumImpact));
    final joint = FoldJoint(
      a: guide.line.$1,
      b: guide.line.$2,
      side: side,
      facing: FoldFacing.toward,
      pieceIds: {guide.pieceId},
    );
    final next = _sheet.copyWith(folds: [..._sheet.folds, joint]);
    setState(() {
      _foldingMode = true;
      _foldPreviewJoint = true;
      _foldSigned = 0;
      _foldAnchor = _lastFocal ?? _gestureDown;
      _foldScreenAxis = axis;
      _sheet = next;
      _foldBend = next.folds.length - 1;
    });
  }

  void _updateFoldPreview(Offset local) {
    final guide = _folderGuideDown;
    final anchor = _foldAnchor;
    final axis = _foldScreenAxis;
    if (guide == null || anchor == null || axis == null) return;
    final delta = local - anchor;
    final signed = foldBarSigned(
      delta.dx * axis.dx + delta.dy * axis.dy,
      _kFoldBarHalf,
    );
    if ((signed - _foldSigned).abs() < 1e-4) return;
    _foldSigned = signed;
    _syncPreviewSide(guide);
    setState(() {});
  }

  void _syncPreviewSide(FolderGuide guide) {
    if (!_foldPreviewJoint || _sheet.folds.isEmpty) return;
    if (_foldSigned.abs() < 1e-4) return;
    final normal = creaseLeftNormal(guide.line.$1, guide.line.$2);
    if (normal == null) return;
    final mid = Offset(
      (guide.line.$1.dx + guide.line.$2.dx) / 2,
      (guide.line.$1.dy + guide.line.$2.dy) / 2,
    );
    final flap = flapForPerpendicularDrag(
      drag: normal * _foldSigned.sign,
      creaseA: guide.line.$1,
      creaseB: guide.line.$2,
      origin: mid,
    );
    if (flap == null) return;
    final side = sideOfLine(flap, guide.line.$1, guide.line.$2);
    final last = _sheet.folds.last;
    if ((last.side - side).abs() < 1e-6) return;
    final folds = [..._sheet.folds];
    folds[folds.length - 1] = FoldJoint(
      a: last.a,
      b: last.b,
      side: side,
      facing: last.facing,
      pieceIds: last.pieceIds,
    );
    _sheet = _sheet.copyWith(folds: folds);
  }

  void _releaseFoldingMode() {
    final guide = _folderGuideDown;
    final signed = _foldSigned;
    _foldingMode = false;
    if (guide == null || !_foldPreviewJoint) {
      _foldPreviewJoint = false;
      _foldBend = null;
      setState(() {});
      return;
    }
    if (foldPreviewCommits(signed)) {
      _commitFoldPreview(guide, signed);
      return;
    }
    _easeFoldPreview(foldPreviewBend(signed), 0);
  }

  void _easeFoldPreview(double from, double to) {
    _settlingFold = true;
    _settleFrom = from;
    _settleTo = to;
    setState(() {});
    _foldSettle.forward(from: 0);
  }

  void _commitFoldPreview(FolderGuide guide, double signed) {
    final from = foldPreviewBend(signed);
    final normal = creaseLeftNormal(guide.line.$1, guide.line.$2);
    final mid = Offset(
      (guide.line.$1.dx + guide.line.$2.dx) / 2,
      (guide.line.$1.dy + guide.line.$2.dy) / 2,
    );
    final flap = normal == null
        ? null
        : flapForPerpendicularDrag(
            drag: normal * signed.sign,
            creaseA: guide.line.$1,
            creaseB: guide.line.$2,
            origin: mid,
          );
    final base = _sheet.folds.isEmpty
        ? _sheet
        : _sheet.copyWith(
            folds: _sheet.folds.sublist(0, _sheet.folds.length - 1),
          );
    final next = flap == null || !_canSpend(CraftTool.folder, _folderUses)
        ? null
        : foldSheet(
            sheet: base,
            spanA: guide.line.$1,
            spanB: guide.line.$2,
            flapPoint: flap,
            cutShift: guide.separation,
            facing: FoldFacing.toward,
            noFold: _step.permutation.noFold,
            blueprintPieces: _step.closedPolygons,
            pieceId: guide.pieceId,
          );
    if (next == null) {
      _easeFoldPreview(from, 0);
      return;
    }
    _foldPreviewJoint = false;
    _sheet = base;
    _pushUndo();
    setState(() {
      _sheet = next;
      _folderUses += 1;
      _foldBend = next.folds.length - 1;
      _settlingFold = true;
      _settleFrom = from;
      _settleTo = 1;
    });
    _foldSettle.forward(from: 0);
    _playCutCelebration();
  }

  void _onFoldSettle(AnimationStatus status) {
    if (status != AnimationStatus.completed || !_settlingFold || !mounted) {
      return;
    }
    setState(() {
      if (_foldPreviewJoint && _settleTo == 0 && _sheet.folds.isNotEmpty) {
        _sheet = _sheet.copyWith(
          folds: _sheet.folds.sublist(0, _sheet.folds.length - 1),
        );
      }
      _foldPreviewJoint = false;
      _settlingFold = false;
      _foldBend = null;
      _foldSigned = 0;
    });
  }

  double get _shownBend {
    if (_foldingMode) return foldPreviewBend(_foldSigned);
    if (_settlingFold) {
      final t = Curves.easeOut.transform(_foldSettle.value);
      return _settleFrom + (_settleTo - _settleFrom) * t;
    }
    if (_creaseTwitch) return creaseFoldBend(_creaseAnim.value);
    return _foldAnim.value;
  }

  void _onCreaseStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !_creaseTwitch || !mounted) {
      return;
    }
    setState(() {
      if (_sheet.folds.isNotEmpty) {
        _sheet = _sheet.copyWith(
          folds: _sheet.folds.sublist(0, _sheet.folds.length - 1),
        );
      }
      _creaseTwitch = false;
      _foldBend = null;
    });
  }

  /// A fold lands at completed. An unfold runs backward and lands at dismissed.
  /// Each also reports the opposite status when it jumps to its start value.
  void _onFoldStatus(AnimationStatus status) {
    if (!mounted) return;
    final opened = _unfoldTo;
    if (status == AnimationStatus.completed && opened == null) {
      setState(() => _foldBend = null);
    } else if (status == AnimationStatus.dismissed && opened != null) {
      setState(() {
        _sheet = opened;
        _unfoldTo = null;
        _foldBend = null;
      });
    }
  }

  FolderGuide? _folderGuide(Offset? aim) {
    if (_tool != _GridTool.folder ||
        aim == null ||
        _foldAnim.isAnimating ||
        _creaseAnim.isAnimating ||
        _settlingFold ||
        _foldingMode) {
      return null;
    }
    if (unfoldCue(_sheet, aim) != null) return null;
    return folderGuide(aim, _sheet, _step.gridSpacing);
  }

  /// [aim] stays where the paper is drawn: [unfoldCue] and [folderGuide]
  /// already add each piece's separation and fold reflections.
  (Offset, Offset)? _unfoldCue(Offset? aim) {
    if (_tool != _GridTool.folder ||
        aim == null ||
        _foldAnim.isAnimating ||
        _creaseAnim.isAnimating ||
        _settlingFold ||
        _foldingMode) {
      return null;
    }
    return unfoldCue(_sheet, aim);
  }

  /// A press on a crease unfolds it. A press elsewhere scores that segment.
  void _onFolderPress(Offset aim) {
    if (_failing ||
        _won ||
        _foldAnim.isAnimating ||
        _creaseAnim.isAnimating ||
        _settlingFold ||
        _foldingMode) {
      return;
    }
    final opened = unfoldAt(_sheet, aim);
    if (opened != null) {
      if (!_canSpend(CraftTool.folder, _folderUses)) return;
      final bend = _openedJoint(_sheet, opened);
      _pushUndo();
      if (bend == null) {
        setState(() {
          _sheet = opened;
          _folderUses += 1;
        });
        return;
      }
      setState(() {
        _folderUses += 1;
        _foldBend = bend;
        _unfoldTo = opened;
      });
      _foldAnim.reverse(from: 1);
      return;
    }
    final guide = folderGuide(aim, _sheet, _step.gridSpacing);
    if (guide == null) return;
    _startCrease(guide);
  }

  void _startCrease(FolderGuide guide) {
    final flap = guide.flap ?? _fallbackFlap(guide);
    if (flap == null) return;
    final side = sideOfLine(flap, guide.line.$1, guide.line.$2);
    if (side.abs() < 1e-4) return;
    _pushUndo();
    final scored = scoreCrease(_sheet, guide.line.$1, guide.line.$2);
    final joint = FoldJoint(
      a: guide.line.$1,
      b: guide.line.$2,
      side: side,
      facing: FoldFacing.toward,
      pieceIds: {guide.pieceId},
    );
    setState(() {
      _sheet = scored.copyWith(folds: [...scored.folds, joint]);
      _creaseTwitch = true;
      _foldBend = scored.folds.length;
    });
    _creaseAnim.forward(from: 0);
  }

  Offset? _fallbackFlap(FolderGuide guide) {
    final normal = creaseLeftNormal(guide.line.$1, guide.line.$2);
    if (normal == null) return null;
    final mid = Offset(
      (guide.line.$1.dx + guide.line.$2.dx) / 2,
      (guide.line.$1.dy + guide.line.$2.dy) / 2,
    );
    return mid + normal;
  }

  Offset? _screenAxisOfCreaseNormal(FolderGuide guide) {
    final normal = creaseLeftNormal(guide.drawn.$1, guide.drawn.$2);
    if (normal == null) return null;
    final mid = Offset(
      (guide.drawn.$1.dx + guide.drawn.$2.dx) / 2,
      (guide.drawn.$1.dy + guide.drawn.$2.dy) / 2,
    );
    Offset? project(Offset point) {
      return _camera.camera.projectToScreen(
        Vector3(point.dx, point.dy, 0),
        _viewport,
      );
    }

    final origin = project(mid);
    final tipped = project(mid + normal);
    if (origin == null || tipped == null) return null;
    final screen = tipped - origin;
    final length = screen.distance;
    if (length < 1e-3) return null;
    return screen / length;
  }

  /// Index of the fold that is folded in [before] and open in [after].
  int? _openedJoint(PapercutSheet before, PapercutSheet after) {
    final count = math.min(before.folds.length, after.folds.length);
    for (var i = 0; i < count; i++) {
      if (before.folds[i].facing == FoldFacing.unfolded) continue;
      if (after.folds[i].facing == FoldFacing.unfolded) return i;
    }
    return null;
  }

  /// Snapped punch centers under the crosshair, including fold mirrors.
  List<Offset> _punchPreviewCenters(Offset? aim) {
    if (_tool != _GridTool.holePunch || aim == null || _failing || _won) {
      return const [];
    }
    final center = snapPunchCenter(_toModel(aim), _step.gridSpacing);
    final centers = <Offset>[center];
    for (final joint in _sheet.folds) {
      if (joint.facing == FoldFacing.unfolded) continue;
      centers.add(reflectAcrossLine(center, joint.a, joint.b));
    }
    return centers;
  }

  bool _punchPreviewBlocked(Offset? aim) {
    for (final center in _punchPreviewCenters(aim)) {
      final outline = punchOutline(center, _punchShape, _punchSize);
      if (punchCrossesBlueprint(outline, _step.closedPolygons)) return true;
    }
    return false;
  }

  void _onPunch(Offset aim) {
    if (_failing || _won) return;
    if (!_canSpend(CraftTool.holePunch, _punchUses)) return;
    final world = snapPunchCenter(_toModel(aim), _step.gridSpacing);
    final outline = punchOutline(world, _punchShape, _punchSize);
    if (punchCrossesBlueprint(outline, _step.closedPolygons)) return;
    var next = subtractRegion(_sheet, outline);
    if (next == null) return;
    for (final joint in _sheet.folds) {
      if (joint.facing == FoldFacing.unfolded) continue;
      final mirrored = [
        for (final point in outline) reflectAcrossLine(point, joint.a, joint.b),
      ];
      next = subtractRegion(next!, mirrored) ?? next;
    }
    _pushUndo();
    setState(() {
      _sheet = next!;
      _punchUses += 1;
    });
    for (var i = 0; i < outline.length; i++) {
      _noteTouch(outline[i], outline[(i + 1) % outline.length]);
    }
    _releaseTouches();
    if (_failIfRemovedEarly()) return;
    _playCutCelebration();
  }

  void _rotatePiece(bool clockwise) {
    if (_splitAnim.isAnimating) return;
    _animateQuarter(!clockwise);
  }

  void _onTurnTick() {
    final origin = _turnOrigin;
    final fromStep = _turnFromStep;
    final fromSheet = _turnFromSheet;
    if (origin == null || fromStep == null || fromSheet == null) return;
    final t = Curves.easeOutCubic.transform(_turnAnim.value);
    final radians = (_turnClockwise ? -1 : 1) * math.pi / 2 * t;
    final steps = [..._blueprint.steps];
    steps[_stepIndex] = rotateStepBy(fromStep, origin, radians);
    setState(() {
      _blueprint = _blueprint.copyWith(steps: steps);
      _sheet = rotateSheetBy(fromSheet, origin, radians);
      _showMarch(origin, radians);
    });
    _pinScissor();
    _syncFlight();
  }

  void _onTurnStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    final origin = _turnOrigin;
    final fromStep = _turnFromStep;
    final fromSheet = _turnFromSheet;
    if (origin == null || fromStep == null || fromSheet == null) return;
    final radians = (_turnClockwise ? -1 : 1) * math.pi / 2;
    final steps = [..._blueprint.steps];
    steps[_stepIndex] = rotateStep(fromStep, clockwise: _turnClockwise);
    setState(() {
      _blueprint = _blueprint.copyWith(steps: steps);
      _baseline = steps[_stepIndex];
      _sheet = rotateSheet(fromSheet, origin, clockwise: _turnClockwise);
      _showMarch(origin, radians);
      _rulerX = _snap(_step.paper.center.dx, _step.gridSpacing);
      _turnFromStep = null;
      _turnFromSheet = null;
      _turnFromMarch = null;
      _turnFromBase = null;
    });
    _pinScissor();
    _syncFlight();
  }

  void _showMarch(Offset origin, double radians) {
    final march = _turnFromMarch;
    if (march == null) return;
    _march = ScissorMarch(
      path: [
        for (final point in march.path)
          rotateGridPointBy(point, origin, radians),
      ],
      direction: rotateGridPointBy(march.direction, Offset.zero, radians),
      locked: march.locked,
    );
    final base = _turnFromBase;
    if (base != null) {
      _marchBase = rotateSheetBy(base, origin, radians);
    }
  }

  void _clear() {
    if (_advancing) return;
    _turnAnim.stop();
    _splitAnim.stop();
    _stopCelebrate();
    _stopFold();
    _stopFade();
    _stopTally();
    if (_flightAnim.isAnimating) _flightAnim.stop();
    _endMeeting();
    if (_focusAnim.isAnimating) _focusAnim.stop();
    _armingCut = false;
    _armedFrom = null;
    _armedTo = null;
    _modelEnd = null;
    _cutRoll = null;
    _flight.reset();
    _strokeDirection = null;
    _turnFromStep = null;
    final steps = [..._blueprint.steps];
    steps[_stepIndex] = _baseline;
    setState(() {
      _blueprint = _blueprint.copyWith(steps: steps);
      _sheet = _freshSheet(_step);
      _clearOffDesk();
      _march = null;
      _marchBase = null;
      _bladePieceId = null;
      _undo.clear();
      _undoProgress.clear();
      _undoLiberated.clear();
      _progress = const CutProgress();
      _cutQueue.clear();
      _picked = null;
      _stacks.clear();
      _dragPiece = null;
      _won = false;
      _collectionWon = false;
      _liberated = {};
    });
    _syncFlight();
  }

  Future<void> _save() async {
    await _levelsStore.save(_blueprint);
    await _refreshCollections();
  }

  void _pushUndo() {
    _undo.add(_sheet.clone());
    _undoProgress.add(_progress);
    _undoLiberated.add({..._liberated});
    _undoOffDesk.add(
      _OffDesk(
        pieces: {..._offDesk},
        stowed: [..._stowed],
        placements: [..._placements, ?_placing],
      ),
    );
    if (_undo.length > 40) {
      _undo.removeAt(0);
      _undoProgress.removeAt(0);
      if (_undoLiberated.isNotEmpty) _undoLiberated.removeAt(0);
      if (_undoOffDesk.isNotEmpty) _undoOffDesk.removeAt(0);
    }
  }

  /// Paper leaves the stores for the inventory and the model. The sheet is
  /// reset alongside.
  void _clearOffDesk() {
    _offDesk.clear();
    _stowed.clear();
    _placements.clear();
    _placing = null;
    _dropping = null;
    _wrapIsland = null;
    _undoOffDesk.clear();
    _scoredIslands.clear();
  }

  void _undoLast() {
    if (_locked || _undo.isEmpty || _advancing) return;
    _splitAnim.stop();
    _stopCelebrate();
    _stopFold();
    _stopFade();
    _stopTally();
    setState(() {
      _sheet = _undo.removeLast();
      if (_undoOffDesk.isNotEmpty) {
        final off = _undoOffDesk.removeLast();
        _offDesk
          ..clear()
          ..addAll(off.pieces);
        _stowed
          ..clear()
          ..addAll(off.stowed);
        _placements
          ..clear()
          ..addAll(off.placements);
        _placing = null;
        _wrapIsland = null;
      }
      if (_undoProgress.isNotEmpty) _progress = _undoProgress.removeLast();
      _march = null;
      _marchBase = null;
      _bladePieceId = null;
      _cutQueue.clear();
      if (_picked != null && _picked! >= _sheet.pieces.length) _picked = null;
      _stacks.adopt(_picked);
      _won = false;
      _collectionWon = false;
      _liberated = _undoLiberated.isEmpty ? {} : _undoLiberated.removeLast();
    });
    _syncFlight();
  }

  Offset _screenCardinal(_CutSide side) {
    final screen = switch (side) {
      _CutSide.up => const Offset(0, 1),
      _CutSide.down => const Offset(0, -1),
      _CutSide.left => const Offset(-1, 0),
      _CutSide.right => const Offset(1, 0),
    };
    return rotateGridPointBy(screen, Offset.zero, -_camera.roll);
  }

  Offset? _arrival() {
    final path = _march?.path;
    if (path == null || path.length < 2) return null;
    return path.last - path[path.length - 2];
  }

  List<ForwardCut> _forwardOptions() {
    final march = _march;
    final forward = _arrival();
    if (march == null || forward == null) return const [];
    final piece = _bladePiece();
    return forwardCuts(
      from: march.position,
      forward: forward,
      directions: lineworkDirections(
        at: march.position,
        closed: _bladeOutlines(piece),
        open: [...openBlueprint(_step), ..._sheet.cutStrokes, march.path],
      ),
      closed: _bladeOutlines(piece),
      open: [...openBlueprint(_step), ..._sheet.cutStrokes],
      boundary: _paperEdges(piece),
      skipCollinear: _skipPenciled,
    );
  }

  /// The crosshair is the center of the screen. ViewCrosshair is centered
  /// on this same point.
  Offset get _crosshair => Offset(_viewport.width / 2, _viewport.height / 2);

  /// Follow mode measures from the reticle. Fixed mode measures from the tool.
  Offset _directionOrigin() => directionTapOrigin(
    cameraFollowsTool: _cameraFollowsTool,
    reticle: _crosshair,
    toolOnScreen: _trackedToolScreen(),
  );

  /// Larger offset from the aim point. A tap above and left is up when the
  /// vertical component is greater, and left when the horizontal one is.
  _CutSide? _tapSide(Offset? local) {
    if (local == null || _viewport.width < 2 || _viewport.height < 2) {
      return null;
    }
    final side = dominantScreenSide(
      local - _directionOrigin(),
      deadZone: _kCrosshairCutRadius,
    );
    return switch (side) {
      ScreenSide.up => _CutSide.up,
      ScreenSide.down => _CutSide.down,
      ScreenSide.left => _CutSide.left,
      ScreenSide.right => _CutSide.right,
      null => null,
    };
  }

  void _noteTap(Offset? local) {
    if (!_showTapDebug || local == null || _viewport.width < 2) return;
    final side = _tapSide(local);
    setState(() {
      _debugTap = local;
      _debugSide = side?.name ?? 'forward';
    });
  }

  _CutSide _cutSide(ScreenSide side) {
    return switch (side) {
      ScreenSide.up => _CutSide.up,
      ScreenSide.down => _CutSide.down,
      ScreenSide.left => _CutSide.left,
      ScreenSide.right => _CutSide.right,
    };
  }

  /// One stroke from a swipe. A cut already traveling stores the side.
  void _aimSeatedCut(_CutSide? side) {
    if (_cutting) {
      _enqueueCut(side);
      return;
    }
    _performCut(side);
  }

  void _chooseCut(Offset? local) {
    if (_cutting) {
      _enqueueCut(_tapSide(local));
      return;
    }
    if (!_directing) return;
    _performCut(_tapSide(local));
  }

  void _enqueueCut(_CutSide? side) {
    _cutQueue.add(side);
    if (!_showTapDebug) return;
    setState(() {
      _debugSide = '${side?.name ?? 'forward'}  queued ${_cutQueue.length}';
    });
  }

  /// Starts the next stored tap once the blade is free. A side with no legal
  /// cut is dropped so a later tap can still run.
  bool _takeQueuedCut() {
    while (_cutQueue.isNotEmpty) {
      if (_performCut(_cutQueue.removeAt(0))) return true;
    }
    return false;
  }

  /// True when a stroke actually starts. Null continues the arrival direction.
  bool _performCut(_CutSide? side) {
    if (!_directing) return false;
    final from = _march?.position;
    if (from == null) return false;
    final options = _forwardOptions();
    ForwardCut? pick(Offset wish) {
      final cut = mostForwardCut(options, wish);
      if (cut == null) return null;
      final length = wish.distance;
      if (length < 1e-8) return null;
      final heading = wish / length;
      final dot = cut.direction.dx * heading.dx + cut.direction.dy * heading.dy;
      return dot > 0.2 ? cut : null;
    }

    final ForwardCut? cut;
    if (side == null) {
      final forward = _arrival();
      if (forward == null) return false;
      cut = pick(forward);
    } else {
      cut = pick(_screenCardinal(side));
    }
    if (cut == null) return false;
    return _beginStroke(from, cut.end);
  }

  void _cutCardinal(_CutSide side) {
    if (_cutting) {
      _enqueueCut(side);
      return;
    }
    _performCut(side);
  }

  /// Side taps and arrow keys. Right is counterclockwise.
  void _nudgeRoll({required bool counterclockwise}) {
    if (_fixedToolCamera) return;
    if (_tool != _GridTool.scissors) return;
    if (_cutting) return;
    _animateQuarter(counterclockwise);
  }

  /// Lands on the next 0/90/180/270. An in-between angle does not add a full
  /// extra quarter on top of itself.
  void _animateQuarter(bool counterclockwise) {
    final base = _rollNudge.isAnimating ? _rollTo : _camera.roll;
    _animateRollTo(
      PapercutCamera.nextQuarterTurn(base, counterclockwise: counterclockwise),
    );
  }

  /// Turns the sheet so [target] is the roll. Independent of the cut's
  /// world direction: the stroke already knows where it is going.
  void _animateRollTo(double target) {
    if (_fixedToolCamera) return;
    _rollFrom = _camera.roll;
    _rollTo = target;
    if ((_rollTo - _rollFrom).abs() < 1e-3) return;
    _rollNudge.forward(from: 0);
  }

  void _onRollNudge() {
    if (_fixedToolCamera) return;
    final t = Curves.easeOutCubic.transform(_rollNudge.value);
    _camera.setRoll(_rollFrom + (_rollTo - _rollFrom) * t);
    if (_cutting) return;
    _pinScissor();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_inModel) {
      if (event.logicalKey != LogicalKeyboardKey.escape) {
        return KeyEventResult.ignored;
      }
      if (_focusFace != null) {
        _leaveFocus();
      } else {
        _toggleMode();
      }
      return KeyEventResult.handled;
    }
    if (_directing && _tool == _GridTool.scissors) {
      final side = switch (event.logicalKey) {
        LogicalKeyboardKey.arrowUp => _CutSide.up,
        LogicalKeyboardKey.arrowDown => _CutSide.down,
        LogicalKeyboardKey.arrowLeft => _CutSide.left,
        LogicalKeyboardKey.arrowRight => _CutSide.right,
        _ => null,
      };
      if (side != null) {
        if (_cutting && event is KeyRepeatEvent) return KeyEventResult.handled;
        _cutCardinal(side);
        return KeyEventResult.handled;
      }
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _nudgeRoll(counterclockwise: true);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _nudgeRoll(counterclockwise: false);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  bool get _inModel => _mode == _ViewMode.model;

  /// 0 on the flat sheet, 1 with the model fully folded up.
  double get _modelness => Curves.easeInOutCubic.transform(_modeAnim.value);

  /// Folded model of the current level, when its craft link resolves.
  FoldedModel? get _model {
    final link = _step.craft;
    if (link == null) return null;
    if (identical(_modelStep, _step)) return _modelCache;
    final craft = _crafts[link.id];
    if (craft == null) return null;
    _modelStep = _step;
    final built = foldedModelFromCraft(craft, link.step, _step);
    _modelCache = built == null ? null : _floatOverDesk(built);
    _decals = _modelCache == null ? const [] : faceDecals(_modelCache!);
    return _modelCache;
  }

  /// The model hovers above the middle of the blueprint's paper, clear of
  /// the desk by about half its size.
  FoldedModel _floatOverDesk(FoldedModel model) {
    final middle = _step.paper.center;
    final bounds = model.bounds;
    final size = bounds.max - bounds.min;
    final gap = math.max(_step.gridSpacing * 2, size.z * 0.5);
    return model.moved(
      Vector3(
        middle.dx - model.center.x,
        middle.dy - model.center.y,
        gap - bounds.min.z,
      ),
    );
  }

  /// The desk in 3D: the blueprint's paper and every desk piece, with a
  /// margin.
  Rect get _deskRect {
    var rect = _step.paper;
    for (final piece in _sheet.pieces) {
      if (piece.vertices.isEmpty) continue;
      rect = rect.expandToInclude(
        pointBounds(piece.vertices).shift(piece.separation),
      );
    }
    return rect.inflate(_step.gridSpacing * 2);
  }

  void _toggleMode() {
    if (_modeAnim.isAnimating || _flyAnim.isAnimating || _lapping) return;
    if (_inModel) {
      _leaveFocus(fly: false);
      _camera.beginToggle();
      final flat = _flatPose;
      _camera.beginFly(
        CameraPose(
          lookAt: flat?.lookAt ?? _step.paper.center,
          halfHeight: flat?.halfHeight ?? _camera.framedHalfHeightMm,
          azimuth: PapercutCamera.advanceAngle(_camera.azimuth, 0),
          elevation: 0,
          roll: flat?.roll ?? 0,
        ),
      );
      _settleTimer?.cancel();
      _settled = false;
      _setPreselect(null);
      setState(() => _mode = _ViewMode.flat);
      _modeAnim.reverse(from: 1);
      return;
    }
    final model = _model;
    if (model == null || _advancing || _collectionWon || _locked) return;
    _cancelFoldHold();
    if (_foldingMode) {
      _foldSigned = 0;
      _releaseFoldingMode();
    }
    _flatPose = _camera.pose;
    _camera.beginToggle();
    _camera.beginFly(
      _modelFraming(model).withAngles(
        _camera.anglesAlong(
          _turntableDirection(_kModelTurn, _kModelTilt),
          up: _modelUp,
        ),
      ),
    );
    setState(() => _mode = _ViewMode.model);
    _modeAnim.forward(from: 0);
  }

  static final Vector3 _modelUp = Vector3(0, 0, 1);

  /// Eye direction around the model's vertical axis. [turn] spins about +z
  /// from +x; [tilt] lifts above the sheet.
  Vector3 _turntableDirection(double turn, double tilt) => Vector3(
    math.cos(tilt) * math.cos(turn),
    math.cos(tilt) * math.sin(turn),
    math.sin(tilt),
  );

  CameraPose _modelFraming(FoldedModel model) =>
      _camera.frameSphere(model.center, model.radius * 1.3, _viewport);

  /// One-finger orbit: a turntable around the model's vertical axis.
  void _turntable(double dTurn, double dTilt) {
    final n = _camera.viewDirection;
    final turn = math.atan2(n.y, n.x) + dTurn;
    final tilt = (math.asin(n.z.clamp(-1.0, 1.0)) + dTilt).clamp(
      -_kMaxTilt,
      _kMaxTilt,
    );
    _camera.orbitTo(_turntableDirection(turn, tilt), up: _modelUp);
  }

  void _onModeTick() {
    final value = _modeAnim.value;
    final travel = _inModel ? value : 1 - value;
    final t = (travel * 2).clamp(0.0, 1.0);
    _camera.setBlend(t);
    _camera.setFly(Curves.easeInOutCubic.transform(t));
  }

  void _onFlyTick() {
    _camera.setFly(Curves.easeOutCubic.transform(_flyAnim.value));
  }

  /// Back on the flat sheet at once, with no placements. Used on level load.
  void _leaveModelNow() {
    if (_modeAnim.isAnimating) _modeAnim.stop();
    if (_flyAnim.isAnimating) _flyAnim.stop();
    if (_wrapAnim.isAnimating) _wrapAnim.stop();
    _stopLap();
    if (_inModel || !_camera.targetFlat) {
      _camera.beginToggle();
      _camera.setBlend(1);
      _camera.beginFly(
        CameraPose(
          lookAt: _camera.lookAt,
          halfHeight: _camera.framedHalfHeightMm,
          azimuth: 0,
          elevation: 0,
          roll: _flatPose?.roll ?? 0,
        ),
      );
      _camera.setFly(1);
    }
    _modeAnim.value = 0;
    _mode = _ViewMode.flat;
    _focusFace = null;
    _orbitPose = null;
    _flatPose = null;
    _clearOffDesk();
    _deskAnim.value = 0;
    _deskDragId = null;
    _overInventory = false;
    _placeDragging = false;
    _lastTapTime = null;
    _settleTimer?.cancel();
    _settled = false;
    _preselect = null;
    _preselectTicker.stop();
    _preselectFill.value = const {};
    _dropping = null;
    _dropShown.value = false;
    _planeGrab = null;
  }

  void _frameModel() {
    final model = _model;
    if (model == null || _modeAnim.isAnimating || _lapping) return;
    _leaveFocus(fly: false);
    _camera.beginFly(_modelFraming(model));
    _flyAnim.forward(from: 0);
  }

  CraftPlane _facePlane(FoldedModel model, int face) =>
      CraftPlane(model.faces[face].toWorld);

  void _cameraMoved() {
    final eye = _camera.camera.position.clone();
    final target = _camera.target;
    final half = _camera.framedHalfHeightMm;
    final restEye = _restEye;
    final restTarget = _restTarget;
    if (restEye != null &&
        restTarget != null &&
        (eye - restEye).length2 < 1e-12 &&
        (target - restTarget).length2 < 1e-12 &&
        (half - _restHalf).abs() < 1e-9) {
      return;
    }
    _restEye = eye;
    _restTarget = target;
    _restHalf = half;
    _updatePreselect();
    _settleTimer?.cancel();
    _settled = false;
    _settleTimer = Timer(_kSettle, () {
      if (mounted && _inModel) setState(() => _settled = true);
    });
  }

  /// The reticle's face. Focus keeps the focused face preselected.
  void _updatePreselect() {
    final model = _model;
    if (!_inModel || model == null || _lapping) {
      _setPreselect(null);
      return;
    }
    if (_focusFace != null) {
      _setPreselect(_focusFace);
      return;
    }
    _setPreselect(_targetAt(model, _crosshair));
  }

  /// The model face or the desk nearest along the ray through [screen].
  int? _targetAt(FoldedModel model, Offset screen) {
    final ray = _camera.camera.unprojectRay(screen, _viewport);
    if (ray == null) return null;
    final face = pickFace(model, ray.origin, ray.direction);
    final desk = _planeHit(CraftPlane.sheet, screen);
    final onDesk = desk != null && _deskRect.contains(desk.at);
    if (face == null) return onDesk ? _kDesk : null;
    if (onDesk && desk.distance < face.distance) return _kDesk;
    return face.face;
  }

  /// Desk paper under [screen], topmost first, unless a model face is in
  /// front of it.
  int? _deskPieceAt(FoldedModel model, Offset screen) {
    final hit = _planeHit(CraftPlane.sheet, screen);
    if (hit == null) return null;
    final ray = _camera.camera.unprojectRay(screen, _viewport);
    final face = ray == null
        ? null
        : pickFace(model, ray.origin, ray.direction);
    if (face != null && face.distance < hit.distance) return null;
    for (var i = _sheet.pieces.length - 1; i >= 0; i--) {
      final piece = _sheet.pieces[i];
      if (ownsPoint(piece.vertices, hit.at - piece.separation)) return i;
    }
    return null;
  }

  void _setPreselect(int? face) {
    if (face == _preselect) return;
    _preselect = face;
    if (_preselectTicker.isActive) return;
    _preselectElapsed = Duration.zero;
    _preselectTicker.start();
  }

  void _onPreselectTick(Duration elapsed) {
    final step =
        (elapsed - _preselectElapsed).inMicroseconds /
        _kPreselectFade.inMicroseconds;
    _preselectElapsed = elapsed;
    final current = _preselectFill.value;
    final next = <int, double>{};
    var easing = false;
    for (final face in {...current.keys, ?_preselect}) {
      final from = current[face] ?? 0;
      final to = face == _preselect ? 1.0 : 0.0;
      final value = from < to
          ? math.min(to, from + step)
          : math.max(to, from - step);
      if (value != to) easing = true;
      if (value > 0) next[face] = value;
    }
    _preselectFill.value = next;
    if (!easing) _preselectTicker.stop();
  }

  /// Works on [face] where the camera is: one finger slides the paper, or
  /// pans along the face when it misses the paper.
  void _enterFocus(int face) {
    if (_focusFace == face) return;
    _commitPlacing();
    setState(() => _focusFace = face);
    _setPreselect(face);
    _syncDesk();
    unawaited(fmHapticSmallClick());
  }

  /// Desk paper shows as paper while the desk is focused, grey otherwise.
  void _syncDesk() {
    if (_focusFace == _kDesk) {
      _deskAnim.forward();
    } else {
      _deskAnim.reverse();
    }
  }

  /// Flies the camera square onto the focused face. Leaving focus flies back.
  /// On the desk this is the 2D crafting view.
  void _focusCamera() {
    final model = _model;
    final face = _focusFace;
    if (model == null || face == null || _modeAnim.isAnimating) return;
    if (face == _kDesk) {
      _toggleMode();
      return;
    }
    _orbitPose ??= _camera.pose;
    final modelFace = model.faces[face];
    final middle = modelFace.centroid;
    var reach = 0.0;
    for (final point in modelFace.outline) {
      reach = math.max(reach, (point - middle).distance);
    }
    final aspect = _viewport.height < 2
        ? 1.0
        : _viewport.width / _viewport.height;
    final half = math.max(reach * 2.2, reach * 2.2 / math.max(aspect, 0.05));
    _camera.flyTo(
      model.worldCenter(face),
      model.outwardNormal(face),
      half / math.tan(_camera.halfFovRadians),
      up: modelFace.toWorld.getRotation().transformed(Vector3(0, 1, 0)),
    );
    _flyAnim.forward(from: 0);
  }

  void _leaveFocus({bool fly = true}) {
    if (_focusFace == null) return;
    _commitPlacing();
    final back = _orbitPose;
    _orbitPose = null;
    _planeGrab = null;
    _deskDragId = null;
    setState(() => _focusFace = null);
    _syncDesk();
    _updatePreselect();
    if (!fly || back == null) return;
    _camera.beginFly(back);
    _flyAnim.forward(from: 0);
  }

  PapercutPiece? _pieceById(String id) {
    final off = _offDesk[id];
    if (off != null) return off;
    for (final piece in _sheet.pieces) {
      if (piece.id == id) return piece;
    }
    return null;
  }

  /// Moves desk paper into the inventory. [undo] is false when the drag that
  /// brought it here already saved an undo step.
  void _stow(String id, {bool undo = true}) {
    final index = _sheet.pieces.indexWhere((piece) => piece.id == id);
    if (index < 0 || _locked || _advancing) return;
    if (undo) _pushUndo();
    final piece = _sheet.pieces[index];
    setState(() {
      _sheet = _sheet.copyWith(pieces: [..._sheet.pieces]..removeAt(index));
      _offDesk[id] = piece.copyWith(separation: Offset.zero);
      _stowed.add(id);
      if (_picked != null && _picked! >= _sheet.pieces.length) _picked = null;
      _stacks.adopt(_picked);
    });
    unawaited(fmHapticSmallClick());
  }

  /// Lays stowed paper back on the desk, nudged by [separation].
  void _unstow(String id, Offset separation) {
    final piece = _offDesk[id];
    if (piece == null || !_stowed.contains(id) || _locked || _advancing) {
      return;
    }
    _pushUndo();
    setState(() {
      _offDesk.remove(id);
      _stowed.remove(id);
      _sheet = _sheet.copyWith(
        pieces: [
          ..._sheet.pieces,
          piece.copyWith(separation: separation),
        ],
      );
    });
    unawaited(fmHapticSmallClick());
  }

  /// Separation that puts [piece]'s middle on the desk point [at].
  Offset _deskNudge(PapercutPiece piece, Offset at) =>
      _snapOffset(at - pointBounds(piece.vertices).center);

  /// Plane of a model face, or the world sheet for the desk.
  CraftPlane _planeOf(FoldedModel model, int target) =>
      target == _kDesk ? CraftPlane.sheet : _facePlane(model, target);

  bool _matches(PiecePlacement placement) {
    final model = _model;
    final piece = _pieceById(placement.pieceId);
    if (model == null || piece == null) return false;
    return placementMatches(placement, piece, model, _step);
  }

  /// Islands with a matching piece, mapped to the face the piece was laid on.
  Map<int, PiecePlacement> get _wrapped {
    final model = _model;
    if (model == null) return const {};
    return {
      for (final placement in _placements)
        if (_matches(placement)) model.faces[placement.face].island: placement,
    };
  }

  bool get _modelComplete {
    final model = _model;
    if (model == null || _wrapAnim.isAnimating) return false;
    return _wrapped.length == model.islands.length;
  }

  /// Paper the inventory offers: what was stowed and is not in hand.
  List<PapercutPiece> get _inventory => [
    for (final id in _stowed)
      if (_offDesk[id] case final piece?)
        if (id != _placing?.pieceId && piece.vertices.length >= 3) piece,
  ];

  /// The face that takes paper: the focused one, else the preselected one.
  int? get _targetFace => _focusFace ?? _preselect;

  /// The inventory is out while paper can be moved into or out of it: with
  /// the select tool on the flat desk and in desk focus. Over a model face it
  /// offers stowed paper in focus, or once the camera rests on the face, and
  /// stays out through a drop.
  bool get _inventoryShown {
    if (_model == null || _modeAnim.isAnimating || _lapping) return false;
    if (!_inModel) return _tool == _GridTool.select;
    if (_focusFace == _kDesk || _dropping != null) return true;
    if (_inventory.isEmpty) return false;
    return _focusFace != null || (_settled && _preselect != null);
  }

  /// Where paper from the inventory goes: the desk on the flat view, else the
  /// focused or preselected target.
  int? get _paperTarget => _inModel ? _targetFace : _kDesk;

  void _pickPiece(String id) {
    final model = _model;
    final target = _paperTarget;
    final piece = _pieceById(id);
    if (model == null || target == null || piece == null) return;
    if (target == _kDesk) {
      final at = _inModel
          ? _planeHit(CraftPlane.sheet, _crosshair)?.at
          : _aimWorld();
      final spot = at != null && _deskRect.contains(at)
          ? at
          : _step.paper.center;
      _unstow(id, _deskNudge(piece, spot));
      if (_inModel) _enterFocus(_kDesk);
      return;
    }
    if (_placing?.pieceId == id) return;
    _hold(target, startPlacement(piece, target, model, _step.gridSpacing));
  }

  /// Focuses [face] with [placement] in hand.
  void _hold(int face, PiecePlacement placement) {
    _enterFocus(face);
    _commitPlacing();
    _placements.removeWhere((laid) => laid.pieceId == placement.pieceId);
    _stowed.remove(placement.pieceId);
    setState(() => _placing = placement);
    _settlePlacing();
  }

  /// Where a dragged inventory piece would land with its middle at [global].
  /// On the desk the offset is the piece's separation.
  PiecePlacement? _dropAt(String id, Offset global) {
    final model = _model;
    final face = _paperTarget;
    final piece = _pieceById(id);
    final box = _dropKey.currentContext?.findRenderObject();
    if (model == null || face == null || piece == null || box is! RenderBox) {
      return null;
    }
    final local = box.globalToLocal(global);
    if (face == _kDesk) {
      final at = _inModel
          ? _planeHit(CraftPlane.sheet, local)?.at
          : _camera.planePoint(local, _viewport);
      if (at == null) return null;
      if (_inModel && !_deskRect.inflate(_step.gridSpacing * 4).contains(at)) {
        return null;
      }
      return PiecePlacement(
        pieceId: id,
        face: _kDesk,
        offset: _deskNudge(piece, at),
      );
    }
    final hit = _planeHit(_facePlane(model, face), local);
    if (hit == null) return null;
    final modelFace = model.faces[face];
    if ((hit.at - modelFace.centroid).distance > model.radius * 3) return null;
    final middle = pointBounds(piece.vertices).center;
    return PiecePlacement(
      pieceId: id,
      face: face,
      offset: snapToGrid(hit.at - middle, _step.gridSpacing),
    );
  }

  void _onDropMove(DragTargetDetails<String> details) {
    final next = _dropAt(details.data, details.offset);
    _dropShown.value = next != null;
    if (next == _dropping) return;
    setState(() => _dropping = next);
  }

  void _onDropLeave(String? _) {
    _dropShown.value = false;
    if (_dropping == null) return;
    setState(() => _dropping = null);
  }

  void _onDrop(DragTargetDetails<String> details) {
    final placement = _dropping ?? _dropAt(details.data, details.offset);
    _dropShown.value = false;
    setState(() => _dropping = null);
    if (placement == null) return;
    if (placement.face == _kDesk) {
      _unstow(placement.pieceId, placement.offset);
      if (_inModel) _enterFocus(_kDesk);
      return;
    }
    _hold(placement.face, placement);
  }

  /// [screen] is over the inventory column, give or take a finger.
  bool _overInventoryAt(Offset screen) {
    if (!_inventoryShown) return false;
    final column = _inventoryKey.currentContext?.findRenderObject();
    final canvas = _dropKey.currentContext?.findRenderObject();
    if (column is! RenderBox || canvas is! RenderBox) return false;
    if (!column.hasSize || column.size.isEmpty) return false;
    final rect = column.localToGlobal(Offset.zero) & column.size;
    return rect.inflate(16).contains(canvas.localToGlobal(screen));
  }

  void _setOverInventory(bool over) {
    if (over == _overInventory) return;
    setState(() => _overInventory = over);
  }

  /// Plane coordinates under [screen] and the ray distance to them, in front
  /// of the camera only.
  ({Offset at, double distance})? _planeHit(CraftPlane plane, Offset screen) {
    final ray = _camera.camera.unprojectRay(screen, _viewport);
    if (ray == null) return null;
    final normal = plane.normal;
    final denom = ray.direction.dot(normal);
    if (denom.abs() < 1e-8) return null;
    final t = (plane.origin - ray.origin).dot(normal) / denom;
    if (t <= 0) return null;
    return (at: plane.local(ray.pointAt(t)), distance: t);
  }

  /// Loose paper on [face] under [screen], nearest first.
  PiecePlacement? _looseAt(FoldedModel model, int face, Offset screen) {
    final hit = _planeHit(_facePlane(model, face), screen);
    if (hit == null) return null;
    for (final placement in _placements.reversed) {
      if (placement.face != face || _matches(placement)) continue;
      final piece = _pieceById(placement.pieceId);
      if (piece == null) continue;
      if (ownsPoint(placedPiece(piece, placement).vertices, hit.at)) {
        return placement;
      }
    }
    return null;
  }

  /// The tap lands on the focused face, its paper in hand, or paper laid on it.
  bool _onFocusedWork(FoldedModel model, Offset screen) {
    final face = _focusFace;
    if (face == null) return false;
    final hit = _planeHit(_planeOf(model, face), screen);
    if (hit == null) return false;
    if (face == _kDesk) return _deskRect.contains(hit.at);
    if (ownsPoint(model.faces[face].outline, hit.at)) return true;
    final placing = _placing;
    final piece = placing == null ? null : _pieceById(placing.pieceId);
    if (placing != null &&
        piece != null &&
        ownsPoint(placedPiece(piece, placing).vertices, hit.at)) {
      return true;
    }
    return _looseAt(model, face, screen) != null;
  }

  /// The tap lands on paper lying on the focused plane: desk paper, the piece
  /// in hand, or loose paper on the face.
  bool _onFocusedPaper(FoldedModel model, Offset screen) {
    final face = _focusFace;
    if (face == null) return false;
    if (face == _kDesk) return _deskPieceAt(model, screen) != null;
    final hit = _planeHit(_planeOf(model, face), screen);
    if (hit == null) return false;
    final placing = _placing;
    final piece = placing == null ? null : _pieceById(placing.pieceId);
    if (placing != null &&
        piece != null &&
        ownsPoint(placedPiece(piece, placing).vertices, hit.at)) {
      return true;
    }
    return _looseAt(model, face, screen) != null;
  }

  /// Leaves the piece in hand lying loose where it is.
  void _commitPlacing() {
    final placing = _placing;
    if (placing == null) return;
    _placing = null;
    _placements.add(placing);
  }

  /// A matching piece in hand glows, then wraps the model.
  void _settlePlacing() {
    final placing = _placing;
    final model = _model;
    if (placing == null || model == null || !_matches(placing)) return;
    setState(() {
      _placing = null;
      _placements.add(placing);
      _wrapIsland = model.faces[placing.face].island;
    });
    _wrapAnim.forward(from: 0);
    unawaited(fmHapticSmallClick());
  }

  /// The paper's middle, on the half grid so a quarter turn stays on cells.
  Offset _turnPivot(PapercutPiece placed) =>
      snapToGrid(pointBounds(placed.vertices).center * 2, _step.gridSpacing) /
      2;

  /// Turns the piece in hand to [turns] quarter turns about its middle.
  /// Every turn is taken from where the ring started, so turning back puts
  /// the paper exactly where it was; sliding the paper starts afresh.
  void _turnPlacingTo(int turns) {
    final placing = _placing;
    final piece = placing == null ? null : _pieceById(placing.pieceId);
    if (placing == null || piece == null) return;
    var from = _gimbalFrom;
    if (from == null || placing != _gimbalLast) {
      from = placing;
      _gimbalFrom = from;
    }
    final steps = (turns - from.turns) % 4;
    final pivot = _turnPivot(placedPiece(piece, from));
    final next = PiecePlacement(
      pieceId: from.pieceId,
      face: from.face,
      offset: snapToGrid(
        turn(from.offset - pivot, steps) + pivot,
        _step.gridSpacing,
      ),
      quarterTurns: (from.quarterTurns + steps) % 4,
    );
    if (next == placing) return;
    _gimbalLast = next;
    setState(() => _placing = next);
    unawaited(fmHapticSmallClick());
    _settlePlacing();
  }

  /// On the piece in hand: a rotate icon, or once tapped, a ring around the
  /// paper that turns it by quarter turns as it is dragged.
  Widget? _placeGimbal() {
    final model = _model;
    final placing = _placing;
    final face = _focusFace;
    if (!_inModel || model == null || placing == null || face == null) {
      return null;
    }
    if (face == _kDesk || placing.face != face || _placeDragging) return null;
    if (_flyAnim.isAnimating || _modeAnim.isAnimating || _lapping) return null;
    final piece = _pieceById(placing.pieceId);
    if (piece == null) return null;
    final placed = placedPiece(piece, placing);
    final plane = _facePlane(
      model,
      face,
    ).lifted(model.outwardSides[face] * _kPaperLift);
    Offset? screen(Offset point) =>
        _camera.camera.projectToScreen(plane.world(point), _viewport);
    final pivot = _turnPivot(placed);
    final center = screen(pivot);
    final alongX = screen(pivot + const Offset(1, 0));
    final alongY = screen(pivot + const Offset(0, 1));
    if (center == null || alongX == null || alongY == null) return null;
    final corners = [for (final point in placed.vertices) ?screen(point)];
    if (corners.isEmpty) return null;
    final safe = Rect.fromLTRB(
      _kGimbalInset.left,
      _kGimbalInset.top,
      _viewport.width - _kGimbalInset.right - (_inventoryShown ? 132 : 0),
      _viewport.height - _kGimbalInset.bottom,
    );
    if (safe.width < 80 || safe.height < 80) return null;
    var reach = 0.0;
    for (final corner in corners) {
      reach = math.max(reach, (corner - center).distance);
    }
    if (_gimbalPiece == placing.pieceId) {
      final ex = alongX - center;
      final ey = alongY - center;
      final radius = math.min(
        (reach + 18).clamp(56.0, 220.0),
        math.min(safe.width, safe.height) / 2 - 36,
      );
      return RotationGizmo(
        key: const Key('grid-place-gimbal'),
        center: Offset(
          center.dx.clamp(safe.left + radius, safe.right - radius),
          center.dy.clamp(safe.top + radius, safe.bottom - radius),
        ),
        rotationDeg: placing.turns * 90.0,
        objectName: 'Paper',
        screenRefAngle: math.atan2(ex.dy, ex.dx),
        rotationSign: ex.dx * ey.dy - ex.dy * ey.dx < 0 ? -1 : 1,
        ringRadius: radius,
        snapDegrees: 90,
        tickCount: 4,
        onRotationChanged: (deg) => _turnPlacingTo((deg / 90).round() % 4),
        onDismiss: () => setState(() => _gimbalPiece = null),
      );
    }
    const icon = 34.0;
    final box = pointBounds(corners);
    final visible = box.intersect(safe);
    final Offset at;
    if (visible.width <= 0 || visible.height <= 0) {
      return null;
    } else if (visible == box) {
      at = Offset(box.right + 6, box.top - icon - 6);
    } else {
      at = Offset(visible.right - icon - 6, visible.top + 6);
    }
    final clamped = Offset(
      at.dx.clamp(safe.left, safe.right - icon),
      at.dy.clamp(safe.top, safe.bottom - icon),
    );
    return Stack(
      children: [
        Positioned(
          left: clamped.dx,
          top: clamped.dy,
          child: GestureDetector(
            key: const Key('grid-place-rotate'),
            onTap: () => setState(() => _gimbalPiece = placing.pieceId),
            child: Container(
              width: icon,
              height: icon,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: 0.8),
                border: Border.all(color: Colors.white54, width: 1.5),
              ),
              child: const Icon(
                Icons.rotate_right,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _onWrapStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    final island = _wrapIsland;
    setState(() => _wrapIsland = null);
    if (_modelComplete) unawaited(fmHapticSmallClick());
    if (island != null) _beginLap(island);
  }

  bool get _lapping => _lapAnim.isAnimating;

  /// Backs out past the model framing, along the current view with its tilt
  /// held in range, then turns once around the model.
  void _beginLap(int island) {
    final model = _model;
    if (model == null || !_inModel || _modeAnim.isAnimating) return;
    if (_flyAnim.isAnimating) _flyAnim.stop();
    _leaveFocus(fly: false);
    final n = _camera.viewDirection;
    _lapTurn = math.atan2(n.y, n.x);
    _lapTilt = math
        .asin(n.z.clamp(-1.0, 1.0))
        .clamp(_kLapTiltMin, _kLapTiltMax);
    final framing = _modelFraming(model);
    _camera.beginFly(
      CameraPose(
        lookAt: framing.lookAt,
        lookAtZ: framing.lookAtZ,
        halfHeight: math.max(
          framing.halfHeight * _kBackOutMargin,
          _camera.framedHalfHeightMm,
        ),
      ).withAngles(
        _camera.anglesAlong(
          _turntableDirection(_lapTurn, _lapTilt),
          up: _modelUp,
        ),
      ),
    );
    _lapIsland = island;
    _lapBackedOut = false;
    _setPreselect(null);
    _lapAnim.forward(from: 0);
  }

  void _onLapTick() {
    final split =
        _kBackOutDuration.inMicroseconds /
        (_kBackOutDuration + _kLapDuration).inMicroseconds;
    final t = _lapAnim.value;
    if (t < split) {
      _camera.setFly(Curves.easeOutCubic.transform(t / split));
      return;
    }
    if (!_lapBackedOut) {
      _camera.setFly(1);
      _lapBackedOut = true;
    }
    final s = Curves.easeInOutCubic.transform((t - split) / (1 - split));
    _camera.orbitTo(
      _turntableDirection(_lapTurn + 2 * math.pi * s, _lapTilt),
      up: _modelUp,
    );
  }

  void _onLapStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    final island = _lapIsland;
    _lapIsland = null;
    if (!mounted) return;
    _updatePreselect();
    if (island == null || !_scoredIslands.add(island)) return;
    setState(() => _collectionScore += _kWrapPoints);
    _scorePop.forward(from: 0);
    unawaited(fmHapticSmallClick());
  }

  void _stopLap() {
    if (_lapAnim.isAnimating) _lapAnim.stop();
    _lapIsland = null;
  }

  /// Takes back the piece in hand or the last laid piece, into the inventory.
  void _undoModel() {
    final placing = _placing;
    if (placing != null) {
      setState(() {
        _placing = null;
        _restow(placing.pieceId);
      });
      return;
    }
    if (_placements.isEmpty) return;
    if (_wrapAnim.isAnimating) _wrapAnim.stop();
    if (_lapping) {
      _stopLap();
      _updatePreselect();
    }
    setState(() {
      _restow(_placements.removeLast().pieceId);
      _wrapIsland = null;
    });
  }

  void _restow(String id) {
    if (_offDesk.containsKey(id) && !_stowed.contains(id)) _stowed.add(id);
  }

  void _modelScaleStart(ScaleStartDetails details) {
    _gestureDown = details.localFocalPoint;
    _lastFocal = details.localFocalPoint;
    _moved = 0;
    _gestureScale = 1;
    _placeDragging = false;
    _planeGrab = null;
    _viewGrab = null;
    _deskDragId = null;
    _dragNudged = false;
    final model = _model;
    final face = _focusFace;
    if (model == null || face == null) return;
    if (details.pointerCount != 1 || _modeAnim.isAnimating || _lapping) return;
    final down = _pointerDownAt ?? details.localFocalPoint;
    final grab = _planeHit(_planeOf(model, face), down)?.at;
    if (grab == null) return;
    if (_panButton) {
      _planeGrab = grab;
      return;
    }
    if (face == _kDesk) {
      final index = _deskPieceAt(model, down);
      if (index == null) {
        _planeGrab = grab;
        return;
      }
      final piece = _sheet.pieces[index];
      _deskDragId = piece.id;
      _deskGrab = grab;
      _deskGrabFrom = piece.separation;
      return;
    }
    var placing = _placing;
    final piece = placing == null ? null : _pieceById(placing.pieceId);
    final onHand =
        placing != null &&
        piece != null &&
        ownsPoint(placedPiece(piece, placing).vertices, grab);
    if (!onHand) {
      final loose = _looseAt(model, face, down);
      if (loose != null) {
        _hold(face, loose);
        placing = loose;
      } else {
        _planeGrab = grab;
        return;
      }
    }
    _placeGrab = grab;
    _placeGrabOffset = placing.offset;
    _placeDragging = true;
  }

  void _modelScaleUpdate(ScaleUpdateDetails details) {
    final local = details.localFocalPoint;
    final delta = local - (_lastFocal ?? local);
    _lastFocal = local;
    _moved += delta.distance;
    final model = _model;
    if (model == null || _modeAnim.isAnimating || _lapping) return;
    if (details.pointerCount >= 2) {
      _placeDragging = false;
      _planeGrab = null;
      _deskDragId = null;
      _setOverInventory(false);
      if (_gestureScale > 0) {
        _camera.zoomByScale(details.scale / _gestureScale);
      }
      _gestureScale = details.scale;
      if (!_flyAnim.isAnimating) _panView(model, local, delta);
      return;
    }
    if (_panButton && _focusFace == null) {
      if (!_flyAnim.isAnimating) _panView(model, local, delta);
      return;
    }
    if (_placeDragging) {
      _dragPlacing(model, local);
      return;
    }
    if (_deskDragId != null) {
      _dragDesk(local);
      return;
    }
    if (_flyAnim.isAnimating) return;
    final face = _focusFace;
    final grab = _planeGrab;
    if (face != null) {
      if (grab != null) _panOnPlane(model, face, grab, local);
      return;
    }
    _turntable(-delta.dx * 0.008, delta.dy * 0.008);
  }

  /// How far the look-at point may wander from the model: past the model and
  /// across the desk.
  double _panLimit(FoldedModel model) =>
      math.max(model.radius * 2, _deskRect.longestSide);

  /// Slides the camera in the plane facing it, through [_viewGrab], so that
  /// point stays exactly under [screen]. The grab is picked where the pan
  /// began: the press for a mouse button, else the fingers' middle.
  void _panView(FoldedModel model, Offset screen, Offset delta) {
    final from = _panButton ? _pointerDownAt : null;
    final grab = _viewGrab ??= _viewGrabAt(model, from ?? screen - delta);
    final ray = _camera.camera.unprojectRay(screen, _viewport);
    if (ray == null) return;
    final eye = _camera.camera.position;
    final forward = (_camera.target - eye).normalized();
    final depth = (grab - eye).dot(forward);
    final along = ray.direction.dot(forward);
    if (depth <= _camera.camera.near || along < 1e-6) return;
    final under = eye + ray.direction * (depth / along);
    _camera.shiftTarget(
      grab - under,
      anchor: model.center,
      limit: _panLimit(model),
    );
  }

  /// The point a view pan from [screen] holds: the nearest model face or desk
  /// point under it, else the middle of the nearest face in view, else the
  /// look-at point.
  Vector3 _viewGrabAt(FoldedModel model, Offset screen) {
    final ray = _camera.camera.unprojectRay(screen, _viewport);
    if (ray != null) {
      var best = pickFace(model, ray.origin, ray.direction)?.distance;
      final desk = _planeHit(CraftPlane.sheet, screen);
      if (desk != null &&
          _deskRect.contains(desk.at) &&
          (best == null || desk.distance < best)) {
        best = desk.distance;
      }
      if (best != null) return ray.pointAt(best);
    }
    final eye = _camera.camera.position;
    final forward = (_camera.target - eye).normalized();
    final view = Offset.zero & _viewport;
    Vector3? nearest;
    var nearestDepth = double.infinity;
    for (var i = 0; i < model.faces.length; i++) {
      final center = model.worldCenter(i);
      final depth = (center - eye).dot(forward);
      if (depth <= _camera.camera.near || depth >= nearestDepth) continue;
      final at = _camera.camera.projectToScreen(center, _viewport);
      if (at == null || !view.contains(at)) continue;
      nearest = center;
      nearestDepth = depth;
    }
    return nearest ?? _camera.target;
  }

  /// Slides the camera along [face] so [grab] stays under the finger.
  void _panOnPlane(FoldedModel model, int face, Offset grab, Offset screen) {
    final plane = _planeOf(model, face);
    final at = _planeHit(plane, screen)?.at;
    if (at == null) return;
    _camera.shiftTarget(
      plane.world(grab) - plane.world(at),
      anchor: model.center,
      limit: _panLimit(model),
    );
  }

  /// Slides desk paper in desk focus, snapped like the flat view's drag.
  void _dragDesk(Offset screen) {
    final id = _deskDragId;
    final grab = _deskGrab;
    final at = _planeHit(CraftPlane.sheet, screen)?.at;
    if (id == null || grab == null || at == null) return;
    final index = _sheet.pieces.indexWhere((piece) => piece.id == id);
    if (index < 0) return;
    if (!_dragNudged) {
      if (_moved < 6) return;
      _pushUndo();
      _dragNudged = true;
    }
    _setOverInventory(_overInventoryAt(screen));
    final next = _snapOffset(_deskGrabFrom + (at - grab));
    final piece = _sheet.pieces[index];
    if (next == piece.separation) return;
    final pieces = [..._sheet.pieces];
    pieces[index] = piece.copyWith(separation: next);
    setState(() => _sheet = _sheet.copyWith(pieces: pieces));
    unawaited(fmHapticSmallClick());
  }

  void _dragPlacing(FoldedModel model, Offset screen) {
    final placing = _placing;
    final grab = _placeGrab;
    if (placing == null || grab == null) return;
    final at = _camera.planePointOn(
      _facePlane(model, placing.face),
      screen,
      _viewport,
    );
    if (at == null) return;
    final next = placing.movedTo(
      _placeGrabOffset + (at - grab),
      _step.gridSpacing,
    );
    if (next == placing) return;
    setState(() => _placing = next);
    unawaited(fmHapticSmallClick());
  }

  void _modelScaleEnd(ScaleEndDetails details) {
    final dragged = _placeDragging && _moved > 4;
    if (_placeDragging) setState(() => _placeDragging = false);
    _placeGrab = null;
    _planeGrab = null;
    final deskId = _deskDragId;
    final stow = _overInventory && _dragNudged;
    _deskDragId = null;
    _setOverInventory(false);
    if (dragged) {
      _settlePlacing();
      return;
    }
    if (deskId != null && _dragNudged) {
      _dragNudged = false;
      if (stow) _stow(deskId, undo: false);
      return;
    }
    if (_moved > 12 || details.pointerCount >= 2 || _panButton) return;
    final at = _lastFocal ?? _gestureDown;
    if (at == null) return;
    final now = DateTime.now();
    final last = _lastTapTime;
    final lastAt = _lastTapAt;
    if (last != null &&
        lastAt != null &&
        now.difference(last) <= _kDoubleTap &&
        (at - lastAt).distance <= _kDoubleTapSlop) {
      _lastTapTime = null;
      _onModelDoubleTap(at);
      return;
    }
    _lastTapTime = now;
    _lastTapAt = at;
    _onModelTap(at);
  }

  /// A tap on paper laid on the preselected face picks it up and focuses the
  /// face. On the preselected desk, a tap on desk paper focuses the desk.
  void _onModelTap(Offset screen) {
    final model = _model;
    final face = _targetFace;
    if (model == null || face == null || _modeAnim.isAnimating || _lapping) {
      return;
    }
    if (face == _kDesk) {
      if (_focusFace == null && _deskPieceAt(model, screen) != null) {
        _enterFocus(_kDesk);
      }
      return;
    }
    final loose = _looseAt(model, face, screen);
    if (loose != null) _hold(face, loose);
  }

  /// A double-tap on grey desk paper focuses the desk. Once a plane is
  /// focused, a double-tap on its paper goes on to crafting it, as
  /// [_focusCamera] does. Anywhere off the focused face and its paper ends
  /// focus.
  void _onModelDoubleTap(Offset screen) {
    final model = _model;
    if (model == null || _modeAnim.isAnimating || _lapping) return;
    if (_onFocusedPaper(model, screen)) {
      _focusCamera();
      return;
    }
    if (_onFocusedWork(model, screen)) return;
    if (_deskPieceAt(model, screen) != null) {
      _enterFocus(_kDesk);
      return;
    }
    _leaveFocus();
  }

  /// 1 with the desk paper drawn as paper, toward 0 as it greys in 3D.
  double get _deskShown => math.max(1 - _modelness, _deskAnim.value);

  /// Desk paper as drawn: grey and faint in 3D unless the desk is focused,
  /// plus the inventory piece being dropped on it.
  PapercutSheet _tableSheet() {
    final drop = _dropping;
    final dropped = drop == null || drop.face != _kDesk
        ? null
        : _offDesk[drop.pieceId]?.copyWith(separation: drop.offset);
    final shown = _deskShown;
    if (dropped == null && shown >= 1) return _sheet;
    PapercutPiece tint(PapercutPiece piece) => shown >= 1
        ? piece
        : piece.copyWith(
            color: Color.lerp(_kDeskGrey, piece.color, shown),
            backColor: Color.lerp(_kDeskGrey, piece.backColor, shown),
          );
    return _sheet.copyWith(
      pieces: [
        for (final piece in _sheet.pieces) tint(piece),
        if (dropped != null) tint(dropped),
      ],
    );
  }

  ModelPainter _modelPainter(FoldedModel model) {
    final paperPoses = <int, Matrix4>{};
    final paperColors = <int, Color>{};
    final glow = <int, double>{};
    for (final entry in _wrapped.entries) {
      final placement = entry.value;
      final piece = _pieceById(placement.pieceId);
      final wrapping = entry.key == _wrapIsland && _wrapAnim.isAnimating;
      final t = wrapping
          ? Curves.easeInOutCubic.transform(_wrapAnim.value)
          : 1.0;
      final poses = wrapPose(model, placement.face, t);
      paperPoses.addAll(poses);
      for (final face in poses.keys) {
        paperColors[face] = piece?.color ?? kPapercutYellow;
      }
      if (wrapping) glow[placement.face] = 1 - _wrapAnim.value * 0.6;
    }
    final placing = _placing;
    if (placing != null && _matches(placing)) {
      glow[placing.face] = 0.6 + 0.4 * _flash.value;
    }
    final onFace = _facePlacement;
    final loose = <LoosePaper>[];
    for (final placement in [
      ..._placements,
      if (placing != null && !identical(placing, onFace?.$2)) placing,
    ]) {
      if (_matches(placement) || placement.pieceId == _dropping?.pieceId) {
        continue;
      }
      final piece = _pieceById(placement.pieceId);
      if (piece == null) continue;
      loose.add(_loosePaper(model, piece, placement));
    }
    return ModelPainter(
      camera: _camera,
      model: model,
      decals: _decals,
      paperPoses: paperPoses,
      paperColors: paperColors,
      loose: loose,
      highlight: _preselectFill.value,
      desk: _deskRect,
      deskHighlight: _preselectFill.value[_kDesk] ?? 0,
      glow: glow,
      complete: _modelComplete ? 0.55 + 0.45 * _flash.value : 0,
    );
  }

  LoosePaper _loosePaper(
    FoldedModel model,
    PapercutPiece piece,
    PiecePlacement placement,
  ) {
    final plane = _facePlane(
      model,
      placement.face,
    ).lifted(model.outwardSides[placement.face] * _kPaperLift);
    Vector3 world(Offset point) => plane.world(placement.apply(point));
    final ink = <(Vector3, Vector3)>[];
    for (var i = 0; i < _step.polygons.length; i++) {
      final ring = _step.polygons[i];
      for (var e = 0; e < _step.edgeCountOf(i); e++) {
        final a = ring[e];
        final b = ring[(e + 1) % ring.length];
        if (!ownsPoint(piece.vertices, Offset.lerp(a, b, 0.5)!)) continue;
        ink.add((world(a), world(b)));
      }
    }
    return LoosePaper(
      ring: [for (final point in piece.vertices) world(point)],
      color: piece.color,
      ink: ink,
      plane: plane,
      decals: placedDecals(_decalsOn(piece), placement),
    );
  }

  /// Decals [piece] carries, in level coordinates.
  List<Decal> _decalsOn(PapercutPiece piece) => [
    for (final decal in _decals)
      if (markOwner(decal.center, [piece]) != null) decal,
  ];

  /// The face drawn like the crafting sheet, with the paper on it: the drop
  /// preview, else the piece in hand.
  (int, PiecePlacement?)? get _facePlacement {
    if (_flyAnim.isAnimating) return null;
    final dropping = _dropping;
    if (dropping != null && dropping.face != _kDesk) {
      return (dropping.face, dropping);
    }
    final face = _focusFace;
    if (face == null || face == _kDesk) return null;
    return (face, _placing);
  }

  /// Dots around the face, a few cells past its outline.
  Rect _faceGridBounds(FoldedModel model, int face) =>
      pointBounds(model.faces[face].outline).inflate(_step.gridSpacing * 4);

  /// The focused face drawn like the crafting sheet: dots, and the paper on
  /// it with its ink and marks.
  GridPuzzlePainter? _facePainter(FoldedModel model) {
    final shown = _facePlacement;
    if (shown == null) return null;
    final (face, placing) = shown;
    final plane = _facePlane(
      model,
      face,
    ).lifted(model.outwardSides[face] * _kPaperLift);
    final piece = placing == null ? null : _pieceById(placing.pieceId);
    if (placing == null || piece == null) {
      return GridPuzzlePainter(
        camera: _camera,
        step: _step.copyWith(polygons: const [], edgeStyles: const []),
        sheet: PapercutSheet.empty(),
        march: null,
        flash: 0,
        rulerX: null,
        showRuler: false,
        selected: const {},
        plane: plane,
        gridOpacity: 0.45,
        gridBounds: _faceGridBounds(model, face),
      );
    }
    return GridPuzzlePainter(
      camera: _camera,
      step: placedStep(_step, placing),
      sheet: PapercutSheet(pieces: [placedPiece(piece, placing)]),
      march: null,
      flash: 0,
      rulerX: null,
      showRuler: false,
      selected: const {},
      blueprintColor: kBlueprintInk,
      plane: plane,
      gridOpacity: 0.45,
      gridBounds: _faceGridBounds(model, face),
      decals: placedDecals(_decalsOn(piece), placing),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _keys,
      autofocus: true,
      onKeyEvent: _onKey,
      child: FmScreen(
        backgroundColor: kPapercutBackground,
        overlays: [
          FmDevBackButton(
            label: widget.returnToEditor ? '← Editor' : '← Dev',
            onPressed: widget.returnToEditor ? () => context.pop() : null,
          ),
        ],
        background: LayoutBuilder(
          builder: (context, constraints) {
            _viewport = Size(constraints.maxWidth, constraints.maxHeight);
            if (_needsFrame && _viewport.width > 2) {
              _needsFrame = false;
              _frame();
              _rememberStart();
            }
            return Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: DragTarget<String>(
                    key: _dropKey,
                    onWillAcceptWithDetails: (_) =>
                        _model != null &&
                        !_modeAnim.isAnimating &&
                        !_lapping &&
                        _paperTarget != null,
                    onMove: _onDropMove,
                    onLeave: _onDropLeave,
                    onAcceptWithDetails: _onDrop,
                    builder: (context, _, _) => Listener(
                      onPointerSignal: (event) {
                        if (_fixedToolCamera ||
                            _advancing ||
                            _collectionWon ||
                            event is! PointerScrollEvent ||
                            event.scrollDelta.dy == 0) {
                          return;
                        }
                        _camera.zoomByScale(
                          math.exp(-event.scrollDelta.dy * 0.002),
                        );
                        if (_canvasPointers > 0 || _pointerDown) _noteZoom();
                      },
                      child: GestureDetector(
                        key: const Key('grid-puzzle-canvas'),
                        behavior: HitTestBehavior.opaque,
                        onScaleStart: _onScaleStart,
                        onScaleUpdate: _onScaleUpdate,
                        onScaleEnd: _onScaleEnd,
                        child: Listener(
                          behavior: HitTestBehavior.translucent,
                          onPointerDown: _onCanvasPointerDown,
                          onPointerUp: _onCanvasPointerUp,
                          onPointerCancel: _onCanvasPointerCancel,
                          child: AnimatedBuilder(
                            animation: Listenable.merge([
                              _flash,
                              _failAnim,
                              _celebrateAnim,
                              _advanceAnim,
                              _flightAnim,
                              _foldAnim,
                              _creaseAnim,
                              _foldSettle,
                              _fadeAnim,
                              _tallyAnim,
                              _modeAnim,
                              _deskAnim,
                            ]),
                            builder: (context, _) {
                              final aim = _inModel || _modeAnim.value > 0
                                  ? null
                                  : _aimWorld();
                              final ghosts = _ruledGhosts(_displayGhosts(aim));
                              final guide = _folderGuide(aim);
                              final model = _model;
                              final modelness = _modelness;
                              return CustomPaint(
                                painter: GridPuzzlePainter(
                                  camera: _camera,
                                  step: _step,
                                  sheet: _tableSheet(),
                                  gridOpacity: math.max(
                                    1 - modelness,
                                    0.45 * _deskAnim.value,
                                  ),
                                  gridBounds: modelness > 0 ? _deskRect : null,
                                  sheetOpacity:
                                      _kDeskOpacity +
                                      (1 - _kDeskOpacity) * _deskShown,
                                  decals: model == null ? const [] : _decals,
                                  march: null,
                                  flash: _flash.value,
                                  rulerX: aim == null
                                      ? _rulerX
                                      : _snap(
                                          _toModel(aim).dx,
                                          _step.gridSpacing,
                                        ),
                                  showRuler: false,
                                  selected: const {},
                                  pickedPiece: _tool == _GridTool.select
                                      ? (_dragPiece ?? _picked)
                                      : null,
                                  ghostCuts: ghosts.$1,
                                  blockedCuts: ghosts.$2,
                                  activeCut: _activeCut(),
                                  ghostSeparation: _ghostShift(aim),
                                  gatheredColors: _progress.collectedColors,
                                  nextNumber: _progress.nextNumber,
                                  failure: _failureCue,
                                  failureFlash: _failAnim.value,
                                  darkness: _step.permutation.darkness,
                                  lightOrigin: _tool == _GridTool.scissors
                                      ? _lightOrigin()
                                      : null,
                                  lightDirection: _tool == _GridTool.scissors
                                      ? _lightDirection()
                                      : null,
                                  lightThrow: _step.attachment.flashlightThrow,
                                  foldLine: _foldingMode
                                      ? _folderGuideDown?.drawn
                                      : guide?.drawn,
                                  unfoldLine: _unfoldCue(aim),
                                  punchCenters: _punchPreviewCenters(aim),
                                  punchRadius: _punchSize / 2,
                                  punchShape: _punchShape,
                                  punchBlocked: _punchPreviewBlocked(aim),
                                  foldBend: _foldBend,
                                  foldBendT: _shownBend,
                                  collisionLeft: _collisionLeft,
                                  celebrations: _celebrations,
                                  celebrateSeconds: _celebrateSeconds,
                                  clearedRings: _liberated,
                                  fadingIds: _fading,
                                  fadeOpacity: 1 - _fadeAnim.value,
                                  hiddenPieceIds: _tallyIds,
                                  progress: blueprintProgress(_step, _sheet),
                                ),
                                child:
                                    _incomingStep == null ||
                                        _incomingSheet == null
                                    ? const SizedBox.expand()
                                    : CustomPaint(
                                        painter: GridPuzzlePainter(
                                          camera: _camera,
                                          step: _incomingStep!,
                                          sheet: _incomingSheet!,
                                          march: null,
                                          flash: 0,
                                          rulerX: null,
                                          showRuler: false,
                                          selected: const {},
                                          drawGrid: false,
                                        ),
                                        child: const SizedBox.expand(),
                                      ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (_model case final model?
                    when _inModel || _modeAnim.value > 0)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedBuilder(
                        animation: Listenable.merge([
                          _modeAnim,
                          _flyAnim,
                          _wrapAnim,
                          _flash,
                          _preselectFill,
                        ]),
                        builder: (context, _) => Opacity(
                          opacity: _modelness,
                          child: CustomPaint(
                            key: const Key('grid-model-layer'),
                            painter: _modelPainter(model),
                            foregroundPainter: _facePainter(model),
                            child: const SizedBox.expand(),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (!_inModel)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedBuilder(
                        animation: _flightAnim,
                        builder: (context, _) {
                          return CustomPaint(
                            painter: ScissorGlyphPainter(
                              camera: _camera,
                              pose: _flight.pose(_flightAnim.value),
                              tool: _scissors,
                            ),
                            child: const SizedBox.expand(),
                          );
                        },
                      ),
                    ),
                  ),
                if (_foldingMode && _foldScreenAxis != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _FoldLevelPainter(
                          axis: _foldScreenAxis!,
                          signed: _foldSigned,
                          half: _kFoldBarHalf,
                        ),
                      ),
                    ),
                  ),
                if (_inModel ? _focusFace == null : !_fixedToolCamera)
                  const Positioned.fill(
                    child: IgnorePointer(child: ViewCrosshair()),
                  ),
                if (_inModel)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedOpacity(
                        key: const Key('grid-focus-frame'),
                        opacity: _focusFace == null ? 0 : 1,
                        duration: const Duration(milliseconds: 220),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.55),
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (_inModel)
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: _camera,
                      builder: (context, _) =>
                          _placeGimbal() ?? const SizedBox.shrink(),
                    ),
                  ),
                if (_tallying)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedBuilder(
                        animation: _tallyAnim,
                        builder: (context, _) {
                          final seconds =
                              _tallyAnim.value *
                              _kTallyDuration.inMilliseconds /
                              1000;
                          return CustomPaint(
                            painter: _ScrapTallyPainter(
                              cells: _tallyCells,
                              windows: _tallyWindows,
                              seconds: seconds,
                              style: _tallyStyle,
                              spacing: _step.gridSpacing,
                              project: _project,
                              target: _scoreCenter(context),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                if (_collectionWon)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'victory',
                              key: Key('grid-victory'),
                              style: TextStyle(
                                color: Color(0xFFFFFFFF),
                                fontSize: 56,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 6,
                                shadows: [
                                  Shadow(
                                    color: Color(0x99000000),
                                    blurRadius: 16,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _collectionName,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 18,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (_showTapDebug)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _TapDebugPainter(
                          centroid: _directionOrigin(),
                          tap: _debugTap,
                          side: _debugSide,
                          deadZone: _kCrosshairCutRadius,
                        ),
                      ),
                    ),
                  ),
                FmSafePositioned(top: 8, left: 8, right: 8, child: _topBar()),
                if (_devToolsOpen)
                  FmSafePositioned(
                    top: 196,
                    right: 12,
                    child: GridDevPanel(
                      showTapDebug: _showTapDebug,
                      onShowTapDebugChanged: (value) =>
                          setState(() => _showTapDebug = value),
                      tallyStyle: _tallyStyle,
                      onTallyStyleChanged: (style) =>
                          setState(() => _tallyStyle = style),
                      cameraFollowsTool: _cameraFollowsTool,
                      onCameraFollowsToolChanged: _setCameraFollowsTool,
                      cameraRotates: _cameraRotates,
                      onCameraRotatesChanged: _setCameraRotates,
                    ),
                  ),
                if (_model != null)
                  FmSafePositioned(
                    right: 8,
                    top: 210,
                    bottom: 72,
                    child: AnimatedSwitcher(
                      key: _inventoryKey,
                      duration: const Duration(milliseconds: 320),
                      reverseDuration: const Duration(milliseconds: 220),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      layoutBuilder: (current, previous) => Stack(
                        alignment: Alignment.centerRight,
                        children: [...previous, ?current],
                      ),
                      transitionBuilder: (child, animation) => SlideTransition(
                        position: Tween(
                          begin: const Offset(1.2, 0),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                      child: _inventoryShown
                          ? PieceInventory(
                              pieces: _inventory,
                              step: _step,
                              decals: _decals,
                              selectedId: _placing?.pieceId,
                              onPick: _pickPiece,
                              previewing: _dropShown,
                              accepting: _overInventory,
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                FmSafePositioned(
                  left: 0,
                  right: 0,
                  bottom: 8,
                  child: _inModel ? _modelBar() : _toolbar(),
                ),
                FmSafePositioned(left: 8, bottom: 8, child: _undoButton()),
              ],
            );
          },
        ),
      ),
    );
  }

  Offset? _lastFocal;
  Offset? _pointerDownAt;
  int _downButtons = 0;
  double _rollAnchor = 0;

  /// A right or middle mouse drag, which pans the 3D view instead of
  /// orbiting or moving paper.
  bool get _panButton =>
      _downButtons & (kSecondaryMouseButton | kMiddleMouseButton) != 0;

  void _onCanvasPointerDown(PointerDownEvent event) {
    _pointerDownAt = event.localPosition;
    _downButtons = event.buttons;
    _canvasPointers++;
    if (_canvasPointers >= 2) _noteZoom();
  }

  void _onCanvasPointerUp(PointerEvent event) {
    _canvasPointers = math.max(0, _canvasPointers - 1);
  }

  void _onCanvasPointerCancel(PointerEvent event) {
    _canvasPointers = math.max(0, _canvasPointers - 1);
    _noteZoom();
  }

  /// A zoom is in progress. The scale recognizer ends the one-finger gesture
  /// when a second pointer arrives, before any scale update, so this has to
  /// be recorded first or that end is taken as a press.
  void _noteZoom() {
    _zoomed = true;
    _cancelFoldHold();
    if (!_foldingMode) return;
    _foldSigned = 0;
    _releaseFoldingMode();
  }

  void _onScaleStart(ScaleStartDetails details) {
    if (_inModel || _modeAnim.isAnimating) {
      _modelScaleStart(details);
      return;
    }
    _gestureDown = details.localFocalPoint;
    _lastFocal = details.localFocalPoint;
    _rollAnchor = details.localFocalPoint.dx;
    _rollStart = _camera.roll;
    _moved = 0;
    _gestureScale = 1;
    _dragNudged = false;
    _dragSample = details.localFocalPoint;
    _dragFree = null;
    _dragPiece = null;
    _pointerDown = true;
    if (details.pointerCount >= 2) _noteZoom();
    _cancelFoldHold();
    if (!_zoomed &&
        _tool == _GridTool.folder &&
        !_foldAnim.isAnimating &&
        !_creaseAnim.isAnimating &&
        !_settlingFold &&
        !_foldingMode) {
      _folderGuideDown = _folderGuide(_aimWorld());
      _armFoldHold();
    } else if (!_foldingMode) {
      _folderGuideDown = null;
    }
    if (_tool != _GridTool.select || _cutting || _locked) return;
    final world = _camera.planePoint(details.localFocalPoint, _viewport);
    if (world == null) return;
    final index = _stacks.press(world, _sheet);
    if (index == null || index >= _sheet.pieces.length) return;
    if (_isCelebrating(_sheet.pieces[index].id)) return;
    _dragPiece = index;
    setState(() => _picked = _stacks.selected);
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_inModel || _modeAnim.isAnimating) {
      _modelScaleUpdate(details);
      return;
    }
    if (_advancing || _collectionWon) return;
    final local = details.localFocalPoint;
    final previous = _lastFocal ?? local;
    final delta = local - previous;
    _lastFocal = local;
    _moved += delta.distance;
    if (details.pointerCount >= 2 || (details.scale - 1).abs() > 0.004) {
      _noteZoom();
    }
    if (_foldingMode) {
      if (!_zoomed) _updateFoldPreview(local);
      return;
    }
    if (_fixedToolCamera) return;
    if (_rolling && details.pointerCount < 2) {
      if (_cutting || _fixedToolCamera) return;
      _camera.setRoll(_rollStart + (local.dx - _rollAnchor) * 0.01);
      _pinScissor();
      return;
    }
    if (details.pointerCount >= 2) {
      if (_gestureScale > 0) {
        _camera.zoomByScale(details.scale / _gestureScale);
      }
      _gestureScale = details.scale;
      _panBy(delta);
      return;
    }
    if (_dragPiece != null) {
      _dragSelected(local);
      return;
    }
    if (_foldHold != null) {
      final down = _gestureDown;
      if (down != null && (local - down).distance <= _kFoldHoldSlop) return;
      _cancelFoldHold();
    }
    if (_march != null && _tool == _GridTool.scissors) return;
    _panBy(delta);
  }

  /// A pan that ticks once each time the crosshair reaches a new grid point.
  void _panBy(Offset delta) {
    final before = _snapOffset(_camera.lookAt);
    _camera.panByScreen(delta, _viewport);
    if (_snapOffset(_camera.lookAt) == before) return;
    unawaited(fmHapticSmallClick());
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (_inModel || _modeAnim.isAnimating) {
      _pointerDown = false;
      _modelScaleEnd(details);
      return;
    }
    if (_failing) return;
    final nudged = _dragNudged;
    final dragged = _dragPiece;
    final stow = _overInventory;
    _setOverInventory(false);
    _dragPiece = null;
    _dragNudged = false;
    _dragFree = null;
    _pointerDown = false;
    if (stow && nudged && dragged != null && dragged < _sheet.pieces.length) {
      _cancelFoldHold();
      _stow(_sheet.pieces[dragged].id, undo: false);
      return;
    }
    _cancelFoldHold();
    final zoomed = _zoomed || details.pointerCount >= 2;
    if (zoomed) _zoomed = true;
    if (_canvasPointers == 0) _zoomed = false;
    if (zoomed) {
      if (_foldingMode) {
        _foldSigned = 0;
        _releaseFoldingMode();
      }
      if (_rolling) {
        _camera.setRoll(PapercutCamera.snapRoll(_camera.roll));
        _pinScissor();
      }
      return;
    }
    if (_rolling) {
      _camera.setRoll(PapercutCamera.snapRoll(_camera.roll));
      _pinScissor();
      return;
    }
    final down = _gestureDown;
    final end = _lastFocal;
    final net = down == null || end == null ? Offset.zero : end - down;
    final swiped = net.distance > 12;
    if (_tool == _GridTool.scissors && swiped && (_cutting || _directing)) {
      final side = swipeCutSide(net, deadZone: 12);
      if (side != null) _aimSeatedCut(_cutSide(side));
      return;
    }
    if (_tool == _GridTool.folder) {
      if (swiped) return;
      final world = _aimWorld();
      if (world == null) return;
      _onFolderPress(world);
      return;
    }
    if (swiped) return;
    if (_tool == _GridTool.select) {
      if (!nudged && _lastFocal != null) {
        final world = _camera.planePoint(_lastFocal!, _viewport);
        final index = world == null
            ? null
            : _stacks.tap(world, _sheet, DateTime.now());
        setState(() => _picked = index);
      }
      return;
    }
    if (_tool == _GridTool.scissors) {
      _noteTap(_lastFocal);
      if (_cutting) {
        _enqueueCut(_tapSide(_lastFocal));
        return;
      }
      if (_directing) {
        _chooseCut(_lastFocal);
        return;
      }
    }
    final world = _aimWorld();
    if (world == null) return;
    if (_tool == _GridTool.scissors) {
      _onScissorTap(world);
    } else if (_tool == _GridTool.holePunch) {
      _onPunch(world);
    }
  }

  void _dragSelected(Offset screen) {
    final index = _dragPiece;
    final from = _dragSample;
    if (index == null || from == null || index >= _sheet.pieces.length) return;
    if (!_dragNudged) {
      if (_moved < 12) return;
      _pushUndo();
      _dragNudged = true;
      _dragFree = _sheet.pieces[index].separation;
    }
    final start = _camera.planePoint(from, _viewport);
    final end = _camera.planePoint(screen, _viewport);
    _dragSample = screen;
    _setOverInventory(_model != null && _overInventoryAt(screen));
    if (start == null || end == null) return;
    final world = end - start;
    if (world == Offset.zero) return;
    final free = (_dragFree ?? _sheet.pieces[index].separation) + world;
    _dragFree = free;
    final snapped = _snapOffset(free);
    final pieces = [..._sheet.pieces];
    final piece = pieces[index];
    if (snapped == piece.separation) return;
    pieces[index] = piece.copyWith(separation: snapped);
    setState(() {
      _sheet = _sheet.copyWith(pieces: pieces);
    });
  }

  /// World point under the reticle. Panning slides the sheet under it, and
  /// the seated blade follows. A cut in progress does not use this point.
  Offset? _aimWorld() {
    if (_viewport.width < 2 || _viewport.height < 2) return null;
    return _camera.planePoint(
      Offset(_viewport.width / 2, _viewport.height / 2),
      _viewport,
    );
  }

  (Offset, Offset)? _cueSegment(Offset? aim) {
    if (_directing) {
      final from = _march?.position;
      final forward = _arrival();
      if (from == null || forward == null) return null;
      final cut = mostForwardCut(_forwardOptions(), forward);
      if (cut == null) return null;
      return (from, cut.end);
    }
    return _scissorGhost(aim);
  }

  PapercutPiece? _targetPiece(Offset? aim) {
    final blade = _bladePiece();
    if (blade != null) return blade;
    if (aim == null) return null;
    final edge = _nearestEdge(aim);
    if (edge == null) return null;
    return _sheet.pieces[edge.index];
  }

  Offset? _ghostShift(Offset? aim) => _targetPiece(aim)?.separation;

  (Offset, Offset)? _scissorGhost(Offset? aim) {
    if (_tool != _GridTool.scissors || _failing) return null;
    final edge = _march != null || aim == null || _entryGemsRemain
        ? null
        : _nearestEdge(aim);
    final gem = _march == null && aim != null && _entryGemsRemain
        ? _openGemNear(aim)
        : null;
    final from = _march?.position ?? gem ?? edge?.model;
    if (from == null) return null;
    final piece =
        _bladePiece() ?? (edge == null ? null : _sheet.pieces[edge.index]);
    final rings = _paperEdges(piece);
    final outlines = _bladeOutlines(piece);
    final aimed = nextOutlineHit(
      from: from,
      direction: _paperHeading(from, piece: piece, aim: aim),
      closed: outlines,
      open: [...openBlueprint(_step), ..._sheet.cutStrokes],
      skipCollinear: _skipPenciled,
    );
    if (aimed != null && !cutRidesBoundary(from, aimed, rings)) {
      return (from, aimed);
    }
    if (aimed == null || !cutRidesBoundary(from, aimed, rings)) return null;
    final inward = piece == null
        ? null
        : inwardOnRing(from, piece.vertices) ??
              _inwardOnHoles(from, piece.holes);
    if (inward == null) return null;
    final end = nextOutlineHit(
      from: from,
      direction: inward,
      closed: outlines,
      open: [...openBlueprint(_step), ..._sheet.cutStrokes],
      skipCollinear: _skipPenciled,
    );
    if (end == null || cutRidesBoundary(from, end, rings)) return null;
    return (from, end);
  }

  List<List<Offset>> _paperEdges(PapercutPiece? piece) {
    if (piece != null) return [piece.vertices, ...piece.holes];
    return [
      for (final piece in _sheet.pieces) ...[piece.vertices, ...piece.holes],
    ];
  }

  Offset? _inwardOnHoles(Offset point, List<List<Offset>> holes) {
    for (final hole in holes) {
      final direction = inwardOnRing(point, hole);
      if (direction != null) return direction;
    }
    return null;
  }

  (List<(Offset, Offset)>, List<(Offset, Offset)>) _ruledGhosts(
    List<(Offset, Offset)> ghosts,
  ) {
    if (_liveRules.isEmpty) return (ghosts, const []);
    final open = <(Offset, Offset)>[];
    final blocked = <(Offset, Offset)>[];
    for (final ghost in ghosts) {
      if (_liveRules.allows(
        ghost.$1,
        ghost.$2,
        _progress,
        paper: _step.paper,
      )) {
        open.add(ghost);
      } else {
        blocked.add(ghost);
      }
    }
    return (open, blocked);
  }

  /// Model-space corners of the cut that has not left the paper yet.
  ///
  /// Finished strokes stay in the march path. The blade tip lengthens the
  /// last one while it travels. The path is empty once the blade leaves,
  /// because that stroke does not end where another cut can go forward.
  List<Offset> _activeCut() {
    final march = _march;
    if (march == null || _tool != _GridTool.scissors) return const [];
    Offset? tip;
    if (_flight.phase == ToolFlightPhase.cut) {
      final shift = _bladePiece()?.separation ?? Offset.zero;
      tip = _flight.pose(_flightAnim.value).tip - shift;
    }
    return activeCutPoints(march.path, tip: tip);
  }

  List<(Offset, Offset)> _displayGhosts(Offset? aim) {
    if (_tool != _GridTool.scissors) return const [];
    if (_flight.phase == ToolFlightPhase.cut) return const [];
    if (_directing) {
      final from = _march?.position;
      if (from == null) return const [];
      return [for (final cut in _forwardOptions()) (from, cut.end)];
    }
    final ghost = _scissorGhost(aim);
    if (ghost == null) return const [];
    return [ghost];
  }

  String? _ruleStatus() {
    final rules = _step.rules;
    if (rules.isEmpty &&
        _step.tools == null &&
        _step.scissorLengthBudget == null) {
      return null;
    }
    final parts = <String>[];
    if (rules.maxExits != null) {
      parts.add('exits ${_progress.exitsUsed}/${rules.maxExits}');
    }
    if (rules.maxLength != null || _step.scissorLengthBudget != null) {
      final cap = _step.scissorLengthBudget ?? rules.maxLength!;
      parts.add(
        'length ${_progress.lengthUsed.toStringAsFixed(0)}/${cap.toStringAsFixed(0)}',
      );
    }
    if (rules.numbers.isNotEmpty) parts.add('next ${_progress.nextNumber}');
    final color = _progress.openColor;
    if (color != null && color >= 0 && color < kRuleColorNames.length) {
      parts.add(kRuleColorNames[color]);
    }
    if (rules.seams.isNotEmpty) {
      parts.add('seams ${_progress.severedSeams.length}/${rules.seams.length}');
    }
    if (rules.colors.isNotEmpty || rules.numbers.isNotEmpty) {
      final spentNumbers = rules.numbers
          .where((mark) => mark.number < _progress.nextNumber)
          .length;
      final got = _progress.collectedColors.length + spentNumbers;
      final total = rules.colors.length + rules.numbers.length;
      if (got < total) parts.add('gems $got/$total');
    }
    if (collectiblesCleared(rules, _progress)) parts.add('cleared');
    final filter = _step.tools;
    if (filter != null && filter.allows(CraftTool.folder)) {
      final cap = filter.budget(CraftTool.folder);
      parts.add(
        cap == null
            ? 'folds $_folderUses'
            : 'folds $_folderUses/${cap.toStringAsFixed(0)}',
      );
    }
    if (filter != null && filter.allows(CraftTool.holePunch)) {
      final cap = filter.budget(CraftTool.holePunch);
      parts.add(
        cap == null
            ? 'punches $_punchUses'
            : 'punches $_punchUses/${cap.toStringAsFixed(0)}',
      );
    }
    if (parts.isEmpty) return null;
    return parts.join('  ');
  }

  void _syncFlight() {
    final march = _march;
    _flight.presented = march == null || march.path.length <= 1;
    if (!mounted || _viewport.width < 2) return;
    if (_flight.phase == ToolFlightPhase.cut) return;
    final next = _splitAnim.isAnimating ? null : _cue();
    final duration = _flight.offer(
      next,
      t: _flightAnim.value,
      approach: _approachFor(next),
      follow: _turnAnim.isAnimating,
    );
    if (duration != null) _playFlight(duration);
  }

  ToolCue? _cue() {
    if (_tool != _GridTool.scissors) return null;
    final aim = _aimWorld();
    if (aim == null) return null;
    final ghost = _cueSegment(aim);
    if (ghost == null) return null;
    final shift = _targetPiece(aim)?.separation ?? Offset.zero;
    final anchor = ghost.$1 + shift;
    final end = ghost.$2 + shift;
    final delta = end - anchor;
    if (delta.distance < 1e-6) return null;
    return ToolCue(
      anchor: anchor,
      direction: delta / delta.distance,
      aim: aim,
      reach: _step.gridSpacing * 0.75,
    );
  }

  ScreenApproach? _approachFor(ToolCue? next) {
    final pose = _flight.pose(_flightAnim.value);
    final anchor = next?.anchor ?? pose.tip;
    final direction = next?.direction ?? pose.direction;
    final screen = _project(anchor);
    final ahead = _project(anchor + direction * 10);
    if (screen == null || ahead == null) return null;
    return approachFor(
      anchor: screen,
      heading: ahead - screen,
      viewport: _viewport,
    );
  }

  Offset? _project(Offset world) {
    if (_viewport.width < 2 || _viewport.height < 2) return null;
    return _camera.camera.projectToScreen(
      Vector3(world.dx, world.dy, 0),
      _viewport,
    );
  }

  /// Score widget center in the same space as [_project].
  Offset? _scoreCenter(BuildContext overlay) {
    final box = _scoreKey.currentContext?.findRenderObject() as RenderBox?;
    final host = overlay.findRenderObject() as RenderBox?;
    if (box == null || host == null || !box.hasSize || !host.hasSize) {
      return null;
    }
    return host.globalToLocal(box.localToGlobal(box.size.center(Offset.zero)));
  }

  void _playFlight(Duration duration) {
    void start() {
      if (!mounted) return;
      _flightAnim.duration = duration;
      _flightAnim.forward(from: 0);
      _startMeeting();
    }

    final phase = WidgetsBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => start());
      return;
    }
    start();
  }

  void _onFlightStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    final phase = _flight.phase;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _flight.phase != phase) return;
      switch (_flight.phase) {
        case ToolFlightPhase.cut:
          _endMeeting();
          final split = _commitMarch();
          if (split == true || _tool != _GridTool.scissors) _cutQueue.clear();
          if (split == false && _takeQueuedCut()) return;
          final cue = _cue();
          if (split == true || cue == null) {
            _playFlight(_flight.depart(1, _approachFor(null)));
            return;
          }
          _flight.seat(cue);
          _syncFlight();
        case ToolFlightPhase.arrive:
        case ToolFlightPhase.relocate:
          _flight.land();
          _syncFlight();
        case ToolFlightPhase.leave:
          _flight.land();
          _syncFlight();
        case ToolFlightPhase.hold:
        case ToolFlightPhase.absent:
          break;
      }
    });
  }

  void _onSplitStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _syncFlight();
  }

  Widget _topBar() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xF01A1A1A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(padding: const EdgeInsets.only(left: 76), child: _header()),
            Row(
              children: [
                _turnButton(clockwise: true),
                const Spacer(),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _activeRuleBadge(),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _compassButton(),
                        if (_model != null) _viewModeButton(),
                      ],
                    ),
                  ],
                ),
                const Spacer(),
                _turnButton(clockwise: false),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Collection score. A wrap pops it and floats its points below.
  Widget _score() {
    return AnimatedBuilder(
      animation: _scorePop,
      builder: (context, _) {
        final t = _scorePop.value;
        final popping = _scorePop.isAnimating;
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Transform.scale(
              scale: popping ? 1 + 0.35 * math.sin(math.pi * t) : 1,
              child: KeyedSubtree(
                key: const Key('grid-score'),
                child: Text(
                  '$_collectionScore',
                  key: _scoreKey,
                  style: TextStyle(
                    color: Color.lerp(
                      Colors.white,
                      kPreselectColor,
                      popping ? math.sin(math.pi * t) : 0,
                    ),
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            if (popping)
              Positioned(
                top: 30 + 14 * t,
                child: Opacity(
                  opacity: (1 - t).clamp(0.0, 1.0),
                  child: const Text(
                    '+$_kWrapPoints',
                    key: Key('grid-score-gain'),
                    style: TextStyle(
                      color: kPreselectColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _header() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _libraryButton(
                key: const Key('grid-collection-button'),
                label: 'Collection',
                name: _collectionName,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: _score(),
            ),
            Expanded(
              child: _libraryButton(
                key: const Key('grid-puzzle-button'),
                label: 'Puzzle',
                name: _blueprint.name,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            DevToolsButton(
              active: _devToolsOpen,
              onPressed: () => setState(() => _devToolsOpen = !_devToolsOpen),
            ),
            TextButton(onPressed: _clear, child: const Text('Clear')),
            TextButton(onPressed: _save, child: const Text('Save')),
          ],
        ),
        if (_ruleStatus() case final status?)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              status,
              key: const Key('grid-rule-status'),
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
      ],
    );
  }

  Widget _libraryButton({
    required Key key,
    required String label,
    required String name,
  }) {
    return TextButton(
      key: key,
      onPressed: _openLibrary,
      style: TextButton.styleFrom(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _toolbar() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_tool == _GridTool.holePunch) _punchBar(),
        if (_tool == _GridTool.folder)
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text(
              'Press to score a crease. Hold still, then drag the bubble past the marks to fold.',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        HudToolCarousel<_GridTool>(
          items: _carouselItems(),
          selected: _tool,
          onSelect: (tool) {
            _cancelFoldHold();
            if (_foldingMode && tool != _GridTool.folder) {
              _foldSigned = 0;
              _releaseFoldingMode();
            }
            final leavingScissors =
                _tool == _GridTool.scissors && tool != _GridTool.scissors;
            setState(() {
              if (tool == _GridTool.select && _tool != _GridTool.select) {
                _abandonOtherTools();
              }
              _tool = tool;
            });
            if (leavingScissors) {
              if (_rollNudge.isAnimating) _rollNudge.stop();
            } else if (!_cameraFollowsTool &&
                tool == _GridTool.scissors &&
                _march != null) {
              _lockToolCamera();
            }
            _syncFlight();
          },
        ),
      ],
    );
  }

  List<HudCarouselItem<_GridTool>> _carouselItems() {
    final items = <HudCarouselItem<_GridTool>>[
      HudCarouselItem(
        value: _GridTool.select,
        icon: Icons.near_me,
        label: 'Select',
        fill: CraftPalette.granite.fill,
      ),
    ];
    bool show(CraftTool tool) {
      final filter = _step.tools;
      return filter == null || filter.allows(tool);
    }

    if (show(CraftTool.scissors)) {
      items.add(
        HudCarouselItem(
          value: _GridTool.scissors,
          icon: Icons.content_cut,
          label: 'Scissors',
          fill: CraftPalette.scarlet.fill,
        ),
      );
    }
    if (show(CraftTool.folder)) {
      items.add(
        HudCarouselItem(
          value: _GridTool.folder,
          icon: Icons.flip,
          label: 'Folder',
          fill: CraftPalette.carmel.fill,
        ),
      );
    }
    if (show(CraftTool.holePunch)) {
      items.add(
        HudCarouselItem(
          value: _GridTool.holePunch,
          icon: Icons.circle_outlined,
          label: 'Hole punch',
          fill: CraftPalette.raspberry.fill,
        ),
      );
    }
    return items;
  }

  Widget _punchBar() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextButton(
            onPressed: () => setState(() {
              const shapes = PunchShape.values;
              _punchShape = shapes[(_punchShape.index + 1) % shapes.length];
            }),
            child: Text(
              _punchShape.name,
              style: const TextStyle(color: Colors.white),
            ),
          ),
          TextButton(
            onPressed: () => setState(() {
              final index = punchSizes.indexOf(_punchSize);
              _punchSize = punchSizes[(index + 1) % punchSizes.length];
            }),
            child: Text(
              _punchSize.toString(),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _viewModeButton() {
    return IconButton(
      key: const Key('grid-view-mode'),
      tooltip: _inModel ? 'Flat view' : '3D view',
      onPressed: _toggleMode,
      icon: Icon(
        _inModel ? Icons.grid_on : Icons.view_in_ar,
        color: _inModel ? const Color(0xFFFFD54F) : Colors.white,
      ),
    );
  }

  /// Bottom controls in 3D. Face focus adds the quarter turns and Back.
  Widget _modelBar() {
    Widget button({
      required Key key,
      required IconData icon,
      required String label,
      VoidCallback? onPressed,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xF01A1A1A),
            borderRadius: BorderRadius.circular(12),
          ),
          child: TextButton.icon(
            key: key,
            onPressed: onPressed,
            icon: Icon(
              icon,
              color: onPressed == null ? Colors.white24 : Colors.white,
            ),
            label: Text(
              label,
              style: TextStyle(
                color: onPressed == null ? Colors.white24 : Colors.white,
              ),
            ),
          ),
        ),
      );
    }

    final focused = _focusFace != null;
    final desk = _focusFace == _kDesk;
    final holding = _placing != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            _modelComplete
                ? 'Every piece is wrapped.'
                : desk
                ? 'Slide paper on the desk, or drag it right to stow it.'
                : focused
                ? (holding
                      ? 'Slide and turn the paper until the face glows.'
                      : 'Drag a paper piece onto the face.')
                : _preselect == _kDesk
                ? 'Double-tap desk paper to work on the desk.'
                : _preselect != null
                ? 'Drag a paper piece onto the highlighted face.'
                : 'Drag to orbit. Aim the reticle at a face.',
            key: const Key('grid-model-hint'),
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (focused) ...[
              button(
                key: const Key('grid-focus-back'),
                icon: Icons.arrow_back,
                label: 'Back',
                onPressed: _leaveFocus,
              ),
              button(
                key: const Key('grid-focus-camera'),
                icon: Icons.center_focus_strong,
                label: desk ? 'Craft' : 'Focus camera',
                onPressed: _focusCamera,
              ),
            ] else
              button(
                key: const Key('grid-frame-model'),
                icon: Icons.center_focus_strong,
                label: 'Frame model',
                onPressed: _frameModel,
              ),
          ],
        ),
      ],
    );
  }

  Widget _undoButton() {
    final enabled = _inModel
        ? _placing != null || _placements.isNotEmpty
        : !_locked && _undo.isNotEmpty;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xF01A1A1A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: IconButton(
        tooltip: 'Undo',
        onPressed: enabled ? (_inModel ? _undoModel : _undoLast) : null,
        icon: Icon(Icons.undo, color: enabled ? Colors.white : Colors.white24),
      ),
    );
  }

  Widget _turnButton({required bool clockwise}) {
    return IconButton(
      tooltip: clockwise ? 'Rotate clockwise' : 'Rotate counterclockwise',
      onPressed:
          _turnAnim.isAnimating || _splitAnim.isAnimating || _fixedToolCamera
          ? null
          : () => _rotatePiece(clockwise),
      icon: Icon(
        clockwise ? Icons.rotate_right : Icons.rotate_left,
        color: Colors.white,
      ),
    );
  }

  Widget _activeRuleBadge() {
    final cue = ruleCue(_step.rules, _progress);
    if (cue.isEmpty) return const SizedBox.shrink();
    return Row(
      key: const Key('grid-rule-badge'),
      mainAxisSize: MainAxisSize.min,
      children: [
        if (cue.color != null) _colorChip(cue.color!),
        if (cue.number != null) ...[
          if (cue.color != null) const SizedBox(width: 6),
          _numberChip(cue.number!),
        ],
        if (cue.link != null) ...[
          if (cue.color != null || cue.number != null) const SizedBox(width: 6),
          _linkChip(cue.link!),
        ],
        if (cue.seamsLeft != null) ...[
          if (cue.color != null || cue.number != null || cue.link != null)
            const SizedBox(width: 6),
          _seamChip(cue.seamsLeft!),
        ],
      ],
    );
  }

  Widget _colorChip(int color) {
    final ink = kRulePalette[color];
    return Container(
      key: const Key('grid-rule-badge-color'),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ink,
        border: Border.all(color: Colors.white, width: 1.6),
      ),
    );
  }

  Widget _numberChip(int number) {
    return Container(
      key: const Key('grid-rule-badge-number'),
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white, width: 1.2),
      ),
      child: Text(
        '$number',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _linkChip(int pair) {
    final ink = kRulePalette[pair.abs() % kRulePalette.length];
    return Container(
      key: const Key('grid-rule-badge-link'),
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ink,
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: Text(
        '$pair',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _seamChip(int left) {
    return Container(
      key: const Key('grid-rule-badge-seams'),
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: const Color(0xFFFF8A65), width: 1.4),
      ),
      child: Text(
        '$left',
        style: const TextStyle(color: Color(0xFFFF8A65), fontSize: 12),
      ),
    );
  }

  Widget _compassButton() {
    return IconButton(
      key: const Key('grid-compass'),
      tooltip: 'Free rotate',
      onPressed: () => setState(() => _rolling = !_rolling),
      icon: Icon(
        Icons.explore,
        color: _rolling ? const Color(0xFFFFD54F) : Colors.white,
      ),
    );
  }
}

/// Orange markers for the last click and the crosshair, with the delta labeled.
class _TapDebugPainter extends CustomPainter {
  _TapDebugPainter({
    required this.centroid,
    required this.tap,
    required this.side,
    required this.deadZone,
  });

  final Offset centroid;
  final Offset? tap;
  final String side;
  final double deadZone;

  static const _orange = Color(0xFFFF9800);

  @override
  void paint(Canvas canvas, Size size) {
    final zone = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = _orange.withValues(alpha: 0.7);
    canvas.drawRect(
      Rect.fromCenter(
        center: centroid,
        width: deadZone * 2,
        height: deadZone * 2,
      ),
      zone,
    );
    _dot(canvas, centroid);
    _label(canvas, centroid + const Offset(12, -28), _xy('centroid', centroid));

    final click = tap;
    if (click == null) return;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = _orange;
    canvas.drawLine(centroid, click, line);
    _dot(canvas, click);
    final delta = click - centroid;
    _label(canvas, click + const Offset(12, 8), _xy('click', click));
    _label(
      canvas,
      Offset.lerp(centroid, click, 0.5)! + const Offset(12, -8),
      'dx ${delta.dx.toStringAsFixed(0)}   dy ${delta.dy.toStringAsFixed(0)}\n$side',
    );
  }

  void _dot(Canvas canvas, Offset point) {
    canvas.drawCircle(point, 6, Paint()..color = _orange);
    canvas.drawCircle(
      point,
      6,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = const Color(0xFF1A1A1A),
    );
  }

  String _xy(String name, Offset point) =>
      '$name\n${point.dx.toStringAsFixed(0)}, ${point.dy.toStringAsFixed(0)}';

  void _label(Canvas canvas, Offset at, String text) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: _orange,
          fontSize: 12,
          height: 1.25,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, at);
  }

  @override
  bool shouldRepaint(covariant _TapDebugPainter oldDelegate) {
    return oldDelegate.centroid != centroid ||
        oldDelegate.tap != tap ||
        oldDelegate.side != side ||
        oldDelegate.deadZone != deadZone;
  }
}

/// Leftover paper leaving as unit cells. Drawn in screen space.
class _ScrapTallyPainter extends CustomPainter {
  _ScrapTallyPainter({
    required this.cells,
    required this.windows,
    required this.seconds,
    required this.style,
    required this.spacing,
    required this.project,
    required this.target,
  });

  final List<Offset> cells;
  final List<CellWindow> windows;
  final double seconds;
  final ScrapTallyStyle style;
  final double spacing;
  final Offset? Function(Offset world) project;
  final Offset? target;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFFFFF3B0);
    final fallback = Offset(size.width / 2, 28);
    for (var i = 0; i < cells.length && i < windows.length; i++) {
      final motion = cellMotion(
        style: style,
        window: windows[i],
        seconds: seconds,
      );
      if (motion.gone || motion.scale < 0.02) continue;
      final origin = project(cells[i]);
      final edge = project(cells[i] + Offset(spacing, 0));
      if (origin == null || edge == null) continue;
      final px = (edge - origin).distance;
      if (px < 0.5) continue;
      final at = Offset.lerp(origin, target ?? fallback, motion.fly)!;
      canvas.save();
      canvas.translate(at.dx, at.dy);
      canvas.scale(motion.scale);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: px, height: px),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ScrapTallyPainter oldDelegate) => true;
}

/// Level bubble for a held fold. The track is perpendicular to the crease,
/// centered on the reticle. Each end is a 135° preview; the ticks are 90°.
class _FoldLevelPainter extends CustomPainter {
  _FoldLevelPainter({
    required this.axis,
    required this.signed,
    required this.half,
  });

  final Offset axis;
  final double signed;
  final double half;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final along = axis * half;
    final across = Offset(-axis.dy, axis.dx);
    final start = center - along;
    final end = center + along;
    final shadow = Paint()
      ..color = const Color(0x99000000)
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    final track = Paint()
      ..color = const Color(0xF2FFFFFF)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(start, end, shadow);
    canvas.drawLine(start, end, track);

    final tick = Paint()
      ..color = const Color(0xF2FFFFFF)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final tickShadow = Paint()
      ..color = const Color(0x99000000)
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    for (final side in const [-1.0, 1.0]) {
      final at = center + along * (side * foldCommitMark);
      final tip = across * 9;
      canvas.drawLine(at - tip, at + tip, tickShadow);
      canvas.drawLine(at - tip, at + tip, tick);
    }

    final commits = foldPreviewCommits(signed);
    final bubble = center + along * signed.clamp(-1.0, 1.0);
    canvas.drawCircle(bubble, 8, Paint()..color = const Color(0xCC000000));
    canvas.drawCircle(
      bubble,
      6,
      Paint()
        ..color = commits ? const Color(0xFFFFB020) : const Color(0xF2FFFFFF),
    );
  }

  @override
  bool shouldRepaint(covariant _FoldLevelPainter oldDelegate) {
    return oldDelegate.axis != axis ||
        oldDelegate.signed != signed ||
        oldDelegate.half != half;
  }
}
