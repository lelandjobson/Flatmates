import 'materials.dart';
import 'package:flutter/material.dart';
import 'storage.dart';

class ProtoplaneSettings {
  WorldPreset worldPreset = WorldPreset.ink;
  bool gridLines = false;
  int protoplaneCells = 3;
  bool resetDrawingOnRelease = true;
  bool disableFocusZoom = true;
  double entryFocusLevel = 1;
  double ambient = .7, sun = .25, wallNear = 4, wallFar = 8;
  Map<String, dynamic> toJson() => {
    'version': 1,
    'worldPreset': worldPreset.name,
    'protoplaneCells': protoplaneCells,
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
    worldPreset = WorldPreset.values.byName(json['worldPreset'] ?? 'ink');
    protoplaneCells = cells;
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

Future<void> showProtoplaneDevTools(
  BuildContext context,
  ProtoplaneSettings settings,
  ProtoplaneStorage store,
  VoidCallback changed, {
  String? initialError,
  VoidCallback? clearWorld,
  Future<void> Function(WorldPreset)? switchWorld,
}) async {
  String? error = initialError;
  bool switching = false;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, update) {
        Widget slider(
          String label,
          double value,
          double min,
          double max,
          ValueChanged<double> set,
        ) => Column(
          children: [
            Text('$label ${value.toStringAsFixed(2)}'),
            Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: (v) {
                update(() => set(v));
                changed();
              },
            ),
          ],
        );
        return Dialog(
          child: SizedBox(
            width: 480,
            height: 520,
            child: DefaultTabController(
              length: 3,
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
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const TabBar(
                    tabs: [
                      Tab(text: 'Crafting'),
                      Tab(text: 'Lighting'),
                      Tab(text: 'Camera'),
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
                                            await switchWorld(selection.single);
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
                                              update(() => switching = false);
                                            }
                                          }
                                        },
                                ),
                              ),
                            if (clearWorld != null)
                              ListTile(
                                title: const Text('Clear world'),
                                leading: const Icon(Icons.delete_outline),
                                onTap: () {
                                  clearWorld();
                                  Navigator.pop(context);
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
                                    value: settings.protoplaneCells.toDouble(),
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
                                  () => settings.resetDrawingOnRelease = value,
                                );
                                changed();
                              },
                            ),
                            SwitchListTile(
                              title: const Text('Grid connection lines'),
                              value: settings.gridLines,
                              onChanged: (v) {
                                update(() => settings.gridLines = v);
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
                              title: const Text('Disable focus zoom'),
                              value: settings.disableFocusZoom,
                              onChanged: (value) {
                                update(() => settings.disableFocusZoom = value);
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
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(error!),
                    ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () async {
                          try {
                            final json = await store.load(
                              (j) => ProtoplaneSettings()..load(j),
                            );
                            final activePreset = settings.worldPreset;
                            if (json != null) settings.load(json);
                            settings.worldPreset = activePreset;
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
        );
      },
    ),
  );
}
