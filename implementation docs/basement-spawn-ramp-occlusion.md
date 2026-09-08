# Basement spawn ramp and ground occlusion

Date: 2026-09-08
Chat: [Basement spawn concept](e0120615-dda6-41d6-a309-b9d1f1c419b1)

This note covers the basement spawn ramp and the work of drawing or hiding
geometry behind the map and the door. It does not cover later paper-fly UI
work in the same chat.

## What was requested

Original ask (2026-09-07): introduce a **basement spawn** at datum 0. Punch
two normal tiles at `(0,0)` and `(0,1)` and insert a special-case ramp (keep
the world flat; do not add a general height-field). Place a locked path at
`(0,2)`. Extend the ramp at least one tile past the visible hole so
characters do not pop into view. Add a dark door surface so the camera
cannot see forever down the tunnel. Block walking on the hole tiles; `(0,2)`
is a normal path but not removable.

Course corrections that stuck:

- Show `(0,-1)` and `(0,-2)` as ordinary landscape **bridging** over the
  underground slope. Do not punch them. Do not leave the underside visible.
- Ramp should look like sloped map tiles with a regular ~4-subtile path, not
  a tile-filling slab. Path must join `(0,2)`.
- Door moved around (third tile, then dropped, then a blur veil experiment,
  then door back at the `(0,0)` / `(0,-1)` seam). Veil code stayed; it is
  **disabled**.
- Underground meshes need real occlusion: mark objects that must be clipped;
  leave at-grade objects on the simple painter. Outlines must use the same
  clip as faces.
- Create tools: unbuildable tiles always show the X crosshair and never a
  hologram. `(0,2)` is locked for select/delete/build; walking on it is
  allowed.
- Door wall should look like a **volume wall** with a 2×4 opening, not a
  see-through atlas panel and not path-colored fill.

Prompt that defined the renderer problem (paraphrased): research how this
Flutter / software 3D view can hide parts of an object occluded by the
ground; keep the simple pipeline for at-grade work; opt in per object.

Later occlusion prompts: the wall must actually block what is behind it;
only the door notch should be a hole; all-or-nothing probes made the wall
vanish at acute angles; the wall showed through grass from corners; applying
the same clip to all path outlines deleted at-grade path strokes.

## What we built

The map stays a flat Y=0 plane. `(0,1)` and `(0,0)` are cut out of the
landscape. A sloped deck + path continue under bridged tiles `(0,-1)` and
`(0,-2)`. A volume-colored door wall sits on the south seam of the hole
(shared edge of `(0,0)` and `(0,-1)`), opening only a 2×4 door. Underground
meshes opt into `Mesh.groundOcclusion`. The software scene painter clips
those faces (and matching outlines) to the camera frustum through the hole
and, behind the facade, through the door opening. At-grade path outlines
skip that clip so they keep drawing.

Default `VolumeGrid` is 16-wide; spawn tests use `tilesSide: 48` so the
origin sits in the map after the recenter (−24..23).

## Key engineering problems

### 1. Flat world, local hole (no height-field)

- **Symptom:** A descending path that still lives in a flat-tile game.
- **Cause:** Landscape and tools assume Y=0 tiles. A general corner-height
  system would touch every painter and picker.
- **Solution:** Special-case spawn. Punch only `cutTiles` `(0,1)` / `(0,0)`.
  Build sloped geometry as its own meshes. Bridged tiles stay normal
  landscape. `basementRampHeight` is a linear slope: half a world unit of Y
  per unit of Z, starting at Y=0 on the south edge of `(0,1)`.

### 2. No GPU depth; painters composite in order

- **Symptom:** “I can see the back of a wall / the whole ramp under the
  grass / through the door wall.”
- **Cause:** GameView is stacked 2D `CustomPaint`. There is no depth buffer.
  Later draws win. Atlas-textured or ground-clipped walls became holes.
  Ramp fill painted after the facade, so the path showed through solid
  jambs.
- **Failed approaches:** Treating the door as ground-atlas (it disappeared).
  Path-colored fill with no occluder (ramp still painted through). A single
  visibility probe for the whole facade (`clipPartial: false`) — at acute
  angles the probe missed the hole and the **entire wall vanished**.
- **Solution:** Opt-in `GroundOcclusion` on underground meshes only. Clip
  faces to the hole frustum. Treat the door as a `WallHoleOccluder`: camera
  rays that hit the facade (not the opening) hide ramp fill and outlines
  behind it. Door mesh is volume-colored quads (jambs + lintel), not atlas.

### 3. What “visible through the ground” means

- **Symptom:** Underground geo drawn in full, or hole tiles missing again.
- **Cause:** A vertex below Y=0 is visible only if the camera ray hits the
  plane **inside the cut tiles** before the point. Bridged tiles are solid
  ground; punching them again was a regression.
- **Solution:** `visibleThroughGround` + `GroundHoleRect` from
  `BasementSpawn.cutTileSet` only. `clipPolygonToGroundHoleFrustum` /
  `clipSegmentToGroundHoleFrustum` (Sutherland–Hodgman against the four
  camera–hole-edge planes). Do **not** pad the north (min-Z) hole seam —
  that is the door; padding into the bridge lets the wall show through
  grass. After frustum clip, drop the at-grade lip (`y <= planeY - 0.03`)
  so the door rim does not composite over the lawn.

### 4. Seeing past the door, but only through the notch

- **Symptom:** Whole wall see-through, or ramp outlines continuing through
  the facade; triangular flicker when looking through the door.
- **Cause:** Opening and wall shared one clip. Edge clips without a door
  frustum left strokes on the far side. Tight hole padding flickered.
