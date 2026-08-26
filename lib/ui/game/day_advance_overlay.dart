import 'package:flutter/material.dart';

/// Night → day interlude: fade to black, dummy bar for [barDuration], fade out.
class DayAdvanceOverlay extends StatefulWidget {
  const DayAdvanceOverlay({
    super.key,
    required this.nextDay,
    required this.onReadyForDay,
    required this.onFinished,
    this.fadeDuration = const Duration(milliseconds: 280),
    this.barDuration = const Duration(milliseconds: 400),
  });

  final int nextDay;
  final VoidCallback onReadyForDay;
  final VoidCallback onFinished;
  final Duration fadeDuration;
  final Duration barDuration;

  @override
  State<DayAdvanceOverlay> createState() => _DayAdvanceOverlayState();
}

class _DayAdvanceOverlayState extends State<DayAdvanceOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _fade;
  late final AnimationController _bar;
  var _snapped = false;

  @override
  void initState() {
    super.initState();
    _fade = AnimationController(vsync: this, duration: widget.fadeDuration);
    _bar = AnimationController(vsync: this, duration: widget.barDuration);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _run();
    });
  }

  Future<void> _run() async {
    await _fade.forward();
    if (!mounted) return;
    if (!_snapped) {
      _snapped = true;
      widget.onReadyForDay();
    }
    await _bar.forward();
    if (!mounted) return;
    await _fade.reverse();
    if (!mounted) return;
    widget.onFinished();
  }

  @override
  void dispose() {
    _fade.dispose();
    _bar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_fade, _bar]),
      builder: (context, _) {
        final fade = _fade.value;
        final showCopy = fade > 0.85 || _bar.value > 0;
        return IgnorePointer(
          child: Opacity(
            opacity: fade,
            child: ColoredBox(
              color: Colors.black,
              child: Center(
                child: Opacity(
                  opacity: showCopy ? 1 : 0,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Day ${widget.nextDay}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(height: 16),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: _bar.value,
                            minHeight: 6,
                            backgroundColor: Colors.white24,
                            color: const Color(0xFFFFE08A),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
