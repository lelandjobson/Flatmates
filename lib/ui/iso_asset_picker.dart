import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import '../data/asset_database.dart';
import '../data/placed_asset_database.dart';
import '../rendering/iso/iso_asset.dart';
import '../rendering/iso/iso_asset_cache.dart';
import '../rendering/iso/iso_camera.dart';
import '../rendering/iso/iso_sprite.dart';

/// Asset picker widget with emoji-picker-like grid interface
class IsoAssetPicker extends StatefulWidget {
  const IsoAssetPicker({
    super.key,
    required this.assetDatabase,
    required this.assetCache,
    required this.camera,
    required this.onAssetSelected,
    required this.onCancel,
  });

  final AssetDatabase assetDatabase;
  final IsoAssetCache assetCache;
  final IsoCamera camera;
  final Function(AssetTypeId) onAssetSelected;
  final VoidCallback onCancel;

  @override
  State<IsoAssetPicker> createState() => _IsoAssetPickerState();
}

class _IsoAssetPickerState extends State<IsoAssetPicker> {
  String _searchQuery = '';
  List<AssetDefinition> _filteredAssets = [];
  List<AssetDefinition> _allAssets = [];

  @override
  void initState() {
    super.initState();
    _loadAssets();
  }

  Future<void> _loadAssets() async {
    final allAssets = await widget.assetDatabase.getAllDefinitions();
    setState(() {
      _allAssets = allAssets;
      _filteredAssets = allAssets;
    });
  }

  void _filterAssets(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredAssets = _allAssets;
      } else {
        final lowerQuery = query.toLowerCase();
        _filteredAssets = _allAssets.where((asset) {
          return asset.name.toLowerCase().contains(lowerQuery) ||
              asset.category.toString().toLowerCase().contains(lowerQuery);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      height: 400,
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        children: [
          _buildHeader(),
          _buildSearchBar(),
          Expanded(child: _buildAssetGrid()),
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
          const Expanded(
            child: Text(
              'Select Asset',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: widget.onCancel,
            iconSize: 20,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: TextField(
        onChanged: _filterAssets,
        decoration: InputDecoration(
          hintText: 'Search assets...',
          prefixIcon: const Icon(Icons.search, size: 20),
          filled: true,
          fillColor: Colors.black26,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
        ),
        style: const TextStyle(fontSize: 14),
      ),
    );
  }

  Widget _buildAssetGrid() {
    if (_filteredAssets.isEmpty) {
      return const Center(
        child: Text('No assets found', style: TextStyle(color: Colors.white54)),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.0,
      ),
      itemCount: _filteredAssets.length,
      itemBuilder: (context, index) {
        final assetDef = _filteredAssets[index];
        return _buildAssetTile(assetDef);
      },
    );
  }

  Widget _buildAssetTile(AssetDefinition assetDef) {
    return GestureDetector(
      onTap: () => widget.onAssetSelected(assetDef.typeId),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black26,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Render asset thumbnail
            FutureBuilder<IsoAsset?>(
              future: widget.assetCache.getOrCreateAsset(assetDef.typeId),
              builder: (context, snapshot) {
                if (snapshot.hasData && snapshot.data != null) {
                  return _renderAssetThumbnail(snapshot.data!);
                }
                return const Icon(Icons.image, size: 40);
              },
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                assetDef.name,
                style: const TextStyle(fontSize: 11),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _renderAssetThumbnail(IsoAsset asset) {
    final sprite = asset.getSpriteForView(widget.camera.view);
    return SizedBox(
      width: 60,
      height: 60,
      child: CustomPaint(painter: _AssetThumbnailPainter(sprite)),
    );
  }
}

/// Custom painter for rendering asset thumbnail
class _AssetThumbnailPainter extends CustomPainter {
  _AssetThumbnailPainter(this.sprite);

  final IsoSprite sprite;

  @override
  void paint(Canvas canvas, Size size) {
    final spriteSize = sprite.size;

    // Calculate scale to fit in thumbnail
    final scaleX = size.width / spriteSize.width;
    final scaleY = size.height / spriteSize.height;
    final scale = scaleX < scaleY ? scaleX : scaleY;

    // Center the sprite
    final scaledWidth = spriteSize.width * scale;
    final scaledHeight = spriteSize.height * scale;
    final offsetX = (size.width - scaledWidth) / 2;
    final offsetY = (size.height - scaledHeight) / 2;

    canvas.save();
    canvas.translate(offsetX, offsetY);
    canvas.scale(scale);

    // Draw sprite based on type
    if (sprite is RasterIsoSprite) {
      final raster = sprite as RasterIsoSprite;
      canvas.drawImageRect(
        raster.image,
        Rect.fromLTWH(
          0,
          0,
          raster.image.width.toDouble(),
          raster.image.height.toDouble(),
        ),
        Rect.fromLTWH(
          0,
          0,
          spriteSize.width.toDouble(),
          spriteSize.height.toDouble(),
        ),
        Paint(),
      );
    } else if (sprite is VectorIsoSprite) {
      final vector = sprite as VectorIsoSprite;
      canvas.drawPicture(vector.picture);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _AssetThumbnailPainter oldDelegate) {
    return oldDelegate.sprite != sprite;
  }
}
