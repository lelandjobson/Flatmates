import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'drawing_graph.dart';
import 'sticker_program.dart';

class FocusToolDock extends StatefulWidget {
  const FocusToolDock({
    super.key,
    required this.card,
    required this.implement,
    required this.onCard,
    required this.onImplement,
    required this.primed,
    required this.onPrime,
  });
  final FocusToolCard card;
  final DrawingImplement implement;
  final ValueChanged<FocusToolCard> onCard;
  final ValueChanged<DrawingImplement> onImplement;
  final StickerKind? primed;
  final ValueChanged<StickerKind?> onPrime;
  @override
  State<FocusToolDock> createState() => _FocusToolDockState();
}

class _FocusToolDockState extends State<FocusToolDock> {
  late final pages = PageController(initialPage: widget.card.index);
  final scroll = ScrollController();
  bool showName = true;
  late final implements = FixedExtentScrollController(
    initialItem: DrawingImplement.values.length * 1000 + widget.implement.index,
  );
  Timer? nameTimer;
  @override
  void initState() {
    super.initState();
    _name();
  }

  void _name() {
    nameTimer?.cancel();
    showName = true;
    nameTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) setState(() => showName = false);
    });
  }

  @override
  void didUpdateWidget(FocusToolDock old) {
    super.didUpdateWidget(old);
    if (old.implement != widget.implement) {
      _name();
      if (implements.hasClients &&
          implements.selectedItem % DrawingImplement.values.length !=
              widget.implement.index) {
        final current = implements.selectedItem;
        final count = DrawingImplement.values.length;
        var delta = (widget.implement.index - current % count) % count;
        if (delta > count ~/ 2) delta -= count;
        implements.animateToItem(
          current + delta,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    }
    if (old.card != widget.card &&
        pages.hasClients &&
        pages.page?.round() != widget.card.index) {
      pages.animateToPage(
        widget.card.index,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    nameTimer?.cancel();
    pages.dispose();
    implements.dispose();
    scroll.dispose();
    super.dispose();
  }

  void cycle(int direction) => widget.onImplement(
    DrawingImplement.values[(widget.implement.index + direction) %
        DrawingImplement.values.length],
  );
  Widget picture(int index) {
    final real = index < stickerDefinitions.length;
    return Semantics(
      label: real
          ? stickerDefinitions[index].name
          : 'Placeholder sticker ${index + 1}',
      button: real,
      selected: real && widget.primed == stickerDefinitions[index].kind,
      child: Container(
        key: ValueKey('sticker-card-$index'),
        width: 82,
        height: 74,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Color.lerp(
            const Color(0xffeee9dc),
            const Color(0xffcbd1bc),
            (index % 5) * .07,
          ),
          borderRadius: BorderRadius.circular(3),
        ),
        child: CustomPaint(
          painter: real
              ? StickerPicture(stickerDefinitions[index].kind)
              : PlaceholderStickerPicture(index),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final short = MediaQuery.sizeOf(context).height < 500;
    return SizedBox(
      height: short ? 120 : 160,
      width: 640,
      child: PageView(
        controller: pages,
        scrollBehavior: const MaterialScrollBehavior().copyWith(
          dragDevices: PointerDeviceKind.values.toSet(),
          scrollbars: false,
        ),
        onPageChanged: (index) {
          widget.onPrime(null);
          widget.onCard(FocusToolCard.values[index]);
        },
        children: [
          Semantics(
            label: widget.implement.label,
            value: widget.implement.label,
            increasedValue:
                DrawingImplement.values[(widget.implement.index + 1) % 5].label,
            decreasedValue:
                DrawingImplement.values[(widget.implement.index + 4) % 5].label,
            onIncrease: () => cycle(1),
            onDecrease: () => cycle(-1),
            child: Stack(
              key: const ValueKey('drawing-tool-card'),
              children: [
                ListWheelScrollView.useDelegate(
                  key: const ValueKey('implement-wheel'),
                  controller: implements,
                  scrollBehavior: const MaterialScrollBehavior().copyWith(
                    dragDevices: PointerDeviceKind.values.toSet(),
                    scrollbars: false,
                  ),
                  itemExtent: (short ? 120.0 : 160.0) / 5,
                  diameterRatio: 100,
                  perspective: .001,
                  physics: const FixedExtentScrollPhysics(),
                  onSelectedItemChanged: (index) => widget.onImplement(
                    DrawingImplement.values[index %
                        DrawingImplement.values.length],
                  ),
                  childDelegate: ListWheelChildLoopingListDelegate(
                    children: [
                      for (final implement in DrawingImplement.values)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          child: ColorFiltered(
                            colorFilter: ColorFilter.mode(
                              implement == widget.implement
                                  ? Colors.white
                                  : const Color(0xff373b40),
                              implement == widget.implement
                                  ? BlendMode.modulate
                                  : BlendMode.srcIn,
                            ),
                            child: CustomPaint(
                              painter: ImplementPicture(implement),
                              child: const SizedBox.expand(),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Positioned(
                  right: 16,
                  top: 8,
                  child: AnimatedOpacity(
                    opacity: showName ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Text(
                      widget.implement.label,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            key: const ValueKey('stickerbook-card'),
            behavior: HitTestBehavior.opaque,
            onTap: widget.primed == null ? null : () => widget.onPrime(null),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  top: 20,
                  child: ClipRect(
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 160),
                      opacity: 1,
                      child: Transform(
                        key: const ValueKey('tilted-stickerbook'),
                        alignment: Alignment.bottomCenter,
                        transform: Matrix4.identity()
                          ..setEntry(3, 2, .0018)
                          ..rotateX(-.35),
                        child: GridView.builder(
                          key: const ValueKey('stickerbook-scroll'),
                          controller: scroll,
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 106,
                                mainAxisExtent: 82,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                              ),
                          itemCount: 35,
                          itemBuilder: (_, index) => GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => widget.onPrime(
                              widget.primed != null
                                  ? null
                                  : index < 5
                                  ? stickerDefinitions[index].kind
                                  : null,
                            ),
                            child: TweenAnimationBuilder<double>(
                              duration: MediaQuery.disableAnimationsOf(context)
                                  ? Duration.zero
                                  : const Duration(milliseconds: 180),
                              curve: Curves.easeOutCubic,
                              tween: Tween(
                                end:
                                    index < stickerDefinitions.length &&
                                        widget.primed ==
                                            stickerDefinitions[index].kind
                                    ? 1
                                    : 0,
                              ),
                              builder: (context, lift, child) => Transform(
                                key: ValueKey('sticker-lift-$index'),
                                alignment: Alignment.center,
                                transform: Matrix4.identity()
                                  ..translateByDouble(
                                    0.0,
                                    -8.0 * lift,
                                    0.0,
                                    1.0,
                                  )
                                  ..scaleByDouble(
                                    1 + .04 * lift,
                                    1 + .04 * lift,
                                    1.0,
                                    1.0,
                                  ),
                                child: AnimatedOpacity(
                                  duration:
                                      MediaQuery.disableAnimationsOf(context)
                                      ? Duration.zero
                                      : const Duration(milliseconds: 180),
                                  opacity:
                                      widget.primed == null ||
                                          (index < stickerDefinitions.length &&
                                              widget.primed ==
                                                  stickerDefinitions[index]
                                                      .kind)
                                      ? 1
                                      : .38,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: .28 * lift,
                                          ),
                                          blurRadius: 14 * lift,
                                          offset: Offset(0, 9 * lift),
                                        ),
                                      ],
                                    ),
                                    child: child,
                                  ),
                                ),
                              ),
                              child: picture(index),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (widget.primed != null) ...[
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: Text(
                        stickerDefinitions[widget.primed!.index].name,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PlaceholderStickerPicture extends CustomPainter {
  const PlaceholderStickerPicture(this.index);
  final int index;
  @override
  void paint(Canvas canvas, Size size) {
    final color = Color.lerp(
      const Color(0xff586b77),
      const Color(0xff9e715e),
      (index % 7) / 6,
    )!;
    final p = Paint()..color = color,
        center = size.center(Offset.zero),
        r = math.min(size.width, size.height) * .29;
    switch (index % 4) {
      case 0:
        canvas.drawCircle(center, r, p);
      case 1:
        canvas.drawRect(
          Rect.fromCenter(center: center, width: r * 2, height: r * 2),
          p,
        );
      case 2:
        canvas.drawPath(
          Path()
            ..moveTo(center.dx, center.dy - r)
            ..lineTo(center.dx + r, center.dy + r)
            ..lineTo(center.dx - r, center.dy + r)
            ..close(),
          p,
        );
      case 3:
        canvas.save();
        canvas.translate(center.dx, center.dy);
        canvas.rotate(math.pi / 4);
        canvas.drawRect(
          Rect.fromCenter(center: Offset.zero, width: r * 1.6, height: r * 1.6),
          p,
        );
        canvas.restore();
    }
  }

  @override
  bool shouldRepaint(PlaceholderStickerPicture old) => old.index != index;
}

class ImplementPicture extends CustomPainter {
  const ImplementPicture(this.implement);
  final DrawingImplement implement;
  @override
  void paint(Canvas c, Size size) {
    final w = size.width, h = size.height, cy = h * .52;
    final color = switch (implement) {
      DrawingImplement.pencil => const Color(0xffc2a45c),
      DrawingImplement.pen => const Color(0xffc2c9c5),
      DrawingImplement.marker => const Color(0xff283e42),
      DrawingImplement.crookedPencil => const Color(0xff718e74),
      DrawingImplement.eraser => const Color(0xffb36d69),
    };
    final thick =
        (implement == DrawingImplement.marker
            ? 19.0
            : implement == DrawingImplement.eraser
            ? 24.0
            : 10.0) *
        math.min(1.0, h / 64);
    final p = Paint()..color = color;
    if (implement == DrawingImplement.eraser) {
      c.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(w * .15, cy - thick, w * .85, cy + thick),
          const Radius.circular(3),
        ),
        p,
      );
      c.drawRect(
        Rect.fromLTRB(w * .42, cy - thick, w * .78, cy + thick),
        Paint()..color = const Color(0xffe0dbc8),
      );
      return;
    }
    final path = Path()
      ..moveTo(w * .08, cy - thick)
      ..lineTo(w * .87, cy - thick)
      ..lineTo(w * .96, cy)
      ..lineTo(w * .87, cy + thick)
      ..lineTo(w * .08, cy + thick)
      ..close();
    if (implement == DrawingImplement.crookedPencil) {
      c.save();
      c.translate(w * .5, cy);
      c.rotate(-.045);
      c.translate(-w * .5, -cy);
    }
    c.drawPath(path, p);
    c.drawRect(
      Rect.fromLTRB(w * .12, cy - thick, w * .83, cy - thick * .4),
      Paint()..color = Colors.white.withValues(alpha: .22),
    );
    c.drawPath(
      Path()
        ..moveTo(w * .87, cy - thick)
        ..lineTo(w * .96, cy)
        ..lineTo(w * .87, cy + thick)
        ..close(),
      Paint()..color = const Color(0xffd3c7aa),
    );
    c.drawPath(
      Path()
        ..moveTo(w * .935, cy - thick * .25)
        ..lineTo(w * .96, cy)
        ..lineTo(w * .935, cy + thick * .25)
        ..close(),
      Paint()..color = const Color(0xff272e2b),
    );
    c.drawRect(
      Rect.fromLTRB(w * .08, cy - thick, w * .13, cy + thick),
      Paint()..color = const Color(0xff444b48),
    );
    if (implement == DrawingImplement.crookedPencil) c.restore();
  }

  @override
  bool shouldRepaint(ImplementPicture old) => old.implement != implement;
}

class StickerPicture extends CustomPainter {
  const StickerPicture(this.kind);
  final StickerKind kind;
  @override
  void paint(Canvas c, Size size) {
    c.save();
    c.scale(size.width / 80, size.height / 60);
    final ink = Paint()..color = const Color(0xff37464b),
        fill = Paint()..color = const Color(0xffacb69b);
    switch (kind) {
      case StickerKind.house:
        c.drawRect(const Rect.fromLTWH(18, 25, 44, 29), fill);
        c.drawPath(
          Path()
            ..moveTo(10, 27)
            ..lineTo(40, 5)
            ..lineTo(70, 27)
            ..close(),
          ink,
        );
        c.drawRect(const Rect.fromLTWH(33, 35, 14, 19), ink);
      case StickerKind.hill:
        for (var i = 0; i < 3; i++) {
          c.drawRect(
            Rect.fromLTWH(8 + i * 10, 43 - i * 14, 64 - i * 20, 14),
            Paint()
              ..color = Color.lerp(
                const Color(0xff546b51),
                const Color(0xffc0c79c),
                i / 2,
              )!,
          );
        }
      case StickerKind.bed:
        c.drawRect(const Rect.fromLTWH(10, 10, 8, 43), ink);
        c.drawRect(const Rect.fromLTWH(18, 23, 52, 23), fill);
        c.drawRect(
          const Rect.fromLTWH(20, 18, 16, 9),
          Paint()..color = Colors.white,
        );
        c.drawRect(const Rect.fromLTWH(10, 43, 62, 6), ink);
        c.drawRect(const Rect.fromLTWH(64, 44, 6, 10), ink);
      case StickerKind.door:
        c.drawRect(const Rect.fromLTWH(20, 4, 40, 52), ink);
        c.drawRect(const Rect.fromLTWH(26, 9, 28, 47), fill);
        c.drawCircle(const Offset(48, 34), 2, ink);
      case StickerKind.window:
        c.drawRect(const Rect.fromLTWH(13, 8, 54, 44), ink);
        c.drawRect(
          const Rect.fromLTWH(19, 14, 42, 32),
          Paint()..color = const Color(0xff9dbdc0),
        );
        c.drawRect(const Rect.fromLTWH(38, 12, 4, 36), ink);
        c.drawRect(const Rect.fromLTWH(17, 28, 46, 4), ink);
    }
    c.restore();
  }

  @override
  bool shouldRepaint(StickerPicture old) => old.kind != kind;
}
