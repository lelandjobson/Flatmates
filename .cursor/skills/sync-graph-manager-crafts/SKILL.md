---
name: sync-graph-manager-crafts
description: Bundles graph-manager crafts/techs from fm-tech-tree and copies them into the sfapp project assets/crafts. Use when the user asks to sync crafts, update crafts from graph-manager, populate assets/crafts, or import graph-manager bundle into the game.
---

# Sync Graph Manager Crafts

Bundles tech trees and crafting graphs from the graph-manager project and copies them into the Flutter game's `assets/crafts/` folder so the game can load crafts.json, techs.json, and thumbnail images at runtime.

## When to use

- User asks to sync crafts, update crafts from graph-manager, populate assets/crafts, or import the graph-manager bundle

## Steps

1. **Run the bundle** in the graph-manager project:
   ```bash
   cd /Users/ljobson/Desktop/Dev/fm-tech-tree/graph-manager && npm run bundle -- flatmates
   ```

2. **Create destination folder** in the sfapp workspace root:
   ```bash
   mkdir -p assets/crafts/img
   ```

3. **Copy JSON files** from `_build/flatmates/` to `assets/crafts/`:
   ```bash
   cp /Users/ljobson/Desktop/Dev/fm-tech-tree/graph-manager/_build/flatmates/crafts.json assets/crafts/
   cp /Users/ljobson/Desktop/Dev/fm-tech-tree/graph-manager/_build/flatmates/techs.json assets/crafts/
   ```

4. **Copy images** from `_build/flatmates/img/` to `assets/crafts/img/`:
   ```bash
   cp -r /Users/ljobson/Desktop/Dev/fm-tech-tree/graph-manager/_build/flatmates/img/* assets/crafts/img/ 2>/dev/null || true
   ```
   (Use `cp` per file if the img folder is empty to avoid errors.)

5. **Update pubspec.yaml** — ensure under `flutter:` the `assets:` section includes:
   ```yaml
   assets:
     - assets/crafts/crafts.json
     - assets/crafts/techs.json
     - assets/crafts/img/
   ```

## Notes

- Overwrites existing files in assets/crafts/ if they exist
- The workspace root is the sfapp project (where pubspec.yaml lives)
- After sync, run `flutter pub get` so Flutter picks up any new asset paths
