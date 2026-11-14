import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'programs.dart';

IconData programIcon(ProgramKind program) => switch (program) {
  ProgramKind.cut => Icons.content_cut,
  ProgramKind.place => Icons.layers_outlined,
  ProgramKind.erase => Icons.cleaning_services_outlined,
  ProgramKind.volume => Icons.open_in_full,
  ProgramKind.house => Icons.cottage_outlined,
  ProgramKind.pool => Icons.pool,
  ProgramKind.rug => Icons.grid_4x4,
  ProgramKind.table => Icons.table_restaurant_outlined,
  ProgramKind.pictureFrame => Icons.filter_frames_outlined,
  ProgramKind.combine => Icons.join_inner,
};

IconData issueIcon(ProgramIssue issue) => switch (issue) {
  ProgramIssue.tooSmall => Icons.straighten,
  ProgramIssue.orientation => Icons.screen_rotation_alt,
  ProgramIssue.material => Icons.layers_clear_outlined,
  ProgramIssue.collision => Icons.block,
  ProgramIssue.support => Icons.broken_image_outlined,
  ProgramIssue.paper => Icons.layers_outlined,
  ProgramIssue.outline => Icons.polyline_outlined,
  ProgramIssue.empty => Icons.do_not_disturb_alt,
  ProgramIssue.stale => Icons.refresh,
};

Color programColor(ProgramKind p) => const [
  Color(0xffdf7164),
  Color(0xff82a959),
  Color(0xffca91ad),
  Color(0xff9396c9),
  Color(0xffeba64b),
  Color(0xff69acbf),
  Color(0xffc8996d),
  Color(0xff9da66e),
  Color(0xffa58eba),
  Color(0xff7bb6a2),
][p.index];

class ProgramSticker extends StatelessWidget {
  const ProgramSticker({
    super.key,
    required this.program,
    this.selected = false,
    this.onSelected,
    this.onDragStarted,
    this.onDragUpdate,
    this.onDragEnd,
    this.onDrop,
  });
  final ProgramKind program;
  final bool selected;
  final VoidCallback? onSelected, onDragStarted, onDragEnd;
  final ValueChanged<Offset>? onDragUpdate, onDrop;

  Widget _art({bool dragging = false}) => Material(
    color: Colors.transparent,
    child: Transform.rotate(
      angle: dragging ? -.07 : (program.index % 3 - 1) * .035,
      child: Container(
        width: 96,
        height: 110,
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: selected ? const Color(0xffffe8b4) : const Color(0xfffffdf7),
          borderRadius: BorderRadius.circular(19),
          border: Border.all(
            color: selected ? const Color(0xffda8731) : Colors.white,
            width: 3,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .15),
              blurRadius: dragging ? 13 : 4,
              offset: const Offset(2, 3),
            ),
          ],
        ),
        child: Column(
          children: [
            Expanded(
              child: CustomPaint(
                size: const Size(70, 65),
                painter: _StickerArt(program),
              ),
            ),
            Text(
              program.label,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: const TextStyle(
                fontSize: 11,
                height: 1.1,
                fontWeight: FontWeight.w700,
                color: Color(0xff4c4139),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: program.label,
    selected: selected,
    child: Draggable<ProgramKind>(
      data: program,
      feedback: _art(dragging: true),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: onDragStarted,
      onDragUpdate: (d) => onDragUpdate?.call(d.globalPosition),
      onDragEnd: (d) {
        onDrop?.call(d.offset);
        onDragEnd?.call();
      },
      childWhenDragging: Opacity(opacity: .35, child: _art()),
      child: InkWell(
        key: ValueKey('program-${program.name}'),
        onTap: onSelected,
        borderRadius: BorderRadius.circular(19),
        child: _art(),
      ),
    ),
  );
}

class ProgramStickerbook extends StatefulWidget {
  const ProgramStickerbook({
    super.key,
    required this.onSelected,
    required this.onClose,
    required this.onDragStarted,
    required this.onDragUpdate,
    required this.onDrop,
  });
  final ValueChanged<ProgramKind> onSelected, onDragStarted;
  final VoidCallback onClose;
  final void Function(ProgramKind, Offset) onDragUpdate, onDrop;
  @override
  State<ProgramStickerbook> createState() => _ProgramStickerbookState();
}

class _ProgramStickerbookState extends State<ProgramStickerbook> {
  String query = '';
  int selected = 0;
  bool dragging = false;
  List<ProgramKind> get results =>
      ProgramKind.values.where((p) => p.matches(query)).toList();
  final FocusNode searchFocus = FocusNode();
  final ScrollController gridScroll = ScrollController();
  @override
  void dispose() {
    searchFocus.dispose();
    gridScroll.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) searchFocus.requestFocus();
    });
  }

  void _choose() {
    final programs = results;
    if (programs.isNotEmpty) {
      widget.onSelected(programs[selected.clamp(0, programs.length - 1)]);
    }
  }

  void _move(int step) {
    if (results.isEmpty) return;
    setState(() => selected = (selected + step).clamp(0, results.length - 1));
    if (gridScroll.hasClients) {
      final top = (selected ~/ 3) * 128.0 + 18, bottom = top + 118;
      final view = gridScroll.position.viewportDimension,
          offset = gridScroll.offset;
      final next = top < offset
          ? top
          : bottom > offset + view
          ? bottom - view
          : offset;
      gridScroll.jumpTo(next.clamp(0.0, gridScroll.position.maxScrollExtent));
    }
  }

