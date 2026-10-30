import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'asmr_paper.dart';

/// Which part of the ASMR view a theme color belongs to.
enum AsmrThemeGroup { desk, model, ui }

/// One kind of thing drawn in the 2D desk, the 3D model, or the chrome.
enum AsmrThemeSlot {
  desk('desk', 'Desk', AsmrThemeGroup.desk, Color(0xFF14152A)),
  sky('sky', 'Sky', AsmrThemeGroup.desk, Color(0xFF2B2D4A)),
  paper('paper', 'Paper', AsmrThemeGroup.desk, Color(0xFFFFFFFF)),
  score('score', 'Score', AsmrThemeGroup.desk, Color(0xFF2A2440)),
  cut('cut', 'Cut line', AsmrThemeGroup.desk, Color(0xFFFF454D)),
  cutGlow('cutGlow', 'Cut glow', AsmrThemeGroup.desk, Color(0xFFFF454D)),
  cutPreview(
    'cutPreview',
    'Cut preview',
    AsmrThemeGroup.desk,
    Color(0xFFFF5A5F),
  ),
  selection('selection', 'Selection', AsmrThemeGroup.desk, Color(0xFFFFFFFF)),
  hologram('hologram', 'Hologram', AsmrThemeGroup.desk, Color(0xFFFFFFFF)),
  straightEdge(
    'straightEdge',
    'Straight edge',
    AsmrThemeGroup.desk,
    Color(0xFF3B3D46),
  ),
  scissors('scissors', 'Scissors', AsmrThemeGroup.desk, Color(0xFFFFFFFF)),
  scissorsMark(
    'scissorsMark',
    'Scissors mark',
    AsmrThemeGroup.desk,
    Color(0xFFFF5A5F),
  ),
  turnGrip('turnGrip', 'Turn grip', AsmrThemeGroup.desk, Color(0xFFFFFFFF)),
  knife('knife', 'Exacto', AsmrThemeGroup.desk, Color(0xFFFFFFFF)),
  marquee('marquee', 'Marquee', AsmrThemeGroup.desk, Color(0xFF66BB6A)),
  marqueeCross(
    'marqueeCross',
    'Marquee cross',
    AsmrThemeGroup.desk,
    Color(0xFF42A5F5),
  ),
  blueprint('blueprint', 'Blueprint', AsmrThemeGroup.model, Color(0xFF1565C0)),
  preselect('preselect', 'Preselect', AsmrThemeGroup.model, Color(0xFFFF9F43)),
  complete('complete', 'Complete', AsmrThemeGroup.model, Color(0xFF2E7D32)),
  reticle('reticle', 'Reticle', AsmrThemeGroup.ui, Color(0xFFFFFFFF)),
  button('button', 'Buttons', AsmrThemeGroup.ui, Color(0xFFFFFFFF)),
  hint('hint', 'Hint', AsmrThemeGroup.ui, Color(0xFFFFFFFF)),
  title('title', 'Title', AsmrThemeGroup.ui, Color(0xFFFFFFFF));

  const AsmrThemeSlot(this.id, this.label, this.group, this.fallback);

  final String id;
  final String label;
  final AsmrThemeGroup group;
  final Color fallback;

  String get menuLabel => switch (group) {
    AsmrThemeGroup.desk => '2D · $label',
    AsmrThemeGroup.model => '3D · $label',
    AsmrThemeGroup.ui => 'UI · $label',
  };

  static AsmrThemeSlot? byId(String id) {
    for (final slot in values) {
      if (slot.id == id) return slot;
    }
    return null;
  }
}

/// Colors and opacities for the ASMR view, by the kind of thing drawn.
///
/// Slider changes show at once. [save] writes them to [file], and [load]
/// reads that file back the next time the view opens.
class AsmrTheme extends ChangeNotifier {
  AsmrTheme({File? file}) : _file = file ?? _defaultFile() {
    for (final slot in AsmrThemeSlot.values) {
      _color[slot] = slot.fallback;
      _opacity[slot] = 1;
    }
  }

  /// `~/.flatmates/asmr_theme.json`, or a temp file under tests.
  static File _defaultFile() {
    if (Platform.environment['FLUTTER_TEST'] == 'true') {
      return File(
        '${Directory.systemTemp.path}/flatmates_asmr_theme_test.json',
      );
    }
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.systemTemp.path;
    return File('$home/.flatmates/asmr_theme.json');
  }

  final File _file;
  final Map<AsmrThemeSlot, Color> _color = {};
  final Map<AsmrThemeSlot, double> _opacity = {};
  int _stamp = 0;

  /// Bumps whenever a color changes, so painters can repaint.
  int get stamp => _stamp;

  Color colorOf(AsmrThemeSlot slot) => _color[slot] ?? slot.fallback;

  /// Paper hue and its paired marking ink; opacity changes never choose a
  /// different material. White is the legacy identity tint for the default.
  AsmrPaper get paperMaterial =>
      colorOf(AsmrThemeSlot.paper).toARGB32() ==
          AsmrThemeSlot.paper.fallback.toARGB32()
      ? kAsmrCraftPaper
      : asmrPaletteForColor(colorOf(AsmrThemeSlot.paper));

  double opacityOf(AsmrThemeSlot slot) => _opacity[slot] ?? 1;

  /// [color] faded by this slot's opacity. A changed slot color also
  /// replaces [color]'s hue. The slot's own default leaves that hue alone,
  /// so a glow and its core can stay different shades of the same thing.
  Color ink(AsmrThemeSlot slot, Color color) {
    final rgb = colorOf(slot);
    final keep = rgb.toARGB32() == slot.fallback.toARGB32();
    return color.withValues(
      red: keep ? color.r : rgb.r,
      green: keep ? color.g : rgb.g,
      blue: keep ? color.b : rgb.b,
      alpha: color.a * opacityOf(slot),
    );
  }

