import 'package:flutter/material.dart';

const Color kPaperColor = Color(0xFFF3EEE4);
const Color kPaperEdge = Color(0xFFD9D0C2);
const Color kInkColor = Color(0xFF2A2430);
const Color kInkMuted = Color(0xFF6B6170);

/// Off-white leaf with a hairline edge and a soft shadow on the spine side.
class PaperPage extends StatelessWidget {
  const PaperPage({
    super.key,
    required this.child,
    this.spineOnLeft = true,
    this.padding = const EdgeInsets.fromLTRB(22, 28, 22, 24),
  });

  final Widget child;
  final bool spineOnLeft;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: kPaperColor,
        border: Border.all(color: kPaperEdge, width: 0.6),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 8,
            offset: Offset(spineOnLeft ? -1 : 1, 1),
          ),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Padding(padding: padding, child: child),
          IgnorePointer(
            child: Align(
              alignment:
                  spineOnLeft ? Alignment.centerLeft : Alignment.centerRight,
              child: Container(
                width: 14,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: spineOnLeft
                        ? Alignment.centerLeft
                        : Alignment.centerRight,
                    end: spineOnLeft
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    colors: [
                      Colors.black.withValues(alpha: 0.07),
                      Colors.black.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Front cover: dark motif plus placeholder title / author.
class CoverFront extends StatelessWidget {
  const CoverFront({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const CustomPaint(painter: CoverMotifPainter(showTitleBlock: true)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(flex: 5),
              Text(
                'THE CODEX',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  letterSpacing: 6,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFFC4B494).withValues(alpha: 0.9),
                ),
              ),
              const SizedBox(height: 14),
              Container(
                width: 48,
                height: 1,
                color: const Color(0xFF8A7A5C).withValues(alpha: 0.55),
              ),
              const SizedBox(height: 14),
              Text(
                'A. PLACEHOLDER',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 3.2,
                  color: const Color(0xFF8A7A5C).withValues(alpha: 0.8),
                ),
              ),
              const Spacer(flex: 3),
            ],
          ),
        ),
      ],
    );
  }
}

/// Back cover: same motif, no title overlay.
class CoverBack extends StatelessWidget {
  const CoverBack({super.key});

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(painter: CoverMotifPainter(showTitleBlock: false));
  }
}

/// Verso of the front cover — white, centered placeholder.
class InsideFrontCover extends StatelessWidget {
  const InsideFrontCover({super.key});

