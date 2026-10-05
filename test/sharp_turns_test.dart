import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/grid_play_sim.dart';

void _solves(String slug, List<GridCut> cuts) {
  test('$slug is solved by its intended cuts', () {
    expect(playGridCuts(loadLevel('sharp-turns', slug), cuts), isNull);
  });
}

void _traps(String slug, String why, List<GridCut> cuts) {
  test('$slug: $why', () {
    final reason = playGridCuts(loadLevel('sharp-turns', slug), cuts);
    if (Platform.environment['SHARP_DEBUG'] != null) {
      // ignore: avoid_print
      print('TRAP $slug: $reason');
    }
    expect(reason, isNotNull);
  });
}

void main() {
  _solves('wrong-way-round', const [GridCut(3, 8, 'DDRDLUR')]);
  _traps('wrong-way-round', 'the arrow refuses the other way round', const [
    GridCut(3, 8, 'DLDRULU'),
  ]);
  _traps('wrong-way-round', 'starting in the middle of a group fails', const [
    GridCut(6, -2, 'ULURDLU'),
  ]);

  _solves('pass-it-on', const [
    GridCut(0, 5, 'DLLDRU'),
    GridCut(-5, 0, 'RDDRUL'),
    GridCut(0, -5, 'URRULD'),
    GridCut(5, 0, 'LUULDR'),
  ]);
  _traps('pass-it-on', 'cutting the piece you land on skips a number', const [
    GridCut(0, 5, 'DRDLU'),
    GridCut(-5, 0, 'RDDRUL'),
  ]);

  _solves('through-the-looking-glass', const [GridCut(1, -2, 'URULULD')]);
  _traps('through-the-looking-glass', 'the reflection hits an X', const [
    GridCut(3, 8, 'DLDRULU'),
  ]);

  _solves('lights-out', const [GridCut(4, -3, 'ULULURDLD')]);
  _traps('lights-out', 'the arrow refuses counterclockwise', const [
    GridCut(4, -3, 'UURULDRD'),
  ]);

  _solves('exit-strategy', const [GridCut(-3, 0, 'RURR'), GridCut(0, 0, 'RU')]);
  _traps('exit-strategy', 'an open link cannot leave the paper', const [
    GridCut(-3, 0, 'RRUU'),
  ]);
  _traps('exit-strategy', 'a loop breaks an arrow', const [
    GridCut(-3, 0, 'RRULD'),
  ]);

  _solves('split-decision', const [
    GridCut(-2, 3, 'RRR'),
    GridCut(-2, 0, 'RRU'),
    GridCut(0, 0, 'U'),
    GridCut(0, 10, 'DDD'),
    GridCut(0, 8, 'RDD'),
    GridCut(0, 5, 'R'),
  ]);
  _traps('split-decision', 'a second exit is refused', const [
    GridCut(-2, 3, 'RRR'),
    GridCut(-2, 0, 'RRR'),
  ]);

  _solves('penny-pincher', const [
    GridCut(-2, 0, 'RRRUULDLD'),
    GridCut(3, 0, 'U'),
    GridCut(6, 3, 'L'),
  ]);
  _traps('penny-pincher', 'purple before the last yellow fails', const [
    GridCut(-2, 0, 'RRRUULDLD'),
    GridCut(6, 3, 'L'),
  ]);

  _solves('house-of-mirrors', const [GridCut(3, 8, 'DLDRULU')]);
  _traps('house-of-mirrors', 'clockwise reflects against the arrow', const [
    GridCut(3, 8, 'DDRDLUR'),
  ]);
  _traps('house-of-mirrors', 'a side entry reflects onto an X', const [
    GridCut(8, 5, 'LLDRULU'),
  ]);

  _solves('echo-location', const [GridCut(-6, 1, 'RRURULDLD')]);
  _traps('echo-location', 'the top entry reflects onto an X', const [
    GridCut(2, 9, 'D'),
  ]);

  _solves('grand-tour', const [
    GridCut(3, 5, 'DLDRU'),
    GridCut(8, -3, 'ULURDL'),
  ]);
  _traps('grand-tour', 'the right square first strands yellow', const [
    GridCut(7, -3, 'ULURDL'),
  ]);
}