  @override
  Widget build(BuildContext context) {
    final programs = results;
    return Opacity(
      opacity: dragging ? .2 : 1,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(3),
          const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-3),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () => _move(1),
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _move(-1),
          const SingleActivator(LogicalKeyboardKey.enter): _choose,
          const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
        },
        child: Material(
          key: const ValueKey('program-stickerbook'),
          elevation: 18,
          shadowColor: Colors.black54,
          color: const Color(0xfff0e9d8),
          borderRadius: BorderRadius.circular(22),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
                child: Row(
                  children: [
                    const Icon(
                      Icons.auto_stories_outlined,
                      color: Color(0xff806c50),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Programs',
                        style: TextStyle(
                          color: Color(0xff514335),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: widget.onClose,
                      icon: const Icon(Icons.close, color: Color(0xff514335)),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  key: const ValueKey('program-search'),
                  focusNode: searchFocus,
                  autofocus: true,
                  style: const TextStyle(color: Color(0xff3d352b)),
                  decoration: InputDecoration(
                    labelText: 'Search',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: const Color(0xfffffcf4),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onChanged: (v) => setState(() {
                    query = v;
                    selected = 0;
                  }),
                ),
              ),
              Flexible(
                child: programs.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No programs',
                          style: TextStyle(color: Color(0xff514335)),
                        ),
                      )
                    : GridView.builder(
                        controller: gridScroll,
                        shrinkWrap: true,
                        padding: const EdgeInsets.all(18),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              mainAxisExtent: 118,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                            ),
                        itemCount: programs.length,
                        itemBuilder: (context, i) => Center(
                          child: ProgramSticker(
                            program: programs[i],
                            selected: i == selected,
                            onSelected: () => widget.onSelected(programs[i]),
                            onDragStarted: () {
                              setState(() => dragging = true);
                              widget.onDragStarted(programs[i]);
                            },
                            onDragUpdate: (p) =>
                                widget.onDragUpdate(programs[i], p),
                            onDrop: (p) => widget.onDrop(programs[i], p),
                            onDragEnd: () {
                              if (mounted) setState(() => dragging = false);
                            },
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StickerArt extends CustomPainter {
  _StickerArt(this.program);
  final ProgramKind program;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 70, size.height / 65);
    final color = programColor(program), paint = Paint()..color = color;
    final outline = Paint()
      ..color = const Color(0xff514335)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round;
    void shape(Path path) {
      canvas.drawPath(path, paint);
      canvas.drawPath(path, outline);
    }

    if (program == ProgramKind.house) {
      shape(
        Path()
          ..moveTo(12, 30)
          ..lineTo(35, 10)
          ..lineTo(59, 30)
          ..lineTo(55, 30)
          ..lineTo(55, 57)
          ..lineTo(15, 57)
          ..lineTo(15, 30)
          ..close(),
      );
      canvas.drawRect(
        const Rect.fromLTWH(29, 38, 12, 19),
        Paint()..color = const Color(0xfff9e5b7),
      );
      canvas.drawRect(
        const Rect.fromLTWH(19, 33, 8, 9),
        Paint()..color = const Color(0xff698f9b),
      );
      canvas.drawRect(
        const Rect.fromLTWH(44, 33, 8, 9),
        Paint()..color = const Color(0xff698f9b),
      );
    } else if (program == ProgramKind.pool ||
        program == ProgramKind.rug ||
        program == ProgramKind.table) {
      if (program == ProgramKind.table) {
        for (final p in [
          const Offset(12, 34),
          const Offset(48, 41),
          const Offset(56, 25),
        ]) {
          canvas.drawLine(
            p,
            p + const Offset(0, 20),
            Paint()
              ..color = const Color(0xff66543c)
              ..strokeWidth = 5,
          );
        }
      }
      shape(
        Path()
          ..moveTo(8, 28)
          ..lineTo(28, 14)
          ..lineTo(62, 26)
          ..lineTo(44, 44)
          ..close(),
      );
      if (program == ProgramKind.pool) {
        for (var i = 0; i < 3; i++) {
          canvas.drawArc(
            Rect.fromLTWH(18 + i * 9, 25 + i * 2, 14, 6),
            0,
            math.pi,
            false,
            Paint()
              ..color = Colors.white70
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2,
          );
        }
      } else if (program == ProgramKind.rug) {
        canvas.drawPath(
          Path()
            ..moveTo(18, 29)
            ..lineTo(29, 22)
            ..lineTo(51, 29)
            ..lineTo(42, 37)
            ..close(),
          outline..color = Colors.white70,
        );
      }
    } else if (program == ProgramKind.pictureFrame) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(12, 10, 47, 45),
          const Radius.circular(3),
        ),
        paint,
      );
      canvas.drawRect(
        const Rect.fromLTWH(20, 18, 31, 29),
        Paint()..color = const Color(0xfffffcf4),
      );
      canvas.drawRect(const Rect.fromLTWH(12, 10, 47, 45), outline);
      canvas.drawRect(const Rect.fromLTWH(20, 18, 31, 29), outline);
    } else {
      canvas.drawCircle(
        const Offset(35, 32),
        27,
        paint..color = color.withValues(alpha: .3),
      );
      final icon = programIcon(program);
      final tp = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(
            fontSize: 40,
            fontFamily: icon.fontFamily,
            package: icon.fontPackage,
            color: color,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset((70 - tp.width) / 2, (65 - tp.height) / 2));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StickerArt oldDelegate) => oldDelegate.program != program;
}
