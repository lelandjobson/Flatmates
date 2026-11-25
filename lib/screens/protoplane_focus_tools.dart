part of 'protoplane_concept_view.dart';

extension _FocusTools on _ProtoplaneConceptViewState {
  void _cancelFocusStroke() {
    _focusPath.clear();
    _focusLiveScreen = null;
    _eraseStart = _eraseEnd = null;
    _focusGestureSurface = null;
  }

  int? _focusNode(Offset screen) {
    final surface = model.drawingSurface, grid = model.focusDrawingGrid;
    if (surface == null || grid == null) return null;
    var best = 20.0;
    int? result;
    for (final (i, p) in grid.nodes.indexed) {
      final at = camera.projectToScreen(surface.frame.point(p, .009), viewport);
      if (at != null && (at - screen).distance < best) {
        best = (at - screen).distance;
        result = i;
      }
    }
    return result;
  }

  bool _focusPointerDown(PointerDownEvent e) {
    if (!_drawingFocused || devToolsOpen || loading || loadFailed) {
      return false;
    }
    _focusTouches[e.pointer] = e.localPosition;
    _focusLiveScreen = e.localPosition;
    _updateFocusUi(() {});
    controls.move(e.kind, e.localPosition);
    if (_focusTouches.length > 1) {
      _cancelFocusStroke();
      _focusHadMultiple = true;
      _focusSpan =
          (_focusTouches.values.first - _focusTouches.values.last).distance;
      _updateFocusUi(() {});
      return true;
    }
    controls.begin(e.kind, e.localPosition);
    _focusHadMultiple = false;
    _focusDownAt = e.localPosition;
    if (e.buttons & (kSecondaryMouseButton | kMiddleMouseButton) != 0) {
      return true;
    }
    if (model.focusCard != FocusToolCard.drawing) return true;
    final surface = model.drawingSurface;
    if (surface == null) return true;
    _focusGestureSurface = surface.id;
    if (model.drawingImplement == DrawingImplement.eraser) {
      _eraseStart = _eraseEnd = _localOn(surface.frame, e.localPosition, .009);
    } else {
      final node = _focusNode(e.localPosition);
      if (node != null) _focusPath.add(node);
    }
    _updateFocusUi(() {});
    return true;
  }

  bool _focusPointerMove(PointerMoveEvent e) {
    if (!_focusTouches.containsKey(e.pointer)) return false;
    _focusTouches[e.pointer] = e.localPosition;
    _focusLiveScreen = e.localPosition;
    _updateFocusUi(() {});
    controls.move(e.kind, e.localPosition);
    if (_focusTouches.length > 1) {
      final span =
          (_focusTouches.values.first - _focusTouches.values.last).distance;
      if (_focusSpan > 0 && span / _focusSpan < .85) {
        model.leave();
        _cancelFocusStroke();
      }
      return true;
    }
    if (_focusHadMultiple || _focusGestureSurface != model.drawingSurface?.id) {
      return true;
    }
    if (_eraseStart != null) {
      _eraseEnd = _localOn(model.drawingSurface!.frame, e.localPosition, .009);
      _updateFocusUi(() {});
      return true;
    }
    if (_focusPath.isEmpty) return true;
    final next = _focusNode(e.localPosition), grid = model.focusDrawingGrid!;
    if (next == null || next == _focusPath.last) return true;
    final a = grid.nodes[_focusPath.last], b = grid.nodes[next];
    final d = model.drawingImplement.toLattice(b - a);
    if (d.dx.abs() > 1e-6 && d.dy.abs() > 1e-6) return true;
    final route =
        grid.nodes.indexed
            .where((n) => n.$1 != _focusPath.last && onSegment(n.$2, a, b))
            .toList()
          ..sort((x, y) => (x.$2 - a).distance.compareTo((y.$2 - a).distance));
    var previous = _focusPath.last;
    for (final node in route) {
      if (grid.connection(previous, node.$1) == null) return true;
      previous = node.$1;
    }
    // Walk each pip, including skipped pointer samples, so retracing removes
    // the pending tail rather than drawing a second edge over it.
    for (final node in route) {
      if (_focusPath.length > 1 &&
          node.$1 == _focusPath[_focusPath.length - 2]) {
        _focusPath.removeLast();
      } else {
        _focusPath.add(node.$1);
      }
    }
    _updateFocusUi(() {});
    return true;
  }