  @override
  Widget build(BuildContext context) {
    return PaperPage(
      spineOnLeft: false,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CustomPaint(
              size: const Size(56, 56),
              painter: _DiamondMarkPainter(),
            ),
            const SizedBox(height: 16),
            Text(
              'ex libris',
              style: TextStyle(
                fontSize: 12,
                letterSpacing: 3,
                fontStyle: FontStyle.italic,
                color: kInkMuted.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Blank verso used while the back cover hinges.
class InsideBackCover extends StatelessWidget {
  const InsideBackCover({super.key});

  @override
  Widget build(BuildContext context) {
    return const PaperPage(
      spineOnLeft: true,
      child: SizedBox.expand(),
    );
  }
}

class ContentsPage extends StatelessWidget {
  const ContentsPage({super.key});

  static const _entries = [
    ('I.', 'The First Isle', '1'),
    ('II.', 'The Second Isle', '3'),
    ('III.', 'A Quiet Harbor', '5'),
    ('IV.', 'The Inner Room', '7'),
    ('V.', 'Returning', '9'),
  ];

  @override
  Widget build(BuildContext context) {
    return PaperPage(
      spineOnLeft: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          const Text(
            'Contents',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w500,
              color: kInkColor,
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Container(
              width: 36,
              height: 1,
              color: kInkMuted.withValues(alpha: 0.35),
            ),
          ),
          const SizedBox(height: 28),
          Expanded(
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Column(
                children: [
                  for (final e in _entries) ...[
                    _ContentsRow(numeral: e.$1, title: e.$2, page: e.$3),
                    const SizedBox(height: 14),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContentsRow extends StatelessWidget {
  const _ContentsRow({
    required this.numeral,
    required this.title,
    required this.page,
  });

  final String numeral;
  final String title;
  final String page;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 28,
          child: Text(
            numeral,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: const TextStyle(
              fontSize: 13,
              color: kInkMuted,
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Stack(
              alignment: Alignment.centerLeft,
              clipBehavior: Clip.hardEdge,
              children: [
                Text(
                  '· · · · · · · · · · · · · · · · · · · · · · · · · · · ·',
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1,
                    color: kInkMuted.withValues(alpha: 0.45),
                  ),
                ),
                ColoredBox(
                  color: kPaperColor,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        color: kInkColor,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Text(
          page,
          style: const TextStyle(
            fontSize: 13,
            color: kInkMuted,
          ),
        ),
      ],
    );
  }
}

class NumberedPage extends StatelessWidget {
  const NumberedPage({
    super.key,
    required this.number,
    required this.isLeft,
  });

  final int number;
  final bool isLeft;

  @override
  Widget build(BuildContext context) {
    return PaperPage(
      spineOnLeft: isLeft,
      padding: const EdgeInsets.fromLTRB(22, 28, 22, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Page $number',
            style: TextStyle(
              fontSize: 13,
              letterSpacing: 1.2,
              color: kInkMuted.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'The page is blank save for its number. Later this leaf will hold a map, a note, or a door.',
            style: TextStyle(
              fontSize: 14,
              height: 1.55,
              color: kInkColor.withValues(alpha: 0.72),
            ),
          ),
          const Spacer(),
          Align(
            alignment:
                isLeft ? Alignment.bottomLeft : Alignment.bottomRight,
            child: Text(
              '$number',
              style: const TextStyle(
                fontSize: 13,
                color: kInkMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CoverMotifPainter extends CustomPainter {
  const CoverMotifPainter({required this.showTitleBlock});

  final bool showTitleBlock;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(2));

    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1A1630),
            Color(0xFF101828),
            Color(0xFF1C1232),
          ],
        ).createShader(rect),
    );

    final line = Paint()
      ..color = const Color(0xFF8A7A5C).withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect.deflate(size.width * 0.055),
        const Radius.circular(1),
      ),
      line,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect.deflate(size.width * 0.085),
        const Radius.circular(1),
      ),
      line,
    );

    final panel = rect.deflate(size.width * 0.13);
    canvas.drawRRect(
      RRect.fromRectAndRadius(panel, const Radius.circular(1)),
      Paint()..color = const Color(0xFF0A0C16).withValues(alpha: 0.4),
    );

    final cx = size.width / 2;
    final cy = showTitleBlock ? size.height * 0.36 : size.height * 0.5;
    final d = size.width * 0.11;
    final diamond = Path()
      ..moveTo(cx, cy - d)
      ..lineTo(cx + d * 0.68, cy)
      ..lineTo(cx, cy + d)
      ..lineTo(cx - d * 0.68, cy)
      ..close();
    canvas.drawPath(
      diamond,
      Paint()..color = const Color(0xFF8A7A5C).withValues(alpha: 0.12),
    );
    canvas.drawPath(diamond, line);

    if (!showTitleBlock) {
      final inner = Path()
        ..moveTo(cx, cy - d * 0.45)
        ..lineTo(cx + d * 0.3, cy)
        ..lineTo(cx, cy + d * 0.45)
        ..lineTo(cx - d * 0.3, cy)
        ..close();
      canvas.drawPath(inner, line);
    }
  }

  @override
  bool shouldRepaint(covariant CoverMotifPainter oldDelegate) =>
      oldDelegate.showTitleBlock != showTitleBlock;
}

class _DiamondMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final d = size.width * 0.38;
    final path = Path()
      ..moveTo(cx, cy - d)
      ..lineTo(cx + d * 0.7, cy)
      ..lineTo(cx, cy + d)
      ..lineTo(cx - d * 0.7, cy)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = kInkMuted.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
