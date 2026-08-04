import 'package:flutter/material.dart';
import '../rendering/iso/iso_coordinate.dart';
import '../data/placed_asset_database.dart';
import '../data/path_database.dart';

/// Information about a path segment on a tile
class PathSegmentInfo {
  const PathSegmentInfo({required this.pathId, required this.segmentIndex});

  final PathId pathId;
  final int segmentIndex; // Index of this coordinate in path
}

/// Right-side panel for editing contents of a selected tile
class IsoTileEditPanel extends StatelessWidget {
  const IsoTileEditPanel({
    super.key,
    required this.coordinate,
    required this.assetsOnTile,
    required this.pathsOnTile,
    required this.onEditAsset,
    required this.onDeleteAsset,
    required this.onAddAsset,
    required this.onEditPath,
    required this.onDeletePath,
    required this.onClose,
  });

  final IsoCoordinate coordinate;
  final List<PlacedAssetEntry> assetsOnTile;
  final List<PathSegmentInfo> pathsOnTile;
  final Function(PlacedAssetId) onEditAsset;
  final Function(PlacedAssetId) onDeleteAsset;
  final VoidCallback onAddAsset;
  final Function(PathId) onEditPath;
  final Function(PathId, IsoCoordinate) onDeletePath;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      margin: const EdgeInsets.only(right: 16, top: 80, bottom: 80),
      decoration: BoxDecoration(
        color: Colors.grey[900]!.withOpacity(0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: ListView(
              children: [_buildAssetsSection(), _buildPathsSection()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white12)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Tile (${coordinate.x}, ${coordinate.y})',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: onClose,
            iconSize: 20,
          ),
        ],
      ),
    );
  }

  Widget _buildAssetsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            'Assets',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
        ),
        // List existing assets
        ...assetsOnTile.map((asset) => _buildAssetRow(asset)),
        // Add asset button (only if no assets)
        if (assetsOnTile.isEmpty) _buildAddButton('Add Asset', onAddAsset),
      ],
    );
  }

  Widget _buildAssetRow(PlacedAssetEntry asset) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.house, size: 20, color: Colors.orangeAccent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              asset.typeId.substring(0, asset.typeId.length.clamp(0, 20)),
              style: const TextStyle(fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit, size: 18),
            onPressed: () => onEditAsset(asset.id),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.delete, size: 18, color: Colors.red),
            onPressed: () => onDeleteAsset(asset.id),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildPathsSection() {
    if (pathsOnTile.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            'Paths',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
        ),
        ...pathsOnTile.map((pathInfo) => _buildPathRow(pathInfo)),
      ],
    );
  }

  Widget _buildPathRow(PathSegmentInfo pathInfo) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.route, size: 20, color: Colors.yellow),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Path ${pathInfo.pathId}',
              style: const TextStyle(fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit, size: 18),
            onPressed: () => onEditPath(pathInfo.pathId),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.delete, size: 18, color: Colors.red),
            onPressed: () => onDeletePath(pathInfo.pathId, coordinate),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildAddButton(String label, VoidCallback onPressed) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.add, size: 18),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green.withOpacity(0.8),
          minimumSize: const Size(double.infinity, 40),
        ),
      ),
    );
  }
}
