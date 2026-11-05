import 'models.dart';
import 'dart:async';
import 'dart:math' as math;
import 'fog_settings.dart';
import 'package:flutter/material.dart';
import 'storage.dart';
import 'appearance.dart';
import 'stroke_color_picker.dart';

class ProtoplaneSettings {
  FogSettings fog = FogSettings();
  double nearestDistance = 2, farthestDistance = 25;
  WorldPreset worldPreset = WorldPreset.paper;
  double tileGridOpacity = .12;
  int focusContextTiles = 1;
  bool showSafeZone = false;
  bool showGestureDebug = false;
  double focusContextOpacity = .35;
  static const defaultBackgroundColors = [
    Color(0xff263b70),
    Color(0xff765184),
    Color(0xffe9a072),
  ];
  List<Color> backgroundColors = List.of(defaultBackgroundColors);
  LinearGradient get backgroundGradient => LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    colors: backgroundColors,
    stops: const [0, .5, 1],
  );

  SurfaceAppearance paperTextureAppearance = SurfaceAppearance();
  double paperTextureStrength = .6, paperTextureRepeat = 2;
  Color cutLineColor = const Color(0xffff4040);
  Color? _lineColor;
  Color get lineColor => _lineColor ?? const Color(0xff7fff00);
  set lineColor(Color value) => _lineColor = value;
  int effectDurationMs = 400;
  bool haptics = true, screenShake = true;
  SurfaceAppearance landscapeAppearance = SurfaceAppearance(),
      craftedAppearance = SurfaceAppearance();
  bool gridLines = false;
  int protoplaneCells = 3;
  GridConnections? _gridConnections;
  GridConnections get gridConnections =>
      _gridConnections ?? GridConnections.orthogonal;
  set gridConnections(GridConnections value) => _gridConnections = value;
  bool resetDrawingOnRelease = true;
  bool disableFocusZoom = true;
  double entryFocusLevel = 1;
  double ambient = .7, sun = .25, wallNear = 4, wallFar = 8;
  Map<String, dynamic> toJson() => {
    'version': 1,
    'fog': fog.toJson(),
    'nearestDistance': nearestDistance,
    'farthestDistance': farthestDistance,
    'paperWorldDefault': true,
    'tileGridOpacity': tileGridOpacity,
    'focusContextTiles': focusContextTiles,
    'showSafeZone': showSafeZone,
    'showGestureDebug': showGestureDebug,
    'focusContextOpacity': focusContextOpacity,
    'paperTextureAppearance': paperTextureAppearance.toJson(),
    'paperTextureStrength': paperTextureStrength,
    'paperTextureRepeat': paperTextureRepeat,
    'backgroundColors': backgroundColors
        .map((color) => color.toARGB32())
        .toList(),
    'landscapeAppearance': landscapeAppearance.toJson(),
    'craftedAppearance': craftedAppearance.toJson(),
    'lineColor': lineColor.toARGB32(),
    'cutLineColor': cutLineColor.toARGB32(),
    'effectDurationMs': effectDurationMs,
    'haptics': haptics,
    'screenShake': screenShake,
    'worldPreset': worldPreset.name,
    'protoplaneCells': protoplaneCells,
    'gridConnections': gridConnections.name,
    'entryFocusLevel': entryFocusLevel,
    'disableFocusZoom': disableFocusZoom,
    'gridLines': gridLines,
    'resetDrawingOnRelease': resetDrawingOnRelease,
    'ambient': ambient,
    'sun': sun,
    'wallNear': wallNear,
    'wallFar': wallFar,
  };
  void load(Map<String, dynamic> json) {
    if (json['version'] != 1 || json['gridLines'] is! bool) {
      throw const FormatException('Invalid settings');
    }
    double number(String key, double min, double max) {
      final value = json[key];
      if (value is! num || !value.isFinite || value < min || value > max) {
        throw const FormatException('Invalid settings');
      }
      return value.toDouble();
    }

    fog = FogSettings.fromJson(json['fog']);
    nearestDistance = json.containsKey('nearestDistance')
        ? number('nearestDistance', 1, 59.5)
        : 2;
    farthestDistance = json.containsKey('farthestDistance')
        ? number('farthestDistance', 1.5, 60)
        : 25;
    if (farthestDistance - nearestDistance < .5) {
      throw const FormatException('Invalid camera limits');
    }
    final texture = SurfaceAppearance.fromJson(json['paperTextureAppearance']);
    final strength = json.containsKey('paperTextureStrength')
        ? number('paperTextureStrength', 0, 1)
        : .6;
    final repeat = json.containsKey('paperTextureRepeat')
        ? number('paperTextureRepeat', .25, 8)
        : 2.0;
    paperTextureAppearance = texture;
    paperTextureStrength = strength;
    paperTextureRepeat = repeat;
    final a = number('ambient', 0, 1),
        s = number('sun', 0, 1),
        n = number('wallNear', 1, 8),
        f = number('wallFar', 2, 16);
    if (f <= n) throw const FormatException('Invalid wall range');
    final focus = json.containsKey('entryFocusLevel')
        ? number('entryFocusLevel', 0, 1)
        : 1.0;
    final disabled = json['disableFocusZoom'] ?? true;
    if (disabled is! bool) {
      throw const FormatException('Invalid focus zoom setting');
    }
    final reset = json['resetDrawingOnRelease'] ?? true;
    if (reset is! bool) {
      throw const FormatException('Invalid drawing reset setting');
    }
    final cells = json['protoplaneCells'] ?? 3;
    if (cells is! int || cells < 1 || cells > 5) {
      throw const FormatException('Invalid grid resolution');
    }
    worldPreset = json['paperWorldDefault'] == true
        ? WorldPreset.values.byName(json['worldPreset'] ?? 'paper')
        : WorldPreset.paper;
    tileGridOpacity = json.containsKey('tileGridOpacity')
        ? number('tileGridOpacity', 0, 1)
        : .12;
    final safeZone = json['showSafeZone'] ?? false;
    if (safeZone is! bool) {
      throw const FormatException('Invalid safe zone setting');
    }
    final gestures = json['showGestureDebug'] ?? false;
    if (gestures is! bool) {
      throw const FormatException('Invalid gesture debug setting');
    }
    showGestureDebug = gestures;
    showSafeZone = safeZone;
    final contextTiles = json['focusContextTiles'] ?? 1;
    if (contextTiles is! int || contextTiles < 0 || contextTiles > 4) {
      throw const FormatException('Invalid context distance');
    }
    focusContextTiles = contextTiles;
    focusContextOpacity = json.containsKey('focusContextOpacity')
        ? number('focusContextOpacity', 0, 1)
        : .35;
    final rgb = json['lineColor'] ?? 0xff7fff00;
    if (rgb is! int || rgb < 0xff000000 || rgb > 0xffffffff) {
      throw const FormatException('Invalid line color');
    }
    lineColor = Color(rgb);
    final cutRgb = json['cutLineColor'] ?? 0xffff4040;
    if (cutRgb is! int || cutRgb < 0xff000000 || cutRgb > 0xffffffff) {
      throw const FormatException('Invalid cutting line color');
    }
    cutLineColor = Color(cutRgb);
    final background = json['backgroundColors'];
    if (background != null &&
        (background is! List ||
            background.length != 3 ||
            background.any(
              (v) => v is! int || v < 0xff000000 || v > 0xffffffff,
            ))) {
      throw const FormatException('Invalid background colors');
    }
    backgroundColors = background == null
        ? List.of(defaultBackgroundColors)
        : (background as List).map((v) => Color(v as int)).toList();

    final effectDuration = json['effectDurationMs'] ?? 400;
    final hapticSetting = json['haptics'] ?? true;
    final shakeSetting = json['screenShake'] ?? true;
    if (effectDuration is! int ||
        effectDuration < 100 ||
        effectDuration > 1000 ||
        hapticSetting is! bool ||
        shakeSetting is! bool) {
      throw const FormatException('Invalid paper effect settings');
    }
    effectDurationMs = effectDuration;
    haptics = hapticSetting;
    screenShake = shakeSetting;
    gridConnections = GridConnections.values.byName(
      json['gridConnections'] ?? 'orthogonal',
    );
    protoplaneCells = cells;
    final natural = SurfaceAppearance.fromJson(json['landscapeAppearance']);
    final crafted = SurfaceAppearance.fromJson(json['craftedAppearance']);
    landscapeAppearance = natural;
    craftedAppearance = crafted;
    resetDrawingOnRelease = reset;
    disableFocusZoom = disabled;
    entryFocusLevel = focus;
    gridLines = json['gridLines'];
    ambient = a;
    sun = s;
    wallNear = n;
    wallFar = f;
  }
}