  bool _focusPointerUp(PointerUpEvent e) {
    if (!_focusTouches.containsKey(e.pointer)) return false;
    _focusTouches.remove(e.pointer);
    if (_focusTouches.isNotEmpty) return true;
    controls.end();
    if (_primedSticker != null) {
      if (!_focusHadMultiple &&
          _focusDownAt != null &&
          (e.localPosition - _focusDownAt!).distance < 6) {
        controls.move(e.kind, e.localPosition);
        _placePrimedSticker();
      }
      _cancelFocusStroke();
      _updateFocusUi(() {});
      return true;
    }

    if (!_focusHadMultiple &&
        _focusGestureSurface == model.drawingSurface?.id) {
      if (_eraseStart != null && _eraseEnd != null) {
        model.eraseDrawingLine(_eraseStart!, _eraseEnd!);
      } else if (_focusPath.length > 1) {
        final grid = model.focusDrawingGrid!;
        model.commitDrawingPath(_focusPath.map((n) => grid.nodes[n]).toList());
      }
    }
    if (!_focusHadMultiple &&
        _focusPath.length < 2 &&
        _eraseStart == null &&
        _focusDownAt != null &&
        (e.localPosition - _focusDownAt!).distance < 6) {
      final hit = _pick(e.localPosition);
      if (hit != null) {
        final id = hit.object == null ? hit.plane : 'surface-${hit.object}';
        if (id != model.activePlaneId &&
            !model.activePlane!.supports.contains(id)) {
          model.enter(model.surfaceFusion.canonical[id] ?? id);
        }
      }
    }
    _cancelFocusStroke();
    _updateFocusUi(() {});
    return true;
  }

  bool _focusPointerCancel(PointerCancelEvent e) {
    if (!_focusTouches.containsKey(e.pointer)) return false;
    _focusTouches.remove(e.pointer);
    controls.cancel();
    _cancelFocusStroke();
    _focusHadMultiple = true;
    _updateFocusUi(() {});
    return true;
  }

  void _primeSticker(StickerKind? kind) {
    _primedSticker = kind;
    _stickerEvaluation = null;
    _stickerPreviewKey = null;
    _cancelFocusStroke();
    if (kind != null) _previewPrimedSticker();
    _refreshScene();
    _updateFocusUi(() {});
  }

  ({String planeId, DrawingSurface surface, Offset point})? _stickerTarget() {
    if (!_stickerbookFocused || viewport.isEmpty) return null;
    final aim = viewport.center(Offset.zero);
    final hit = _pick(aim);
    if (hit == null) return null;
    final id = hit.object == null ? hit.plane : 'surface-${hit.object}';
    final planeId = model.surfaceFusion.canonical[id] ?? id;
    final surface = model.drawingSurfaceFor(planeId);
    if (surface == null) return null;
    final point = _localOn(surface.frame, aim);
    return point == null
        ? null
        : (planeId: planeId, surface: surface, point: point);
  }

  void _previewPrimedSticker() {
    final kind = _primedSticker;
    final target = kind == null ? null : _stickerTarget();
    if (kind == null || target == null) {
      if (_stickerEvaluation != null) {
        _stickerEvaluation = null;
        _stickerPreviewKey = null;
        _refreshScene();
      }
      return;
    }
    final face = model.drawingFaceAt(target.point, surface: target.surface);
    final key =
        '$kind/${target.planeId}/${face?.graph.key}/${face?.id}/${model.drawingRevision}/${model.nextId}';
    if (key == _stickerPreviewKey) return;
    _stickerPreviewKey = key;
    _stickerEvaluation = model.evaluateSticker(
      kind,
      target.point,
      targetPlaneId: target.planeId,
    );
    _refreshScene();
  }

