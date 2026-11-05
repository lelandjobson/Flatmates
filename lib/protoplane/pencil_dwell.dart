import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';

/// One dwell produces one committed leg; moving off a dot resets only its timer.
class PencilDwell extends ChangeNotifier {
  PencilDwell(TickerProvider vsync, this.commit) {
    dots = AnimationController(
      vsync: vsync,
      duration: const Duration(milliseconds: 140),
      value: 1,
    )..addListener(notifyListeners);
    animation =
        AnimationController(
            vsync: vsync,
            duration: const Duration(milliseconds: 300),
          )
          ..addListener(notifyListeners)
          ..addStatusListener((status) {
            if (status != AnimationStatus.completed ||
                tail == null ||
                target == null) {
              return;
            }
            final from = tail!, to = target!;
            if (commit(from, to)) tail = to;
            target = null;
            animation.reset();
            _syncDots();
            notifyListeners();
          });
  }
  final bool Function(Offset from, Offset to) commit;
  late final AnimationController animation, dots;
  Map<Offset, double> _dotFrom = {}, _dotTo = {};
  Map<Offset, double> get dotSelection {
    final t = Curves.easeOutCubic.transform(dots.value);
    return {
      for (final p in {..._dotFrom.keys, ..._dotTo.keys})
        p: (_dotFrom[p] ?? 0) + ((_dotTo[p] ?? 0) - (_dotFrom[p] ?? 0)) * t,
    };
  }

  void _syncDots() {
    final selected = {?tail, ?hover};
    if (setEquals(selected, _dotTo.keys.toSet())) return;
    _dotFrom = dotSelection;
    _dotFrom.removeWhere((_, v) => v < .001);
    _dotTo = {for (final p in selected) p: 1};
    dots.forward(from: 0);
  }

  Offset? tail, target, hover;
  double get progress => animation.value;
  void begin(Offset point) {
    cancel();
    tail = hover = point;
    _syncDots();
    notifyListeners();
  }

  void pointAt(Offset? point) {
    hover = point;
    _syncDots();
    if (tail == null) {
      notifyListeners();
      return;
    }
    final next = point == tail ? null : point;
    if (next == target) {
      notifyListeners();
      return;
    }
    animation.reset();
    target = next;
    if (next != null) animation.forward();
    notifyListeners();
  }

  void cancel() {
    animation.reset();
    tail = target = hover = null;
    _syncDots();
    notifyListeners();
  }

  @override
  void dispose() {
    animation.dispose();
    dots.dispose();
    super.dispose();
  }
}