  /// The slot's own color at its opacity.
  Color solid(AsmrThemeSlot slot) =>
      colorOf(slot).withValues(alpha: opacityOf(slot));

  /// White at full strength: paper keeps the color it was printed with.
  bool plain(AsmrThemeSlot slot) =>
      opacityOf(slot) > 0.999 &&
      colorOf(slot).toARGB32() == slot.fallback.toARGB32();

  void setColor(AsmrThemeSlot slot, Color value) {
    final next = value.withValues(alpha: 1);
    if (next.toARGB32() == colorOf(slot).toARGB32()) return;
    _color[slot] = next;
    _stamp++;
    notifyListeners();
  }

  void setOpacity(AsmrThemeSlot slot, double value) {
    final next = value.clamp(0.0, 1.0);
    if ((next - opacityOf(slot)).abs() < 1e-6) return;
    _opacity[slot] = next;
    _stamp++;
    notifyListeners();
  }

  /// Reads the saved theme. Missing or unreadable files leave the defaults.
  Future<void> load() async {
    try {
      if (!await _file.exists()) return;
      final json = jsonDecode(await _file.readAsString());
      if (json is! Map) return;
      var changed = false;
      for (final entry in json.entries) {
        final slot = AsmrThemeSlot.byId(entry.key.toString());
        final raw = entry.value;
        if (slot == null || raw is! Map) continue;
        final color = raw['color'];
        if (color is num) {
          final next = Color(color.toInt()).withValues(alpha: 1);
          if (next.toARGB32() != colorOf(slot).toARGB32()) {
            _color[slot] = next;
            changed = true;
          }
        }
        final opacity = raw['opacity'];
        if (opacity is num) {
          final next = opacity.toDouble().clamp(0.0, 1.0);
          if ((next - opacityOf(slot)).abs() >= 1e-6) {
            _opacity[slot] = next;
            changed = true;
          }
        }
      }
      if (changed) {
        _stamp++;
        notifyListeners();
      }
    } catch (_) {}
  }

  /// Writes the theme to [file].
  void save() {
    try {
      _file.parent.createSync(recursive: true);
      _file.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          for (final slot in AsmrThemeSlot.values)
            slot.id: {
              'color': colorOf(slot).toARGB32(),
              'opacity': opacityOf(slot),
            },
        }),
      );
    } catch (_) {}
  }
}

/// DevTools page: pick a kind of thing, set its color and opacity, then save.
class AsmrThemeEditor extends StatefulWidget {
  const AsmrThemeEditor({super.key, required this.theme});

  final AsmrTheme theme;

  @override
  State<AsmrThemeEditor> createState() => _AsmrThemeEditorState();
}

class _AsmrThemeEditorState extends State<AsmrThemeEditor> {
  AsmrThemeSlot _slot = AsmrThemeSlot.desk;
  bool _saved = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final color = theme.colorOf(_slot);
    final opacity = theme.opacityOf(_slot);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Each kind of thing drawn in the 2D desk, the 3D model, and the controls. Color replaces its hue. Opacity fades it. Save writes the theme, and the view reads it back next time.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.45),
            fontSize: 10,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 8),
        DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: DropdownButton<AsmrThemeSlot>(
              key: const Key('asmr-theme-slot'),
              value: _slot,
              isExpanded: true,
              dropdownColor: const Color(0xFF1A1A1A),
              underline: const SizedBox.shrink(),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              items: [
                for (final slot in AsmrThemeSlot.values)
                  DropdownMenuItem(value: slot, child: Text(slot.menuLabel)),
              ],
              onChanged: (slot) {
                if (slot == null) return;
                setState(() => _slot = slot);
              },
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: theme.solid(_slot),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.white54),
              ),
            ),
            const Spacer(),
            TextButton(
              key: const Key('asmr-theme-save'),
              onPressed: () {
                theme.save();
                setState(() => _saved = true);
              },
              child: Text(
                _saved ? 'Saved' : 'Save theme',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        if (_slot == AsmrThemeSlot.paper)
          DropdownButton<AsmrPaper>(
            key: const Key('asmr-paper-palette'),
            value: theme.paperMaterial,
            isExpanded: true,
            dropdownColor: const Color(0xFF242237),
            items: [
              for (final paper in kAsmrCraftPalette)
                DropdownMenuItem(
                  value: paper,
                  child: Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        color: paper.color,
                        child: Center(
                          child: Container(
                            width: 10,
                            height: 10,
                            color: paper.markingColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        paper.name,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
            ],
            onChanged: (paper) {
              if (paper == null) return;
              theme.setColor(_slot, paper.color);
              setState(() => _saved = false);
            },
          )
        else ...[
          _channel('Red', color.r, (value) {
            theme.setColor(_slot, color.withValues(red: value));
            setState(() => _saved = false);
          }),
          _channel('Green', color.g, (value) {
            theme.setColor(_slot, color.withValues(green: value));
            setState(() => _saved = false);
          }),
          _channel('Blue', color.b, (value) {
            theme.setColor(_slot, color.withValues(blue: value));
            setState(() => _saved = false);
          }),
        ],
        _channel('Opacity', opacity, (value) {
          theme.setOpacity(_slot, value);
          setState(() => _saved = false);
        }, max: 1),
      ],
    );
  }

  Widget _channel(
    String label,
    double value,
    ValueChanged<double> onChanged, {
    double max = 1,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 58,
          child: Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
        Expanded(
          child: Slider(
            key: Key('asmr-theme-${label.toLowerCase()}'),
            value: value.clamp(0.0, max),
            max: max,
            activeColor: Colors.white70,
            inactiveColor: Colors.white24,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