- **Solution:** Split faces/segments at the wall Z. Front of wall: hole
  frustum only. Back of wall: also `clipPolygonToDoorFrustum` /
  `clipSegmentToDoorFrustum`. `kWallHoleClipPad` (0.06) on the **door**
  hole only, so the opening stays stable. Ramp meshes get
  `wallHole` from `basementGroundOcclusion`. The door mesh itself uses
  hole-frustum occlusion **without** an all-or-nothing probe.

### 5. Shared outline occlusion deleted every path stroke

- **Symptom:** Locked path at `(0,2)` and all newly painted paths lost
  their outlines.
- **Cause:** `ScenePainter._groundOutlineOcclusion` takes the **first**
  mesh with `groundOcclusion` (the basement path) and applies it to
  **all** ground outlines. At-grade path edges then went through the
  underground clip and were dropped or stripped.
- **Solution:** `_atGrade` short-circuit in `clipFaceToVisibleParts` and
  `clipSegmentToVisibleParts`: if every vertex is at `planeY`, return the
  geometry unclipped. Underground sloped edges still clip.

### 6. Tools / pick vs. “random tile selected on the ramp”

- **Symptom:** Hovering the hole selected the last real tile (e.g. `(1,3)`);
  holograms still appeared on locked tiles.
- **Cause:** Cut tiles are not pickable, but aim fell through to stale
  selection. Build checks were incomplete.
- **Solution:** `blocksWalk` = cut only. `blocksSelect` / `blocksBuild` =
  cut **or** locked `(0,2)`. `_canEditTile` uses `blocksBuild`. Ghosts hide
  via `_tileUnbuildable` / `blocksSelect`. `canPaintPathAt` uses
  `blocksBuild`. Crosshair morphs to X when the tile is unbuildable.

### 7. Blur veil (experiment, kept off)

- **Request:** A frosted plane so the tunnel does not read as infinite.
- **What landed:** Self-contained `basement_blur_veil.dart`. Location moved
  to the `(0,-1)` / `(0,-2)` border, then the door came back.
- **Invariant:** `kBasementBlurVeilEnabled = false`. Do not delete the
  module; do not turn it on without revisiting door occlusion.

## Key implementations

**Spawn rules** (`BasementSpawn`):

| Tile | Role |
|------|------|
| `(0, 2)` | Locked path: walkable, not selectable/buildable |
| `(0, 1)`, `(0, 0)` | Punched hole + visible sloped ramp |
| `(0, -1)`, `(0, -2)` | Normal landscape bridging the underground ramp |

Column X=0, −Z is north. Door Z is the shared edge of `(0,0)` and `(0,-1)`.

**Meshes** (`syncBasementSpawnMeshes`): sloped path
(`kBasementSpawnPathId`) with `groundOcclusion` from
`basementGroundOcclusion` (hole + door wall hole). Door
(`kBasementSpawnDoorId`) is fill quads, volume theme color, hole-frustum
occlusion only. Sloped ground is landscape-atlas in the plane painter, not
a leftover solid deck. Path outlines join `(0,2)` via
`basementRampPathOutlineQuads` when that path exists.

**Occlusion types** (`ground_occlusion.dart`):

- `GroundHoleRect` — axis-aligned hole in Y=0
- `WallHoleOccluder` — Z-plane facade with a rectangular opening
- `GroundOcclusion` — opt-in on `Mesh`; `clipPartial` / `visibilityProbe`
  remain but must not be used as the door’s only visibility test
- `visibleThroughGround` / `visiblePastWallHole` — ray tests
- `clipFaceToVisibleParts` / `clipSegmentToVisibleParts` — painter entry

**Call sites:** `ScenePainter._collectFaces` clips marked meshes.
`paintOutlineEdges` uses the same helpers. Landscape plane painter clips
sloped atlas faces. Door overlay (`basement_door_overlay.dart`) can take
the same occlusion.

**Lighting:** sloped atlas and cut walls use `PlaneShadeModel` (same sun
as the paper map). Ramp ground is a bit darker than grade, not as dark as
the first shaded pass.

## Files

- `lib/gameplay/spawns/basement_spawn.dart` — tile sets and block flags
- `lib/gameplay/spawns/basement_spawn_mesh.dart` — ramp/path/door geo + occlusion setup
- `lib/gameplay/spawns/basement_blur_veil.dart` — disabled veil
- `lib/rendering/ground_occlusion.dart` — hole/door clip math
- `lib/rendering/mesh.dart` — `groundOcclusion` flag
- `lib/rendering/scene_view.dart` — face collect + shared outline occlusion
- `lib/landscape/landscape_plane_painter.dart` — sloped atlas clip
- `lib/gameplay/outlines/outline_paint.dart` — outline clip
- `lib/ui/game/basement_door_overlay.dart` — door overlay
- `lib/screens/game_view.dart` — pick, tools, overlay wiring
- `test/basement_spawn_test.dart` — spawn locks and mesh
- `test/ground_occlusion_test.dart` — visibility and clip remnants

## Tests

`ground_occlusion_test` locks ray-vs-plane visibility and clip remnants
(hole vs grass, door opening vs jamb). `basement_spawn_test` locks cut vs
bridge tiles, walk/build/select, and door fill. They do not replace a
visual pass from acute corners or through the 2×4 opening.

## Open / leftover

- Do **not** punch `(0,-1)` / `(0,-2)` again.
- Do **not** re-enable all-or-nothing door probes as the only visibility
  test; that is what vanished the wall at acute angles.
- Do **not** remove the at-grade outline skip; first-mesh outline occlusion
  will strip every path stroke again.
- Blur veil remains in tree, off.
- `_groundOutlineOcclusion` still shares one occlusion object across all
  ground outlines; the at-grade skip is the safety valve, not a per-edge
  mesh lookup.
