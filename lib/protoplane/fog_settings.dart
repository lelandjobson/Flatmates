import 'package:flutter/material.dart';
import 'stroke_color_picker.dart';

enum FogTheme {
  paper('Paper clouds', Color(0xffe8e6df), Color(0xfffaf9f5)),
  charcoal('Charcoal mist', Color(0xff272a30), Color(0xff555b65)),
  background('Background haze', Color(0xff765184), Color(0xffc69e9a));

  const FogTheme(this.label, this.base, this.highlight);
  final String label;
  final Color base, highlight;
}

class FogStyle {
  FogStyle(FogTheme theme) : base = theme.base, highlight = theme.highlight;
  Color base, highlight;
  double opacity = 1,
      margin = .35,
      softness = 4,
      scale = 2,
      contrast = .2,
      speed = .03,
      depth = .35;
  Map<String, dynamic> toJson() => {
    'base': base.toARGB32(),
    'highlight': highlight.toARGB32(),
    'opacity': opacity,
    'margin': margin,
    'softness': softness,
    'scale': scale,
    'contrast': contrast,
    'speed': speed,
    'depth': depth,
  };
  static FogStyle fromJson(FogTheme theme, dynamic json) {
    final s = FogStyle(theme);
    if (json == null) return s;
    if (json is! Map) throw const FormatException('Invalid fog style');
    double n(String key, double min, double max) {
      final v = json[key];
      if (v is! num || !v.isFinite || v < min || v > max) {
        throw const FormatException('Invalid fog style');
      }
      return v.toDouble();
    }

    Color color(String key) {
      final v = json[key];
      if (v is! int || v < 0 || v > 0xffffffff || v >> 24 != 255) {
        throw const FormatException('Invalid fog color');
      }
      return Color(v);
    }

    s.base = color('base');
    s.highlight = color('highlight');
    s.opacity = n('opacity', 0, 1);
    s.margin = n('margin', 0, 3);
    s.softness = n('softness', .25, 8);
    s.scale = n('scale', .5, 8);
    s.contrast = n('contrast', 0, 1);
    s.speed = n('speed', 0, .3);
    s.depth = n('depth', 0, 1);
    return s;
  }
}

class FogSettings {
  bool enabled = true;
  FogTheme theme = FogTheme.paper;
  final Map<FogTheme, FogStyle> styles = {
    for (final t in FogTheme.values) t: FogStyle(t),
  };
  FogStyle get style => styles[theme]!;
  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'theme': theme.name,
    'styles': {for (final e in styles.entries) e.key.name: e.value.toJson()},
  };
  static FogSettings fromJson(dynamic json) {
    final s = FogSettings();
    if (json == null) return s;
    if (json is! Map ||
        json['enabled'] is! bool ||
        !FogTheme.values.any((t) => t.name == json['theme']) ||
        json['styles'] is! Map) {
      throw const FormatException('Invalid fog settings');
    }
    s.enabled = json['enabled'];
    s.theme = FogTheme.values.byName(json['theme']);
    for (final t in FogTheme.values) {
      s.styles[t] = FogStyle.fromJson(t, json['styles'][t.name]);
    }
    return s;
  }
}

class FogControls extends StatelessWidget {
  const FogControls({
    super.key,
    required this.settings,
    required this.changed,
    this.revealAll,
  });
  final FogSettings settings;
  final VoidCallback changed;
  final VoidCallback? revealAll;
  @override
  Widget build(BuildContext context) {
    final s = settings.style;
    Widget slider(
      String label,
      double value,
      double min,
      double max,
      ValueChanged<double> set,
    ) => Column(
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            Text(
              label == 'Opacity' || label == 'Cloud contrast'
                  ? '${(value * 100).round()}%'
                  : value.toStringAsFixed(2),
            ),
          ],
        ),
        Slider(
          key: ValueKey('Fog $label'),
          value: value,
          min: min,
          max: max,
          onChanged: (v) {
            set(v);
            changed();
          },
        ),
      ],
    );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SwitchListTile(
          title: const Text('Fog'),
          value: settings.enabled,
          onChanged: (v) {
            settings.enabled = v;
            changed();
          },
        ),
        DropdownButton<FogTheme>(
          isExpanded: true,
          value: settings.theme,
          items: [
            for (final t in FogTheme.values)
              DropdownMenuItem(value: t, child: Text(t.label)),
          ],
          onChanged: (v) {
            if (v != null) {
              settings.theme = v;
              changed();
            }
          },
        ),
        Row(
          children: [
            for (final highlight in [false, true])
              Expanded(
                child: TextButton.icon(
                  icon: Icon(
                    Icons.circle,
                    color: highlight ? s.highlight : s.base,
                  ),
                  label: Text(highlight ? 'Highlight' : 'Base'),
                  onPressed: () => showStrokeColorPicker(
                    context,
                    highlight ? s.highlight : s.base,
                    (c) {
                      if (highlight) {
                        s.highlight = c;
                      } else {
                        s.base = c;
                      }
                      changed();
                    },
                    title: highlight ? 'Fog highlight' : 'Fog base',
                  ),
                ),
              ),
          ],
        ),
        slider('Opacity', s.opacity, 0, 1, (v) => s.opacity = v),
        slider('Clear margin', s.margin, 0, 3, (v) => s.margin = v),
        slider('Edge softness', s.softness, .25, 8, (v) => s.softness = v),
        slider('Cloud scale', s.scale, .5, 8, (v) => s.scale = v),
        slider('Cloud contrast', s.contrast, 0, 1, (v) => s.contrast = v),
        slider('Drift speed', s.speed, 0, .3, (v) => s.speed = v),
        slider('Apparent depth', s.depth, 0, 1, (v) => s.depth = v),
        Wrap(
          children: [
            TextButton(
              onPressed: () {
                settings.styles[settings.theme] = FogStyle(settings.theme);
                changed();
              },
              child: const Text('Reset theme'),
            ),
            TextButton(
              onPressed: revealAll,
              child: const Text('Reveal all areas'),
            ),
          ],
        ),
      ],
    );
  }
}