/// Landscape adjustments stay separate from active settings until Update.
/// Copy on apply so subsequent slider drags cannot mutate the live appearance.
class LandscapeStyleDraft {
  LandscapeStyleDraft(ProtoplaneSettings settings)
    : fill = SurfaceAppearance.fromJson(settings.landscapeAppearance.toJson()),
      grain = SurfaceAppearance.fromJson(
        settings.paperTextureAppearance.toJson(),
      ),
      strength = settings.paperTextureStrength,
      repeat = settings.paperTextureRepeat;
  final SurfaceAppearance fill, grain;
  double strength, repeat;
  void applyTo(ProtoplaneSettings settings) {
    settings.landscapeAppearance = SurfaceAppearance.fromJson(fill.toJson());
    settings.paperTextureAppearance = SurfaceAppearance.fromJson(
      grain.toJson(),
    );
    settings.paperTextureStrength = strength;
    settings.paperTextureRepeat = repeat;
  }
}

Future<void> showProtoplaneDevTools(
  BuildContext context,
  ProtoplaneSettings settings,
  ProtoplaneStorage store,
  VoidCallback changed, {
  String? initialError,
  VoidCallback? clearWorld,
  VoidCallback? revealAllAreas,
  Future<void> Function(WorldPreset)? switchWorld,
}) {
  final done = Completer<void>();
  final size = MediaQuery.sizeOf(context),
      padding = MediaQuery.paddingOf(context);
  final top = padding.top + 80;
  late OverlayEntry entry;
  void close() {
    entry.remove();
    if (!done.isCompleted) done.complete();
  }

  entry = OverlayEntry(
    builder: (context) => Positioned(
      left: 20,
      top: top,
      width: math.min(420, math.max(1, size.width - 40)),
      height: math.min(
        460,
        math.max(1, size.height - top - padding.bottom - 20),
      ),
      child: ProtoplaneDevToolsPanel(
        settings: settings,
        store: store,
        changed: changed,
        onClose: close,
        initialError: initialError,
        clearWorld: clearWorld,
        revealAllAreas: revealAllAreas,
        switchWorld: switchWorld,
      ),
    ),
  );
  Overlay.of(context).insert(entry);
  return done.future;
}

