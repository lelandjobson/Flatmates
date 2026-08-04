---
name: sync-structure-models
description: Pulls sliced OBJ 3D model files from the flatmates-structures-debug S3 bucket into the sfapp project assets/models. Each craft has per-layer directories of 5x5 grid-sliced OBJ cells. Use when the user asks to sync structure models, pull models from S3, update model assets, or import 3D structures.
---

# Sync Structure Models

Downloads pre-sliced OBJ 3D model files from the `flatmates-structures-debug` S3 bucket and copies them into the Flutter app's `assets/models/` folder so the game can load them as isometric structure assets at runtime.

Each craft is stored as a directory with a `model/` subdirectory containing one folder per material layer. Each layer contains up to 25 OBJ files (5x5 grid cells), named `{x}_{y}.obj` where x and y range from 0 to 4. Empty cells (no geometry) are omitted. All cells in a craft share the same tile-local coordinate origin so they reassemble seamlessly.

## S3 layout

```
s3://flatmates-structures-debug/v2/crafts/{craft}/model/{layer}/{x}_{y}.obj
                                          ^^^^^^        ^^^^^^^ ^^^ ^^^
                                          craft name    material col row (both 0..4)
```

## Prerequisites

- AWS CLI installed and authenticated on the local machine.
- The S3 bucket `flatmates-structures-debug` must be accessible with the current AWS credentials.

## When to use

- User asks to sync structure models, pull models from S3, update model assets, or import 3D structures

## Steps

1. **Create destination folder** in the sfapp workspace root:
   ```bash
   mkdir -p assets/models
   ```

2. **Sync OBJ files** from S3 `v2/crafts/` path, filtering to model subdirectories:
   ```bash
   aws s3 sync s3://flatmates-structures-debug/v2/crafts/ assets/models/ --exclude "*" --include "*/model/*/*.obj" --delete
   ```
   The `--delete` flag removes local files that no longer exist in the bucket. This preserves the directory structure: each craft becomes a subdirectory (e.g. `assets/models/Group03/model/WoodPanel/0_0.obj`).

3. **Update pubspec.yaml** — ensure under `flutter:` the `assets:` section includes an entry for **each layer subdirectory** within each craft. Scan the synced directories and add entries:
   ```bash
   find assets/models -type d -name "model" -exec find {} -type d \;
   ```
   Then ensure `pubspec.yaml` contains:
   ```yaml
   flutter:
     assets:
       - assets/models/Group03/model/WoodPanel/
       - assets/models/Group03/model/IronPlate/
       # ... one entry per craft/layer directory
   ```
   Remove any stale entries for crafts or layers that no longer exist.

4. **Refresh Flutter assets**:
   ```bash
   flutter pub get
   ```

## Notes

- Overwrites existing files in `assets/models/` if they exist
- The workspace root is the sfapp project (where `pubspec.yaml` lives)
- OBJ files follow the 10:1 scale convention: 10 model units = 1 tile width
- Only the `v2/crafts/*/model/` prefix in the bucket is synced; blueprint files are handled by the sync-crafting-blueprints skill
- Not all 25 cells may be present for a layer — empty cells have no geometry and are not uploaded
- The OBJ schema is documented in the FlatmatesRh repo at `FlatmatesRh/docs/craft-obj-schema.md`
