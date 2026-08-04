import 'package:flutter/material.dart';
import '../rendering/iso/iso_camera.dart';

/// Asset rotation controls shown in edit panel
class IsoAssetEditControls extends StatelessWidget {
  const IsoAssetEditControls({
    super.key,
    required this.currentDirection,
    required this.onRotate,
    required this.onDone,
  });

  final IsoViewDirection currentDirection;
  final Function(IsoViewDirection) onRotate;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.yellow.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          const Text(
            'Rotate Asset',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildRotationButton(IsoViewDirection.nw, 'NW'),
              _buildRotationButton(IsoViewDirection.sw, 'SW'),
              _buildRotationButton(IsoViewDirection.se, 'SE'),
              _buildRotationButton(IsoViewDirection.ne, 'NE'),
            ],
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: onDone,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 36),
            ),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Widget _buildRotationButton(IsoViewDirection direction, String label) {
    final isSelected = direction == currentDirection;
    return ElevatedButton(
      onPressed: () => onRotate(direction),
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected ? Colors.yellow : Colors.grey[800],
        foregroundColor: isSelected ? Colors.black : Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: const Size(50, 36),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }
}