class ProtoplaneDevToolsPanel extends StatefulWidget {
  const ProtoplaneDevToolsPanel({
    super.key,
    required this.settings,
    required this.store,
    required this.changed,
    required this.onClose,
    this.initialError,
    this.clearWorld,
    this.revealAllAreas,
    this.switchWorld,
  });
  final ProtoplaneSettings settings;
  final ProtoplaneStorage store;
  final VoidCallback changed, onClose;
  final String? initialError;
  final VoidCallback? clearWorld, revealAllAreas;
  final Future<void> Function(WorldPreset)? switchWorld;
  @override
  State<ProtoplaneDevToolsPanel> createState() =>
      _ProtoplaneDevToolsPanelState();
}

class _ProtoplaneDevToolsPanelState extends State<ProtoplaneDevToolsPanel> {
  ProtoplaneSettings get settings => widget.settings;
  ProtoplaneStorage get store => widget.store;
  VoidCallback get changed => widget.changed;
  VoidCallback? get clearWorld => widget.clearWorld;
  VoidCallback? get revealAllAreas => widget.revealAllAreas;
  Future<void> Function(WorldPreset)? get switchWorld => widget.switchWorld;
  late String? error = widget.initialError;
  bool switching = false, landscapeDirty = false;
  late LandscapeStyleDraft landscapeDraft = LandscapeStyleDraft(settings);
  void update(VoidCallback change) {
    if (mounted) setState(change);
  }

