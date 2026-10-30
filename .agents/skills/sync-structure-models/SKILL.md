---
name: sync-structure-models
description: Pulls v9 per-step OBJ model files from the flatmates-structures-debug S3 bucket into assets/models. Each craft has a steps/ directory of assembly-step meshes. Use when the user asks to sync structure models, pull models from S3, update model assets, or import 3D structures.
---

# Sync Structure Models

Downloads per-step OBJ meshes from the `flatmates-structures-debug` S3 bucket into the Flutter app's `assets/models/` folder so the game can compose them at runtime.

Each craft is stored as a directory with a `steps/` subdirectory containing one OBJ per assembly step (`{index}.obj`). Optional `volumes/` meshes are data-only and should not be rendered.

## S3 layout

```
s3://flatmates-structures-debug/v2/crafts/{craft}/steps/{N}.obj
s3://flatmates-structures-debug/v2/crafts/{craft}/volumes/{name}.obj
```

Locally:

```
assets/models/{craft}/steps/{N}.obj
assets/models/{craft}/volumes/{name}.obj
```

## Prerequisites

- AWS CLI installed and authenticated on the local machine.
- The S3 bucket `flatmates-structures-debug` must be accessible with the current AWS credentials.

## When to use

- User asks to sync structure models, pull models from S3, update model assets, or import 3D structures

## Steps

1. **Create destination folder** in the project workspace root:
   ```bash
   mkdir -p assets/models
   ```

2. **Sync OBJ files** from S3 `v2/crafts/`:
   ```bash
   aws s3 sync s3://flatmates-structures-debug/v2/crafts/ assets/models/ --exclude "*" --include "*/steps/*.obj" --include "*/volumes/*.obj" --delete
   ```
   The `--delete` flag removes local files that no longer exist in the bucket.

3. **Update pubspec.yaml** — ensure under `flutter:` the `assets:` section includes an entry for **each steps (and volumes) subdirectory**:
   ```bash
   find assets/models -type d \( -name steps -o -name volumes \)
   ```
   Then ensure `pubspec.yaml` contains:
   ```yaml
   flutter:
     assets:
       - assets/models/house_foo/steps/
       # - assets/models/house_foo/volumes/   # if present
   ```
   Remove any stale entries for crafts that no longer exist.

4. **Refresh Flutter assets**:
   ```bash
   flutter pub get
   ```

## Notes

- Overwrites existing files in `assets/models/` if they exist
- The workspace root is the Flutter project (where `pubspec.yaml` lives)
- OBJ files use Rhino Z-up; the app converts to Y-up on load
- Named object groups `*_parts` and `*_appliques` distinguish structure from overlays
- Only `v2/crafts/*/steps/` and `volumes/` are synced; manifests are handled by the sync-crafting-blueprints skill
- The OBJ schema is documented in FlatmatesRh at `FlatmatesRh/docs/flatpipeline-schema.md`
