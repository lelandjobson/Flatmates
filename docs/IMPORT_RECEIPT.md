# Import Receipt — from `sfapp` (sf_experiments)

**Date:** 2026-07-31  
**Source:** `/Users/ljobson/Desktop/Dev/sfapp`  
**Target:** `/Users/ljobson/Desktop/Dev/Flatmates`

---

## Geometry Library

| Source Path | Destination |
|---|---|
| `lib/geometry/` (entire directory) | `lib/geometry/` |

Contents:
- `geometry.dart` — Core 3D geometry (faces, vertices, Vector3)
- `geometry_2d.dart` — 2D polygon primitives
- `geometry_algorithms.dart` — Intersection, containment, winding
- `geometries.dart` — Multi-geometry container
- `folded_geometry.dart` — Paper-fold transforms
- `polygon_union.dart` — Boolean polygon union
- `tessellation.dart` — Triangulation
- `transformable.dart` — Transform interface
- `curves_2d.dart` — 2D curve math
- `geometry_slicer.dart` — 5×5 grid slicer for OBJ cells
- `obj_parser.dart` — Wavefront OBJ → Geometry
- `svg_path_parser.dart` — SVG path data → geometry
- `prefabs/prefab_factory.dart` — Procedural house, tallHouse, cube, frog, cone, tree
- `prefabs/cable_clamp_loader.dart` — OBJ prefab loader
- `prefabs/Cableclamp.obj` — 3.1 MB mesh asset

---

## ISO 2.5D Rendering Pipeline

| Source Path | Destination |
|---|---|
| `lib/rendering/iso/` (entire directory) | `lib/rendering/iso/` |

Key files:
- `iso_painter.dart` — Main CustomPainter (depth-sorted tile + sprite composite)
- `iso_camera.dart` — Pan/zoom/rotate camera
- `iso_projection.dart` — World↔screen axonometric math
- `iso_vector_generator.dart` — 3D geometry → vector ISO sprites
- `craft_sprite_generator.dart` — Blueprint → folded 3D → ISO sprites
- `iso_asset.dart` / `iso_asset_cache.dart` — Asset loading + caching
- `iso_sprite.dart` / `iso_sprite_grid.dart` — Sprite data structures
- `iso_coordinate.dart` — Isometric coordinate system
- `iso_hit_tester.dart` — Pick/hit testing
- `iso_visibility.dart` — Visibility culling
- `compass_direction.dart` — Cardinal directions
- `facing_sprite_ring.dart` — Multi-angle sprite rings
- `friend_expression.dart` / `expression_painter_2d.dart` — Procedural eyes/mouth
- `fog_animator.dart` — Fog effect
- `perlin_noise.dart` — Noise generation
- `path_geometry.dart` / `path_renderable.dart` / `path_style.dart` — Path rendering
- `scene_raster_cache.dart` — Raster caching
- `selection_edges.dart` — Selection highlight
- `sprite_color_theme.dart` — Sprite theming
- `svg_icon_cache.dart` — SVG icon cache
- `terrain_height_sampler.dart` — Terrain heights
- `tile_occupant_layout.dart` — Tile layout
- `tilt_shift_overlay.dart` — Tilt-shift effect
- `zoom_domain.dart` — Zoom level management
- `magnetic_field_sampler.dart` — Magnetic field sampling
- `map_hologram.dart` — Map hologram effect
- `ingredient_decoration_config.dart` — Ingredient decorations

---

## 3D Scene / Viewer

| Source Path | Destination |
|---|---|
| `lib/rendering/scene/` | `lib/rendering/scene/` |
| `lib/rendering/scene_view.dart` | `lib/rendering/scene_view.dart` |
| `lib/ui/scene_widget.dart` | `lib/ui/scene_widget.dart` |

Contents:
- `scene/scene.dart` — Retained scene graph
- `scene/camera.dart` — Perspective + orthographic camera
- `scene/camera_controller.dart` — OrbitCameraController (gesture-driven)
- `scene/camera_snapshot.dart` — Camera state snapshots
- `scene/scene_hit_tester.dart` — Ray-cast hit testing
- `scene_view.dart` — SceneView + ScenePainter (low-level 3D CustomPainter)
- `scene_widget.dart` — Reusable 3D viewer widget (orbit camera, fold/unfold animation)