  @override
  Widget build(BuildContext context) {
    Widget slider(
      String label,
      double value,
      double min,
      double max,
      ValueChanged<double> set, {
      bool deferred = false,
    }) => Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(child: Text(label)),
              Text(
                value.toStringAsFixed(2),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        Slider(
          key: ValueKey(label),
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: (v) {
            update(() {
              set(v);
              if (deferred) landscapeDirty = true;
            });
            if (!deferred) changed();
          },
        ),
      ],
    );
    return Material(
      elevation: 8,
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: RepaintBoundary(
        key: const ValueKey('protoplane-devtools-panel'),
        child: LayoutBuilder(
          builder: (context, constraints) => FittedBox(
            fit: BoxFit.fill,
            child: SizedBox(
              width: constraints.maxWidth / .75,
              height: constraints.maxHeight / .75,
              child: DefaultTabController(
                length: 5,
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('Devtools'),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => widget.onClose(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const TabBar(
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      labelPadding: EdgeInsets.symmetric(horizontal: 6),
                      labelStyle: TextStyle(fontSize: 14),
                      tabs: [
                        Tab(text: 'Crafting'),
                        Tab(text: 'Lighting'),
                        Tab(text: 'Camera'),
                        Tab(text: 'Style'),
                        Tab(text: 'Fog'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          ListView(
                            children: [
                              if (switchWorld != null)
                                Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: SegmentedButton<WorldPreset>(
                                      segments: [
                                        for (final preset in WorldPreset.values)
                                          ButtonSegment(
                                            value: preset,
                                            label: Text(preset.label),
                                          ),
                                      ],
                                      selected: {settings.worldPreset},
                                      onSelectionChanged: switching
                                          ? null
                                          : (selection) async {
                                              update(() => switching = true);
                                              try {
                                                await switchWorld!(
                                                  selection.single,
                                                );
                                                if (context.mounted) {
                                                  update(() => error = null);
                                                }
                                              } catch (_) {
                                                if (context.mounted) {
                                                  update(
                                                    () => error =
                                                        'Could not switch world. Retry saving or reload.',
                                                  );
                                                }
                                              } finally {
                                                if (context.mounted) {
                                                  update(
                                                    () => switching = false,
                                                  );
                                                }
                                              }
                                            },
                                    ),
                                  ),
                                ),
                              if (clearWorld != null)
                                ListTile(
                                  title: const Text('Clear world'),
                                  leading: const Icon(Icons.delete_outline),
                                  onTap: () {
                                    clearWorld!();
                                    widget.onClose();
                                  },
                                ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: Column(
                                  children: [
                                    Text(
                                      'Protoplane cells ${settings.protoplaneCells} × ${settings.protoplaneCells}',
                                    ),
                                    Slider(
                                      value: settings.protoplaneCells
                                          .toDouble(),
                                      min: 1,
                                      max: 5,
                                      divisions: 4,
                                      label: '${settings.protoplaneCells}',
                                      onChanged: (v) {
                                        update(
                                          () => settings.protoplaneCells = v
                                              .round(),
                                        );
                                        changed();
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              SwitchListTile(
                                title: const Text('Reset drawing on release'),
                                value: settings.resetDrawingOnRelease,
                                onChanged: (value) {
                                  update(
                                    () =>
                                        settings.resetDrawingOnRelease = value,
                                  );
                                  changed();
                                },
                              ),
                              ListTile(
                                title: const Text('Context tiles'),
                                trailing: Text('${settings.focusContextTiles}'),
                                subtitle: Slider(
                                  key: const ValueKey('Context tiles'),
                                  value: settings.focusContextTiles.toDouble(),
                                  min: 0,
                                  max: 4,
                                  divisions: 4,
                                  label: '${settings.focusContextTiles}',
                                  onChanged: (v) {
                                    update(
                                      () => settings.focusContextTiles = v
                                          .round(),
                                    );
                                    changed();
                                  },
                                ),
                              ),
                              ListTile(
                                title: const Text('Context opacity'),
                                trailing: Text(
                                  '${(settings.focusContextOpacity * 100).round()}%',
                                ),
                                subtitle: Slider(
                                  key: const ValueKey('Context opacity'),
                                  value: settings.focusContextOpacity,
                                  min: 0,
                                  max: 1,
                                  onChanged: (v) {
                                    update(
                                      () => settings.focusContextOpacity = v,
                                    );
                                    changed();
                                  },
                                ),
                              ),
                              ListTile(
                                title: const Text('Tile grid opacity'),
                                subtitle: Slider(
                                  key: const ValueKey('Tile grid opacity'),
                                  value: settings.tileGridOpacity,
                                  min: 0,
                                  max: 1,
                                  label:
                                      '${(settings.tileGridOpacity * 100).round()}%',
                                  onChanged: (v) {
                                    update(() => settings.tileGridOpacity = v);
                                    changed();
                                  },
                                ),
                              ),
                              SwitchListTile(
                                title: const Text('Grid connection lines'),
                                value: settings.gridLines,
                                onChanged: (v) {
                                  update(() => settings.gridLines = v);
                                  changed();
                                },
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: DropdownButtonFormField<GridConnections>(
                                  key: ValueKey(settings.gridConnections),
                                  isExpanded: true,
                                  initialValue: settings.gridConnections,
                                  decoration: const InputDecoration(
                                    labelText: 'Connections',
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: GridConnections.orthogonal,
                                      child: Text('□  Orthogonal neighbors'),
                                    ),
                                    DropdownMenuItem(
                                      value: GridConnections.diagonal,
                                      child: Text('○  Diagonal neighbors'),
                                    ),
                                    DropdownMenuItem(
                                      value: GridConnections.arbitrary,
                                      child: Text('☆  Any point'),
                                    ),
                                  ],
                                  onChanged: (value) {
                                    if (value != null) {
                                      update(
                                        () => settings.gridConnections = value,
                                      );
                                      changed();
                                    }
                                  },
                                ),
                              ),
                              ListTile(
                                title: const Text('Cutting line color'),
                                trailing: Container(
                                  width: 28,
                                  height: 28,
                                  color: settings.cutLineColor,
                                ),
                                onTap: () => showStrokeColorPicker(
                                  context,
                                  settings.cutLineColor,
                                  (color) {
                                    update(() => settings.cutLineColor = color);
                                    changed();
                                  },
                                ),
                              ),
                              ListTile(
                                title: const Text('Addition line color'),
                                trailing: Container(
                                  width: 28,
                                  height: 28,
                                  color: settings.lineColor,
                                ),
                                onTap: () => showStrokeColorPicker(
                                  context,
                                  settings.lineColor,
                                  (color) {
                                    update(() => settings.lineColor = color);
                                    changed();
                                  },
                                ),
                              ),
                              ListTile(
                                title: Text(
                                  'Effect duration ${settings.effectDurationMs} ms',
                                ),
                                subtitle: Slider(
                                  value: settings.effectDurationMs.toDouble(),
                                  min: 100,
                                  max: 1000,
                                  divisions: 18,
                                  onChanged: (value) {
                                    update(
                                      () => settings.effectDurationMs = value
                                          .round(),
                                    );
                                    changed();
                                  },
                                ),
                              ),
                              SwitchListTile(
                                title: const Text('Haptics'),
                                value: settings.haptics,
                                onChanged: (value) {
                                  update(() => settings.haptics = value);
                                  changed();
                                },
                              ),
                              SwitchListTile(
                                title: const Text('Screen shake'),
                                value: settings.screenShake,
                                onChanged: (value) {
                                  update(() => settings.screenShake = value);
                                  changed();
                                },
                              ),
                            ],
                          ),
                          ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              slider(
                                'Ambient GI',
                                settings.ambient,
                                0,
                                1,
                                (v) => settings.ambient = v,
                              ),
                              slider(
                                'Sun',
                                settings.sun,
                                0,
                                1,
                                (v) => settings.sun = v,
                              ),
                            ],
                          ),
                          ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              SwitchListTile(
                                title: const Text('Gesture overlay'),
                                value: settings.showGestureDebug,
                                onChanged: (v) {
                                  update(() => settings.showGestureDebug = v);
                                  changed();
                                },
                              ),
                              SwitchListTile(
                                title: const Text('Safe zone'),
                                value: settings.showSafeZone,
                                onChanged: (v) {
                                  update(() => settings.showSafeZone = v);
                                  changed();
                                },
                              ),
                              SwitchListTile(
                                title: const Text('Disable focus zoom'),
                                value: settings.disableFocusZoom,
                                onChanged: (value) {
                                  update(
                                    () => settings.disableFocusZoom = value,
                                  );
                                  changed();
                                },
                              ),
                              slider(
                                'Entry focus level',
                                settings.entryFocusLevel,
                                0,
                                1,
                                (v) => settings.entryFocusLevel = v,
                              ),
                              slider(
                                'Wall reveal near',
                                settings.wallNear,
                                1,
                                8,
                                (v) {
                                  settings.wallNear = v;
                                  if (settings.wallFar <= v) {
                                    settings.wallFar = v + .5;
                                  }
                                },
                              ),
                              slider(
                                'Wall restore far',
                                settings.wallFar,
                                settings.wallNear + .1,
                                16,
                                (v) => settings.wallFar = v,
                              ),
                              slider(
                                'Nearest distance',
                                settings.nearestDistance,
                                1,
                                settings.farthestDistance - .5,
                                (v) => settings.nearestDistance = v,
                              ),
                              slider(
                                'Farthest distance',
                                settings.farthestDistance,
                                settings.nearestDistance + .5,
                                60,
                                (v) => settings.farthestDistance = v,
                              ),
                            ],
                          ),
                          ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              const Text('Background'),
                              Container(
                                height: 100,
                                margin: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  gradient: settings.backgroundGradient,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              Row(
                                children: [
                                  for (final (index, label) in [
                                    'Bottom',
                                    'Middle',
                                    'Top',
                                  ].indexed)
                                    Expanded(
                                      child: TextButton.icon(
                                        icon: Container(
                                          width: 16,
                                          height: 16,
                                          decoration: BoxDecoration(
                                            color: settings
                                                .backgroundColors[index],
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        label: Text(label),
                                        onPressed: () => showStrokeColorPicker(
                                          context,
                                          settings.backgroundColors[index],
                                          (color) {
                                            update(
                                              () => settings.backgroundColors =
                                                  [...settings.backgroundColors]
                                                    ..[index] = color,
                                            );
                                            changed();
                                          },
                                          title: 'Background $label',
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const Divider(height: 24),
                              const Text('Paper texture'),
                              slider(
                                'Texture strength',
                                landscapeDraft.strength,
                                0,
                                1,
                                (v) => landscapeDraft.strength = v,
                                deferred: true,
                              ),
                              slider(
                                'Texture scale',
                                landscapeDraft.repeat,
                                .25,
                                8,
                                (v) => landscapeDraft.repeat = v,
                                deferred: true,
                              ),
                              slider(
                                'Texture brightness',
                                landscapeDraft.grain.brightness,
                                -1,
                                1,
                                (v) => landscapeDraft.grain.brightness = v,
                                deferred: true,
                              ),
                              slider(
                                'Texture contrast',
                                landscapeDraft.grain.contrast,
                                0,
                                2,
                                (v) => landscapeDraft.grain.contrast = v,
                                deferred: true,
                              ),
                              const Divider(height: 24),
                              for (final entry in {
                                'Landscape fills / patterns':
                                    landscapeDraft.fill,
                                'Crafted geometry': settings.craftedAppearance,
                              }.entries) ...[
                                Text(entry.key),
                                slider(
                                  'Brightness',
                                  entry.value.brightness,
                                  -1,
                                  1,
                                  (v) => entry.value.brightness = v,
                                  deferred:
                                      entry.key == 'Landscape fills / patterns',
                                ),
                                slider(
                                  'Contrast',
                                  entry.value.contrast,
                                  0,
                                  2,
                                  (v) => entry.value.contrast = v,
                                  deferred:
                                      entry.key == 'Landscape fills / patterns',
                                ),
                                slider(
                                  'Saturation',
                                  entry.value.saturation,
                                  0,
                                  2,
                                  (v) => entry.value.saturation = v,
                                  deferred:
                                      entry.key == 'Landscape fills / patterns',
                                ),
                                slider(
                                  'Hue',
                                  entry.value.hue,
                                  -180,
                                  180,
                                  (v) => entry.value.hue = v,
                                  deferred:
                                      entry.key == 'Landscape fills / patterns',
                                ),
                              ],
                            ],
                          ),
                          FogControls(
                            settings: settings.fog,
                            changed: () {
                              update(() {});
                              changed();
                            },
                            revealAll: revealAllAreas,
                          ),
                        ],
                      ),
                    ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(error!),
                      ),
                    Wrap(
                      alignment: WrapAlignment.end,
                      children: [
                        TextButton(
                          onPressed: landscapeDirty
                              ? () {
                                  landscapeDraft.applyTo(settings);
                                  update(() => landscapeDirty = false);
                                  changed();
                                }
                              : null,
                          child: const Text('Update'),
                        ),
                        TextButton(
                          onPressed: () async {
                            try {
                              final json = await store.load(
                                (j) => ProtoplaneSettings()..load(j),
                              );
                              final activePreset = settings.worldPreset;
                              if (json != null) settings.load(json);
                              settings.worldPreset = activePreset;
                              landscapeDraft = LandscapeStyleDraft(settings);
                              landscapeDirty = false;
                              changed();
                              update(() => error = null);
                            } catch (_) {
                              update(() => error = 'Could not load settings');
                            }
                          },
                          child: const Text('Reload'),
                        ),
                        TextButton(
                          onPressed: () async {
                            try {
                              if (landscapeDirty) {
                                landscapeDraft.applyTo(settings);
                                landscapeDirty = false;
                                changed();
                              }
                              await store.save(settings.toJson());
                              update(() => error = 'Saved');
                            } catch (_) {
                              update(
                                () => error =
                                    'Could not save settings; reload first',
                              );
                            }
                          },
                          child: const Text('Save'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
