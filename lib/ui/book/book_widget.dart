import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'book_pages.dart';
import 'page_turn.dart';

const double kGoldenRatio = 1.618033988749895;
const double kSpineWidth = 3.0;
const double kHitZone = 0.15;
const double kPortraitPageFrac = 0.80;
const double kClosedFrac = 0.48;
const Duration kTurnDuration = Duration(milliseconds: 200);
const int kContentSpreads = 5;
const int kLastSpread = kContentSpreads; // opening (0) + 5 content

enum BookPhase { closedFront, open, closedBack }

enum _Anim {
  none,
  pan,
  pageTurnForward,
  pageTurnBack,
  coverOpen,
  coverCloseFront,
  coverCloseBack,
  coverOpenFromBack,
  flipToFront,
}

class BookWidget extends StatefulWidget {
  const BookWidget({super.key});

  @override
  State<BookWidget> createState() => _BookWidgetState();
}

class _BookWidgetState extends State<BookWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _curve;

  BookPhase _phase = BookPhase.closedFront;
  int _spread = 0;
  bool _focusLeft = false;
  Offset _tapPos = Offset.zero;

  _Anim _anim = _Anim.none;
  int _fromSpread = 0;
  bool _fromFocusLeft = false;
  BookPhase _toPhase = BookPhase.closedFront;
  int _toSpread = 0;
  bool _toFocusLeft = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: kTurnDuration);
    _curve = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          _phase = _toPhase;
          _spread = _toSpread;
          _focusLeft = _toFocusLeft;
          _anim = _Anim.none;
        });
        _controller.reset();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _busy => _anim != _Anim.none;

  void _start({
    required _Anim anim,
    required BookPhase toPhase,
    required int toSpread,
    required bool toFocusLeft,
  }) {
    if (_busy) return;
    setState(() {
      _fromSpread = _spread;
      _fromFocusLeft = _focusLeft;
      _toPhase = toPhase;
      _toSpread = toSpread;
      _toFocusLeft = toFocusLeft;
      _anim = anim;
    });
    _controller.duration = anim == _Anim.flipToFront
        ? const Duration(milliseconds: 420)
        : kTurnDuration;
    _controller.forward(from: 0);
  }

  // ── Sizing ──────────────────────────────────────────────────────────

  Size _closedPageSize(Size screen) {
    final shorter = math.min(screen.width, screen.height);
    var width = shorter * kClosedFrac;
    var height = width * kGoldenRatio;
    if (height > screen.height * 0.82) {
      height = screen.height * 0.82;
      width = height / kGoldenRatio;
    }
    return Size(width, height);
  }

  Size _openPageSize(Size screen, Orientation orientation) {
    if (orientation == Orientation.portrait) {
      var width = screen.width * kPortraitPageFrac;
      var height = width * kGoldenRatio;
      if (height > screen.height * 0.88) {
        height = screen.height * 0.88;
        width = height / kGoldenRatio;
      }
      return Size(width, height);
    }
    final maxH = screen.height * 0.88;
    final maxW = (screen.width * 0.92 - kSpineWidth) / 2;
    var width = maxW;
    var height = width * kGoldenRatio;
    if (height > maxH) {
      height = maxH;
      width = height / kGoldenRatio;
    }
    return Size(width, height);
  }

  double _panX({
    required Size screen,
    required double pageW,
    required Orientation orientation,
    required bool focusLeft,
  }) {
    if (orientation == Orientation.landscape) {
      return (screen.width - (pageW * 2 + kSpineWidth)) / 2;
    }
    final centered = (screen.width - pageW) / 2;
    if (focusLeft) return centered;
    // Right page centered; left page peeks in the left margin.
    return centered - pageW - kSpineWidth;
  }

  Rect _closedBookRect(Size screen) {
    final s = _closedPageSize(screen);
    return Rect.fromCenter(
      center: Offset(screen.width / 2, screen.height / 2),
      width: s.width,
      height: s.height,
    );
  }

  // ── Pages ───────────────────────────────────────────────────────────

  Widget _page(int spread, {required bool left}) {
    if (spread <= 0) {
      return left ? const InsideFrontCover() : const ContentsPage();
    }
    final number = (spread - 1) * 2 + (left ? 1 : 2);
    return NumberedPage(number: number, isLeft: left);
  }

  Widget _spine(double height) {
    return Container(
      width: kSpineWidth,
      height: height,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF1A1620),
            Color(0xFF4A3F50),
            Color(0xFF1A1620),
          ],
        ),
      ),
    );
  }

  Widget _closedShell({
    required Size size,
    required bool spineOnLeft,
    required Widget child,
  }) {
    const thickness = 7.0;
    return SizedBox(
      width: size.width + thickness,
      height: size.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: 6,
            bottom: 6,
            left: spineOnLeft ? size.width - 1 : 0,
            width: thickness + 1,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Color(0xFFE8DCC8), Color(0xFFBFA88A)],
                ),
              ),
            ),
          ),
          Positioned(
            left: spineOnLeft ? 0 : thickness,
            top: 0,
            width: size.width,
            height: size.height,
            child: DecoratedBox(
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 28,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: child,
            ),
          ),
        ],
      ),
    );
  }

  Widget _shadowWrap(Widget child) {
    return DecoratedBox(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.38),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _spreadStack({
    required Size page,
    required Widget left,
    required Widget right,
    Widget? turning,
    bool turnOnRight = true,
  }) {
    return SizedBox(
      width: page.width * 2 + kSpineWidth,
      height: page.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Row(
            children: [
              SizedBox(width: page.width, height: page.height, child: left),
              _spine(page.height),
              SizedBox(width: page.width, height: page.height, child: right),
            ],
          ),
          if (turning != null)
            Positioned(
              left: turnOnRight ? page.width + kSpineWidth : 0,
              top: 0,
              width: page.width,
              height: page.height,
              child: turning,
            ),
        ],
      ),
    );
  }

  // ── Hit testing ─────────────────────────────────────────────────────

  void _onTap(Offset local, Size screen, Orientation orientation) {
    if (_busy) return;
    final leftZone = local.dx < screen.width * kHitZone;
    final rightZone = local.dx > screen.width * (1 - kHitZone);

    switch (_phase) {
      case BookPhase.closedFront:
        if (_closedBookRect(screen).inflate(8).contains(local)) {
          _start(
            anim: _Anim.coverOpen,
            toPhase: BookPhase.open,
            toSpread: 0,
            toFocusLeft: false,
          );
        }
        return;
      case BookPhase.closedBack:
        final book = _closedBookRect(screen).inflate(8);
        final onBook = book.contains(local);
        final onLeftHalf = onBook && local.dx < book.center.dx;
        final onRightHalf = onBook && local.dx >= book.center.dx;
        if (leftZone || onLeftHalf) {
          _start(
            anim: _Anim.coverOpenFromBack,
            toPhase: BookPhase.open,
            toSpread: kLastSpread,
            toFocusLeft: false,
          );
        } else if (rightZone || onRightHalf) {
          _start(
            anim: _Anim.flipToFront,
            toPhase: BookPhase.closedFront,
            toSpread: 0,
            toFocusLeft: false,
          );
        }
        return;
      case BookPhase.open:
        if (orientation == Orientation.landscape) {
          if (rightZone) _landscapeNext();
          if (leftZone) _landscapePrev();
        } else {
          _portraitTap(leftZone, rightZone);
        }
    }
  }

  void _portraitTap(bool leftZone, bool rightZone) {
    if (!leftZone && !rightZone) return;

    if (_spread == 0) {
      if (leftZone) {
        _start(
          anim: _Anim.coverCloseFront,
          toPhase: BookPhase.closedFront,
          toSpread: 0,
          toFocusLeft: false,
        );
      } else if (rightZone) {
        _start(
          anim: _Anim.pageTurnForward,
          toPhase: BookPhase.open,
          toSpread: 1,
          toFocusLeft: true,
        );
      }
      return;
    }

    if (_focusLeft) {
      if (rightZone) {
        _start(
          anim: _Anim.pan,
          toPhase: BookPhase.open,
          toSpread: _spread,
          toFocusLeft: false,
        );
      } else if (leftZone) {
        _start(
          anim: _Anim.pageTurnBack,
          toPhase: BookPhase.open,
          toSpread: _spread - 1,
          toFocusLeft: false,
        );
      }
      return;
    }

    if (leftZone) {
      _start(
        anim: _Anim.pan,
        toPhase: BookPhase.open,
        toSpread: _spread,
        toFocusLeft: true,
      );
    } else if (rightZone) {
      if (_spread == kLastSpread) {
        _start(
          anim: _Anim.coverCloseBack,
          toPhase: BookPhase.closedBack,
          toSpread: kLastSpread,
          toFocusLeft: false,
        );
      } else {
        _start(
          anim: _Anim.pageTurnForward,
          toPhase: BookPhase.open,
          toSpread: _spread + 1,
          toFocusLeft: true,
        );
      }
    }
  }

  void _landscapeNext() {
    if (_spread == kLastSpread) {
      _start(
        anim: _Anim.coverCloseBack,
        toPhase: BookPhase.closedBack,
        toSpread: kLastSpread,
        toFocusLeft: false,
      );
    } else {
      _start(
        anim: _Anim.pageTurnForward,
        toPhase: BookPhase.open,
        toSpread: _spread + 1,
        toFocusLeft: false,
      );
    }
  }

  void _landscapePrev() {
    if (_spread == 0) {
      _start(
        anim: _Anim.coverCloseFront,
        toPhase: BookPhase.closedFront,
        toSpread: 0,
        toFocusLeft: false,
      );
    } else {
      _start(
        anim: _Anim.pageTurnBack,
        toPhase: BookPhase.open,
        toSpread: _spread - 1,
        toFocusLeft: false,
      );
    }
  }

  // ── Build ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screen = Size(constraints.maxWidth, constraints.maxHeight);
        final orientation = MediaQuery.orientationOf(context);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _tapPos = d.localPosition,
          onTap: () => _onTap(_tapPos, screen, orientation),
          child: AnimatedBuilder(
            animation: _curve,
            builder: (context, _) => _buildVisual(screen, orientation),
          ),
        );
      },
    );
  }

  Widget _buildVisual(Size screen, Orientation orientation) {
    final t = _curve.value;
    switch (_anim) {
      case _Anim.none:
        return _idle(screen, orientation);
      case _Anim.pan:
        return _buildOpenSpread(
          screen: screen,
          orientation: orientation,
          spread: _spread,
          focusLeftFrom: _fromFocusLeft,
          focusLeftTo: _toFocusLeft,
          panT: t,
        );
      case _Anim.pageTurnForward:
      case _Anim.pageTurnBack:
        return _buildOpenSpread(
          screen: screen,
          orientation: orientation,
          spread: _fromSpread,
          toSpread: _toSpread,
          turnT: t,
          turnForward: _anim == _Anim.pageTurnForward,
          focusLeftFrom: _fromFocusLeft,
          focusLeftTo: _toFocusLeft,
          panT: t,
        );
      case _Anim.coverOpen:
        return _buildFrontHinge(screen, orientation, t);
      case _Anim.coverCloseFront:
        return _buildFrontHinge(screen, orientation, 1 - t);
      case _Anim.coverOpenFromBack:
        return _buildBackHinge(screen, orientation, t);
      case _Anim.coverCloseBack:
        return _buildBackHinge(screen, orientation, 1 - t);
      case _Anim.flipToFront:
        return _buildFlip(screen, Curves.easeInOutSine.transform(_controller.value));
    }
  }

  Widget _idle(Size screen, Orientation orientation) {
    switch (_phase) {
      case BookPhase.closedFront:
        return Center(
          child: _closedShell(
            size: _closedPageSize(screen),
            spineOnLeft: true,
            child: const CoverFront(),
          ),
        );
      case BookPhase.closedBack:
        return Center(
          child: _closedShell(
            size: _closedPageSize(screen),
            spineOnLeft: false,
            child: const CoverBack(),
          ),
        );
      case BookPhase.open:
        return _buildOpenSpread(
          screen: screen,
          orientation: orientation,
          spread: _spread,
          focusLeftFrom: _focusLeft,
          focusLeftTo: _focusLeft,
          panT: 1,
        );
    }
  }

  Widget _buildOpenSpread({
    required Size screen,
    required Orientation orientation,
    required int spread,
    int? toSpread,
    double turnT = 0,
    bool turnForward = true,
    required bool focusLeftFrom,
    required bool focusLeftTo,
    required double panT,
  }) {
    final page = _openPageSize(screen, orientation);
    final fromX = _panX(
      screen: screen,
      pageW: page.width,
      orientation: orientation,
      focusLeft: focusLeftFrom,
    );
    final toX = _panX(
      screen: screen,
      pageW: page.width,
      orientation: orientation,
      focusLeft: focusLeftTo,
    );
    final px = fromX + (toX - fromX) * panT;
    final py = (screen.height - page.height) / 2;

    final turning = toSpread != null;
    late final Widget left;
    late final Widget right;
    Widget? leaf;
    var turnOnRight = true;

    if (turning && turnForward) {
      left = _page(spread, left: true);
      right = _page(toSpread, left: false);
      leaf = TurningLeaf(
        progress: turnT,
        hingeLeft: true,
        front: _page(spread, left: false),
        back: _page(toSpread, left: true),
      );
      turnOnRight = true;
    } else if (turning && !turnForward) {
      left = _page(toSpread, left: true);
      right = _page(spread, left: false);
      leaf = TurningLeaf(
        progress: turnT,
        hingeLeft: false,
        front: _page(spread, left: true),
        back: _page(toSpread, left: false),
      );
      turnOnRight = false;
    } else {
      left = _page(spread, left: true);
      right = _page(spread, left: false);
    }

    return Stack(
      children: [
        Positioned(
          left: px,
          top: py,
          child: _shadowWrap(
            _spreadStack(
              page: page,
              left: left,
              right: right,
              turning: leaf,
              turnOnRight: turnOnRight,
            ),
          ),
        ),
      ],
    );
  }

  /// Front cover hinges open around the spine; TOC stays in the cover's place.
  Widget _buildFrontHinge(Size screen, Orientation orientation, double t) {
    final closed = _closedPageSize(screen);
    final open = _openPageSize(screen, orientation);
    final pageW = closed.width + (open.width - closed.width) * t;
    final pageH = closed.height + (open.height - closed.height) * t;

    var dx = (screen.width - pageW) / 2;
    final dy = (screen.height - pageH) / 2;
    if (orientation == Orientation.landscape) {
      dx += (pageW + kSpineWidth) / 2 * t;
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: dx,
          top: dy,
          width: pageW,
          height: pageH,
          child: _shadowWrap(
            Stack(
              clipBehavior: Clip.none,
              children: [
                const ContentsPage(),
                TurningLeaf(
                  progress: t,
                  hingeLeft: true,
                  front: const CoverFront(),
                  back: const InsideFrontCover(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Back cover hinges around the right edge, revealing the last right-hand page.
  Widget _buildBackHinge(Size screen, Orientation orientation, double t) {
    final closed = _closedPageSize(screen);
    final open = _openPageSize(screen, orientation);
    final pageW = closed.width + (open.width - closed.width) * t;
    final pageH = closed.height + (open.height - closed.height) * t;

    var dx = (screen.width - pageW) / 2;
    final dy = (screen.height - pageH) / 2;
    if (orientation == Orientation.landscape) {
      dx += (pageW + kSpineWidth) / 2 * t;
    }

    final lastLeft = _page(kLastSpread, left: true);
    final lastRight = _page(kLastSpread, left: false);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: dx - pageW - kSpineWidth,
          top: dy,
          width: pageW,
          height: pageH,
          child: Opacity(
            opacity: t.clamp(0.0, 1.0),
            child: lastLeft,
          ),
        ),
        Positioned(
          left: dx,
          top: dy,
          width: pageW,
          height: pageH,
          child: _shadowWrap(
            Stack(
              clipBehavior: Clip.none,
              children: [
                lastRight,
                TurningLeaf(
                  progress: t,
                  hingeLeft: false,
                  front: const CoverBack(),
                  back: const InsideBackCover(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFlip(Size screen, double t) {
    final s = _closedPageSize(screen);
    final thickness = math.max(16.0, s.width * 0.08);
    return Center(
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Transform.translate(
            offset: Offset(0, s.height * 0.5 + 2),
            child: IgnorePointer(
              child: Container(
                width: s.width * 0.7,
                height: 20,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 22,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
            ),
          ),
          BookVolumeFlip(
            progress: t,
            size: s,
            thickness: thickness,
            front: const CoverFront(),
            back: const CoverBack(),
          ),
        ],
      ),
    );
  }
}