---

## Supporting Render Infrastructure

| Source Path | Destination |
|---|---|
| `lib/rendering/mesh.dart` | `lib/rendering/mesh.dart` |
| `lib/rendering/lights.dart` | `lib/rendering/lights.dart` |
| `lib/rendering/render_group.dart` | `lib/rendering/render_group.dart` |
| `lib/rendering/eye_mesh_geometry.dart` | `lib/rendering/eye_mesh_geometry.dart` |
| `lib/rendering/follow_camera_controller.dart` | `lib/rendering/follow_camera_controller.dart` |
| `lib/rendering/minimap_overlay.dart` | `lib/rendering/minimap_overlay.dart` |
| `lib/rendering/hatch/` | `lib/rendering/hatch/` |
| `lib/rendering/painters/` | `lib/rendering/painters/` |

---

## Crafting / Blueprints

| Source Path | Destination |
|---|---|
| `lib/crafting/` | `lib/crafting/` |

Contents:
- `crafting_blueprint.dart` — v7 blueprint schema, folding transforms
- `crafting_material.dart` — Material definitions
- `completed_craft.dart` — Completed craft model
- `crafting_history.dart` — Undo/redo stack
- `friend_orientation.dart` — Friend orientation math
- `paper_splitting.dart` — Paper split geometry
- `placed_paper.dart` — **(new file)** Extracted `PlacedPaper` + `PaperColor` models

---

## Data Layer

| Source Path | Destination |
|---|---|
| `lib/data/crafting_state.dart` | `lib/data/crafting_state.dart` |
| `lib/data/crafts_tech_provider.dart` | `lib/data/crafts_tech_provider.dart` |
| `lib/data/craft_tech_models.dart` | `lib/data/craft_tech_models.dart` |
| `lib/data/craft_tree_index.dart` | `lib/data/craft_tree_index.dart` |
| `lib/data/craft_graph_adapter.dart` | `lib/data/craft_graph_adapter.dart` |
| `lib/data/asset_database.dart` | `lib/data/asset_database.dart` |
| `lib/data/placed_asset_database.dart` | `lib/data/placed_asset_database.dart` |
| `lib/data/path_database.dart` | `lib/data/path_database.dart` |
| `lib/data/game_settings.dart` | `lib/data/game_settings.dart` |

---

## Gameplay

| Source Path | Destination |
|---|---|
| `lib/gameplay/` (entire directory) | `lib/gameplay/` |

Contents:
- `inventory.dart` — Inventory system
- `crafting_database.dart` — Craft DB queries
- `task.dart` — Task model
- `task_controller.dart` — Task execution
- `blueprint_task.dart` — Blueprint task
- `structure_task_manager.dart` — Structure tasks
- `pathfinder.dart` — A* pathfinding
- `dropped_item.dart` — Dropped item model
- `friend_action_sequence.dart` — Friend action sequences
- `tile_action.dart` / `tile_action_resolver.dart` — Tile actions

---

## Animation

| Source Path | Destination |
|---|---|
| `lib/animation/` (entire directory) | `lib/animation/` |

Contents:
- `scene_animatables.dart` — Scene animation targets
- `fold_animator.dart` — Paper fold/unfold animation
- `friend_animation.dart` — Friend expression/movement animation
- `tile_restoration.dart` — Tile restoration animation
- + other animation files

---

## Tiles

| Source Path | Destination |
|---|---|
| `lib/tiles/` (entire directory including `iso/` subdir) | `lib/tiles/` |

Contents:
- `tiles.dart` — Core tile models
- `map_tile_manager.dart` — Tile lifecycle
- `map_selection.dart` — Selection state
- `material_theme.dart` — Tile material themes
- `tile_cooldown.dart` — Cooldown timers
- `tile_link_manager.dart` — Tile links
- `tile_provider.dart` — Tile data provider
- `yield_tile_example.dart` — Example usage
- `iso/iso_tile_provider.dart` — ISO tile data provider
- `iso/iso_tile_manager.dart` — ISO tile manager

---

## User / Friends

