---
name: sync-crafting-blueprints
description: Pulls v9 craft.json manifests from the flatmates-structures-debug S3 bucket into assets/crafting_blueprints. Each craft is a subdirectory containing craft.json. Use when the user asks to sync crafting blueprints, pull blueprints from S3, update blueprint assets, or refresh structure geometry.
---

# Sync Crafting Blueprints

Downloads v9 craft manifests from the `flatmates-structures-debug` S3 bucket into the Flutter app's `assets/crafting_blueprints/` folder so the game can load them at runtime.

## S3 layout

```
s3://flatmates-structures-debug/v2/crafts/{craft}/craft.json
```

Locally:

```
assets/crafting_blueprints/{craft}/craft.json
```

## Prerequisites

- AWS CLI installed and authenticated on the local machine.
- The S3 bucket `flatmates-structures-debug` must be accessible with the current AWS credentials.

## When to use

- User asks to sync crafting blueprints, pull blueprints from S3, update blueprint assets, or refresh structure geometry

## Steps

1. **Create destination folder** in the project workspace root:
   ```bash
   mkdir -p assets/crafting_blueprints
   ```

2. **Sync craft.json files** from S3 `v2/crafts/`:
   ```bash
   aws s3 sync s3://flatmates-structures-debug/v2/crafts/ assets/crafting_blueprints/ --exclude "*" --include "*/craft.json" --delete
   ```
   The `--delete` flag removes local files that no longer exist in the bucket.

3. **Update pubspec.yaml** — ensure under `flutter:` the `assets:` section includes an entry for **each craft subdirectory**. Scan the synced directories:
   ```bash
   ls -d assets/crafting_blueprints/*/
   ```
   Then ensure `pubspec.yaml` contains:
   ```yaml
   flutter:
     assets:
       - assets/crafting_blueprints/house_foo/
       # ... one entry per craft directory
   ```

4. **Refresh Flutter assets**:
   ```bash
   flutter pub get
   ```

## Notes

- Overwrites existing files in `assets/crafting_blueprints/` if they exist
- The workspace root is the Flutter project (where `pubspec.yaml` lives)
- Manifests follow the v9 flatpipeline schema documented in FlatmatesRh (`FlatmatesRh/docs/flatpipeline-schema.md`)
- Only `v2/crafts/*/craft.json` is synced; step OBJ files are handled by the sync-structure-models skill
