---
name: sync-crafting-blueprints
description: Pulls crafting blueprint JSON files from the flatmates-structures-debug S3 bucket into the sfapp project assets/crafting_blueprints. Each craft gets a subdirectory containing its island JSONs. Use when the user asks to sync crafting blueprints, pull blueprints from S3, update blueprint assets, or refresh structure geometry.
---

# Sync Crafting Blueprints

Downloads crafting blueprint JSON files from the `flatmates-structures-debug` S3 bucket and copies them into the Flutter app's `assets/crafting_blueprints/` folder so the game can load them at runtime.

## S3 layout

```
s3://flatmates-structures-debug/v2/crafts/{craft}/blueprint/{island}.json
                                          ^^^^^^             ^^^^^^
                                          craft name         island index (0, 1, ...)
```

Each craft may have multiple islands (separate connected regions). Locally the structure mirrors S3:

```
assets/crafting_blueprints/{craft}/blueprint/{island}.json
```

## Prerequisites

- AWS CLI installed and authenticated on the local machine.
- The S3 bucket `flatmates-structures-debug` must be accessible with the current AWS credentials.

## When to use

- User asks to sync crafting blueprints, pull blueprints from S3, update blueprint assets, or refresh structure geometry

## Steps

1. **Create destination folder** in the sfapp workspace root:
   ```bash
   mkdir -p assets/crafting_blueprints
   ```

2. **Sync JSON files** from S3 `v2/crafts/` path, filtering to blueprint subdirectories:
   ```bash
   aws s3 sync s3://flatmates-structures-debug/v2/crafts/ assets/crafting_blueprints/ --exclude "*" --include "*/blueprint/*.json" --delete
   ```
   The `--delete` flag removes local files that no longer exist in the bucket.

3. **Update pubspec.yaml** — ensure under `flutter:` the `assets:` section includes an entry for **each craft's blueprint subdirectory**. Scan the synced directories and add one entry per craft:
   ```bash
   ls -d assets/crafting_blueprints/*/blueprint/
   ```
   Then ensure `pubspec.yaml` contains:
   ```yaml
   flutter:
     assets:
       - assets/crafting_blueprints/Group03/blueprint/
       - assets/crafting_blueprints/Group04/blueprint/
       # ... one entry per craft blueprint directory
   ```

4. **Refresh Flutter assets**:
   ```bash
   flutter pub get
   ```

## Notes

- Overwrites existing files in `assets/crafting_blueprints/` if they exist
- The workspace root is the sfapp project (where `pubspec.yaml` lives)
- Blueprint JSON files follow the v7 schema documented in the FlatmatesRh repo (`FlatmatesRh/docs/blueprint-schema.md`)
- Only the `v2/crafts/*/blueprint/` prefix in the bucket is synced; model files are handled by the sync-structure-models skill