  void _placePrimedSticker() {
    final kind = _primedSticker, target = _stickerTarget();
    if (kind == null || target == null) return;
    final evaluation = model.evaluateSticker(
      kind,
      target.point,
      targetPlaneId: target.planeId,
    );
    if (evaluation.valid && model.applySticker(evaluation)) {
      _primeSticker(null);
    } else {
      model.report(evaluation.issue ?? 'The target has changed');
    }
  }

  void _focusPreferences() {
    devSettings.focusToolCard = model.focusCard;
    devSettings.drawingImplement = model.drawingImplement;
    devSettings.lastDrawingImplement = model.lastDrawingImplement;
    if (widget.controller == null) {
      unawaited(
        settingsStore.save(devSettings.toJson()).catchError((Object _) {
          if (mounted) {
            _updateFocusUi(
              () => settingsError = 'Could not save tool preference',
            );
          }
        }),
      );
    }
  }

  Widget _focusDock() => FocusToolDock(
    key: ValueKey('focus-tools-${model.activePlaneId}'),
    card: model.focusCard,
    implement: model.drawingImplement,
    primed: _primedSticker,
    onPrime: _primeSticker,
    onCard: (v) {
      _primeSticker(null);
      model.selectFocusCard(v);
      _focusPreferences();
    },
    onImplement: (v) {
      _cancelFocusStroke();
      model.selectDrawingImplement(v);
      _focusPreferences();
    },
  );
}

