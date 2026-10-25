import 'package:flutter/material.dart';

import 'workview.dart';

/// The Workviews page of the craft room's DevTools: how the workview that
/// is not active is drawn under the active one.
class WorkviewPage extends StatelessWidget {
  const WorkviewPage({super.key, required this.settings});

  final WorkviewSettings settings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => Column(
        key: const Key('workview-settings'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How the inactive workview is drawn under the active one. Double-tap empty space to switch.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 10,
              height: 1.3,
            ),
          ),
          _Row(
            label: 'Opacity',
            sliderKey: const Key('workview-opacity'),
            value: settings.opacity,
            max: 1,
            divisions: 20,
            readout: '${(settings.opacity * 100).round()}%',
            onChanged: (value) => settings.opacity = value,
          ),
          _Row(
            label: 'Blur',
            sliderKey: const Key('workview-blur'),
            value: settings.blur,
            max: 20,
            divisions: 40,
            readout: settings.blur.toStringAsFixed(1),
            onChanged: (value) => settings.blur = value,
          ),
          _Row(
            label: 'Saturation',
            sliderKey: const Key('workview-saturation'),
            value: settings.saturation,
            max: 2,
            divisions: 40,
            readout: '${(settings.saturation * 100).round()}%',
            onChanged: (value) => settings.saturation = value,
          ),
          _Row(
            label: 'Brightness',
            sliderKey: const Key('workview-brightness'),
            value: settings.brightness,
            max: 2,
            divisions: 40,
            readout: '${(settings.brightness * 100).round()}%',
            onChanged: (value) => settings.brightness = value,
          ),
          _Row(
            label: 'Switch',
            sliderKey: const Key('workview-switch'),
            value: settings.switchMs,
            max: 1000,
            divisions: 20,
            readout: '${settings.switchMs.round()}ms',
            onChanged: (value) => settings.switchMs = value,
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.sliderKey,
    required this.value,
    required this.max,
    required this.divisions,
    required this.readout,
    required this.onChanged,
  });

  final String label;
  final Key sliderKey;
  final double value;
  final double max;
  final int divisions;
  final String readout;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 68,
          child: Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ),
        Expanded(
          child: Slider(
            key: sliderKey,
            value: value.clamp(0.0, max),
            max: max,
            divisions: divisions,
            activeColor: Colors.white70,
            inactiveColor: Colors.white24,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            readout,
            textAlign: TextAlign.right,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ),
      ],
    );
  }
}
