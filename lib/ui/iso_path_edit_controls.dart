import 'package:flutter/material.dart';

/// Bottom controls for path editing mode
class IsoPathEditControls extends StatelessWidget {
  const IsoPathEditControls({
    super.key,
    required this.canAddSegment,
    required this.onAddSegment,
    required this.onDeleteLast,
    required this.onDone,
    required this.pathLength,
    required this.isAtStart,
    required this.isAtEnd,
    required this.onGoToStart,
    required this.onGoToEnd,
  });

  final bool canAddSegment;
  final VoidCallback onAddSegment;
  final VoidCallback onDeleteLast;
  final VoidCallback onDone;
  final int pathLength;
  final bool isAtStart;
  final bool isAtEnd;
  final VoidCallback onGoToStart;
  final VoidCallback onGoToEnd;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 80,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.grey[900]!.withOpacity(0.95),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.yellow, width: 2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Path Editing',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 12),
              Text(
                'Length: $pathLength/10',
                style: TextStyle(
                  fontSize: 12,
                  color: pathLength >= 10 ? Colors.red : Colors.white70,
                ),
              ),
              const SizedBox(width: 24),
              IconButton(
                icon: const Icon(Icons.first_page, size: 20),
                onPressed: isAtStart ? null : onGoToStart,
                tooltip: 'Go to Start',
                color: Colors.white70,
              ),
              IconButton(
                icon: const Icon(Icons.last_page, size: 20),
                onPressed: isAtEnd ? null : onGoToEnd,
                tooltip: 'Go to End',
                color: Colors.white70,
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Segment'),
                onPressed: canAddSegment ? onAddSegment : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  disabledBackgroundColor: Colors.grey[700],
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.remove, size: 18),
                label: const Text('Delete Last'),
                onPressed: onDeleteLast,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              ),
              const SizedBox(width: 12),
              ElevatedButton(onPressed: onDone, child: const Text('Done')),
            ],
          ),
        ),
      ),
    );
  }
}