class _DrawingGraphPainter extends CustomPainter {
  _DrawingGraphPainter(
    this.model,
    this.camera,
    this.scene,
    this.path,
    this.eraseA,
    this.eraseB,
    this.evaluation,
    this.liveScreen,
  );
  final ProtoplaneController model;
  final Camera camera;
  final Scene scene;
  final List<int> path;
  final Offset? eraseA, eraseB, liveScreen;
  final ProgramEvaluation? evaluation;
  @override
  void paint(Canvas canvas, Size size) {
    final surface = model.drawingSurface;
    final visibility = <CraftPlane, Path>{};
    void clip(CraftPlane frame) => canvas.clipPath(
      visibility.putIfAbsent(
        frame,
        () => drawingVisibility(scene, camera, size, frame),
      ),
    );
    Offset? screen(Offset p) => surface == null
        ? null
        : camera.projectToScreen(surface.frame.point(p, .009), size);
    CraftPlane? lineFrame = surface?.frame;
    void line(
      Offset a,
      Offset b,
      Color color,
      double width, {
      bool glow = false,
    }) {
      final x = camera.projectToScreen(lineFrame!.point(a, .009), size),
          y = camera.projectToScreen(lineFrame.point(b, .009), size);
      if (x == null || y == null) return;
      canvas.save();
      clip(lineFrame);
      if (glow) {
        canvas.drawLine(
          x,
          y,
          Paint()
            ..color = color.withValues(alpha: .5)
            ..strokeWidth = width + 7
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
      }
      canvas.drawLine(
        x,
        y,
        Paint()
          ..color = color
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round,
      );
      canvas.restore();
    }

    final hits = eraseA != null && eraseB != null
        ? model.eraserIntersections(eraseA!, eraseB!)
        : <String, Set<String>>{};
    for (final graph in model.drawingGraphs.values) {
      lineFrame = graph.frame;
      final color = switch (graph.implement) {
        DrawingImplement.pencil => const Color(0xffff9b32),
        DrawingImplement.pen => const Color(0xff83d5ef),
        DrawingImplement.marker => const Color(0xffb3d294),
        DrawingImplement.crookedPencil => const Color(0xffd9b6ec),
        DrawingImplement.eraser => Colors.red,
      };
      for (final edge in graph.edges) {
        for (final part
            in surface != null && graph.surfaceId == surface.id
                ? surface.clip([edge])
                : [edge]) {
          final selected =
              hits[graph.key]?.contains(drawingEdgeKey(edge)) ?? false;
          line(
            part.a,
            part.b,
            selected ? Colors.orangeAccent : color,
            graph.implement == DrawingImplement.marker ? 8 : 6,
            glow: true,
          );
        }
      }
    }
    if (surface == null) return;
    final strokeColor = switch (model.drawingImplement) {
      DrawingImplement.pencil => const Color(0xffff9b32),
      DrawingImplement.pen => const Color(0xff83d5ef),
      DrawingImplement.marker => const Color(0xffb3d294),
      DrawingImplement.crookedPencil => const Color(0xffd9b6ec),
      DrawingImplement.eraser => Colors.redAccent,
    };
    final strokeWidth = model.drawingImplement == DrawingImplement.marker
        ? 8.0
        : 6.0;
    lineFrame = surface.frame;
    if (model.focusCard == FocusToolCard.drawing &&
        model.drawingImplement != DrawingImplement.eraser) {
      final grid = model.focusDrawingGrid!;
      final preview = liveScreen == null
          ? <Offset>[]
          : liveStrokePreview(
              grid: grid,
              path: path,
              pointer: liveScreen!,
              project: screen,
              allowBacktracking: true,
            );
      final reversing =
          path.length > 1 &&
          preview.length > 1 &&
          !near(preview.last, grid.nodes[path.last]) &&
          onSegment(
            preview.last,
            grid.nodes[path[path.length - 2]],
            grid.nodes[path.last],
          );
      final selected = path.take(path.length - (reversing ? 1 : 0)).toSet();
      canvas.save();
      clip(surface.frame);
      for (final (i, node) in grid.nodes.indexed) {
        final p = screen(node);
        if (p != null) {
          canvas.drawCircle(
            p,
            selected.contains(i) ? 6.5 : 3.5,
            Paint()..color = const Color(0xff181818),
          );
          canvas.drawCircle(
            p,
            selected.contains(i) ? 5 : 1.75,
            Paint()
              ..color = selected.contains(i)
                  ? strokeColor
                  : const Color(0xffd2d2d2),
          );
        }
      }
      canvas.restore();
      for (var i = 1; i < path.length - (reversing ? 1 : 0); i++) {
        line(
          grid.nodes[path[i - 1]],
          grid.nodes[path[i]],
          strokeColor,
          strokeWidth,
          glow: true,
        );
      }
      if (reversing) {
        line(
          grid.nodes[path[path.length - 2]],
          preview.last,
          strokeColor,
          strokeWidth,
          glow: true,
        );
      } else {
        for (var i = 1; i < preview.length; i++) {
          line(
            preview[i - 1],
            preview[i],
            strokeColor,
            strokeWidth,
            glow: true,
          );
        }
      }
    }
    final region = evaluation?.region;
    final targetSurface = evaluation == null
        ? null
        : model.drawingSurfaceFor(evaluation!.targetPlaneId);
    if (model.focusCard == FocusToolCard.stickerbook &&
        evaluation?.valid == true &&
        region != null &&
        targetSurface != null) {
      final p = Path()..fillType = PathFillType.evenOdd;
      for (final ring in region.rings) {
        var first = true;
        for (final node in ring) {
          final at = camera.projectToScreen(
            targetSurface.frame.point(node, .009),
            size,
          );
          if (at == null) continue;
          if (first) {
            p.moveTo(at.dx, at.dy);
            first = false;
          } else {
            p.lineTo(at.dx, at.dy);
          }
        }
        p.close();
      }
      canvas.save();
      clip(targetSurface.frame);
      canvas.drawPath(p, Paint()..color = Colors.yellow.withValues(alpha: .22));
      canvas.restore();
    }
    if (eraseA != null && eraseB != null) {
      line(eraseA!, eraseB!, Colors.redAccent, 2.5);
    }
  }

  @override
  bool shouldRepaint(_DrawingGraphPainter old) => true;
}