| Source Path | Destination |
|---|---|
| `lib/user/` (entire directory) | `lib/user/` |

Contents:
- `friend_provider.dart` — Default friends (Frogman, Cubeboy, Conico)
- `friend_manager.dart` — Friend state management
- `friend_manager_integration_example.dart` — Usage example
- + supporting files

---

## UI Widgets

| Source Path | Destination |
|---|---|
| `lib/ui/scene_widget.dart` | `lib/ui/scene_widget.dart` |
| `lib/ui/rotation_gizmo.dart` | `lib/ui/rotation_gizmo.dart` |
| `lib/ui/map_3d_transition.dart` | `lib/ui/map_3d_transition.dart` |
| `lib/ui/view_mode_filters.dart` | `lib/ui/view_mode_filters.dart` |
| `lib/ui/iso_asset_picker.dart` | `lib/ui/iso_asset_picker.dart` |
| `lib/ui/iso_asset_edit_controls.dart` | `lib/ui/iso_asset_edit_controls.dart` |
| `lib/ui/iso_edit_mode_overlay.dart` | `lib/ui/iso_edit_mode_overlay.dart` |
| `lib/ui/iso_path_edit_controls.dart` | `lib/ui/iso_path_edit_controls.dart` |
| `lib/ui/iso_tile_edit_panel.dart` | `lib/ui/iso_tile_edit_panel.dart` |
| `lib/ui/iso_view_rotation_controls.dart` | `lib/ui/iso_view_rotation_controls.dart` |
| `lib/ui/hud/` | `lib/ui/hud/` |
| `lib/ui/graph/` | `lib/ui/graph/` |

---

## Supporting Utilities

| Source Path | Destination |
|---|---|
| `lib/gestures/` | `lib/gestures/` |
| `lib/utils/` | `lib/utils/` |
| `lib/foliage/` | `lib/foliage/` |
| `lib/painting/` | `lib/painting/` |

---

## Assets

| Source Path | Destination | Description |
|---|---|---|
| `assets/crafts/crafts.json` | `assets/crafts/crafts.json` | 26 KB craft definitions |
| `assets/crafts/techs.json` | `assets/crafts/techs.json` | Tech tree |
| `assets/crafts/img/` | `assets/crafts/img/` | 133 PNG thumbnails (5 tiers each) |
| `assets/crafting_blueprints/` | `assets/crafting_blueprints/` | 11 JSON blueprint files across 8 groups |
| `assets/models/` | `assets/models/` | 155 sliced OBJ files across 8 groups |

---

## Cursor Skills

| Source Path | Destination | Purpose |
|---|---|---|
| `.cursor/skills/sync-structure-models/` | `.cursor/skills/sync-structure-models/` | S3 → `assets/models/` sync |
| `.cursor/skills/sync-crafting-blueprints/` | `.cursor/skills/sync-crafting-blueprints/` | S3 → `assets/crafting_blueprints/` sync |
| `.cursor/skills/sync-graph-manager-crafts/` | `.cursor/skills/sync-graph-manager-crafts/` | Graph manager → `assets/crafts/` sync |

---

## Dependencies Added to `pubspec.yaml`

| Package | Version | Purpose |
|---|---|---|
| `vector_math` | `^2.1.5` | 3D math (Vector3, Matrix4, etc.) |
| `flutter_svg` | `^2.0.15+2` | SVG rendering for icons |

---

## Modifications Made

- **`pubspec.yaml`** — Added `vector_math`, `flutter_svg` dependencies and full asset declarations
- **`lib/crafting/placed_paper.dart`** — New file extracting `PlacedPaper` and `PaperColor` models (originally inline in `views/crafting_test_view.dart`)
- **`lib/data/crafting_state.dart`** — Import path updated to point to extracted model
- **`lib/crafting/crafting_history.dart`** — Import path updated to point to extracted model

---

## What Was NOT Imported

- Views/routes (`lib/views/`) — intentionally excluded per user request
- `geometry/` (top-level) — Boost.Geometry C++ vendored library, not used by Flutter
- `build/`, `.dart_tool/`, platform runners — build artifacts
- `lib/data/` files not referenced by imported code (world state, providers beyond crafting)
