# Protoplane concept

Open `protoplane_concept` in the developer menu (`/protoplane-concept`). This
prototype has its own world, paper inventory, history, and local save. It does
not change GameView or the grid-puzzle rules.

## Interaction

- In the world, drag to pan. Touch taps select at the center reticle; mouse
  clicks select at the cursor. Two-finger horizontal swipes or secondary mouse
  dragging rotate; pinching or the mouse wheel zooms.
- Select a protoplane to draw on its dots. Continue a path across separate
  drags. Only the displayed connections can be used. Ground connections may
  be diagonal, but pass through intervening dots. Lines cannot self-intersect.
- A valid drawing sustains a glow in the selected line color. Choose a matching object, inspect its preview
  and material quote, and press Create. Swiping the bottom carousel changes
  acetate grids without losing their drafts. The right carousel chooses paper.
- Select a crafted object to craft on its surface. Edit changes that object
  using its original source grid. A closed scissors path removes its region;
  a boundary-to-boundary path splits paper and retains both pieces. On a Screen,
  cuts trim or split its original open path into retained panel runs.
- Volume taps give a region thickness. Toggle 3D (or double-tap background)
  and drag the cap along its normal to adjust depth. Apply confirms an edit.
- Pinch inward past the exit threshold, scroll outward, or use Back to return
  to the cached world perspective. Undo/redo cover strokes and committed edits.

## Construction and recipes

Each ground tile has a 5×5 dot grid. Any simple closed outline can become a
floor. Sibling pieces may share boundaries but not material area. Floor
surfaces receive three deterministic generated grids; generated node/edge
definitions are saved, so they never reroll on reopen. Templates guarantee
drawable Rug, Tabletop, Bench, Planter, and Screen examples across the grids.
Curved connections are quadratic paths flattened to a fixed local tolerance.

Recognition combines geometry (oriented aspect ratio, area, curves), topology
(open path/closed region), and support context. Rotation, reflection, winding,
and start-point order do not determine identity. Ambiguous matches are offered
as choices. Identity survives later cuts and depth edits.

Floors generate wall candidates on their outer straight edges. Any wall
unlocks one upper-floor candidate over its supporting floor at one tile-width
story height. Walls support interior windows and bottom-touching doors;
openings remove actual wall material. Window and planter cavities are stored
in their geometry, including their inner sidewall material costs. Upper floors
repeat the construction loop. No structural simulation is performed.

Support ownership and wall support lists are explicit. Edits that could strand
existing attachments or occupied derived planes are conservatively rejected.
Unused derived planes are rebuilt after edits. Screen occupancy follows all
its panel segments; volumetric collision uses convex triangular prisms and
separating axes, including differently oriented planes.

## Material and history

A tile is one square world unit and 128 material units. Each of the five pastel colors
starts with 256 units. Closed crafts cost
`ceil(128 × (net planar area + perimeter including holes × depth))`.
Screen sheets cost `ceil(128 × path length × height)`. Bench geometry is a
stylized seat and supports; its material quote uses its drawn extrusion
envelope. This is a prototype accounting convention, not a paper unfolding.

Depth increases charge only added side area. Cuts, splits, and reductions
do not refund material. Undo restores the exact previous balance. A completed
drag is one history action, independent of pointer-event frequency. Camera
animation never enters history. Histories and per-grid drafts are session-only.

## Implementation and persistence

`lib/protoplane/` separates geometry, models/grid generation, recognition,
collision, controller/history, meshing, and storage. The screen adapts these
to the existing SceneView, WorldPlane, MapLookCameraController, reticle,
undo/redo controls, and axis-drag projection.

Geometry uses Boost.Geometry's Cartesian segment-intersection approach and
the repository's planar splitting primitives. Vertical decomposition handles
concavity and holes; seam cancellation preserves disconnected cut results.
No Boost runtime dependency is introduced.

Native saves live in the application-support directory under
`protoplane_concept/world.json`, through `path_provider`. Version 2 stores
planes and their grid definitions, objects and dependencies, stable IDs,
paper balances, and the seeded landscape with depletion and fractional yields.
Version 1 saves migrate automatically, retaining existing balances and objects. Writes are serialized and atomically renamed, with a
previous valid backup. A damaged primary is retained separately when recovery
uses the backup. If neither save validates, writes remain blocked and Retry
reloads; an empty world never silently overwrites the damaged data.

## Validation

Run `flutter test test/protoplane`. The suite covers geometry and holes,
template solvability, invariant recognition, all starter craft families,
paper transactions, support protection, collisions, construction through a
second story, save/recovery, and mouse/touch interaction. UI checks exercise
portrait, landscape, and desktop layouts without golden-image dependencies.

The existing GameViewer, WorldPlane, craft-palette, and debug-layout tests are
useful regression checks. Native desktop builds verify the storage plugin;
physical-device touch tuning remains a separate playtest.

## Bedrooms and flatmates

Every floor surface now has a fourth **Bedroom** acetate with Bed frame,
Lamp, Storage, and Rug recipes. A bed frame's surface offers Mattress;
a mattress offers Pillow and Blanket. Lamps can also be crafted on tabletops
and storage. Existing saves gain the added recipes without rerolling their
original grids or resetting paper balances.

For this stage, a bedroom is one authored floor footprint, with no ceiling
requirement. Every boundary must have actual wall coverage through 0.65 units
of height; real window and door openings count as part of the enclosure.
A door must reach the floor and be at least 0.12 wide and 0.35 high. A bed frame
must support a mattress covering at least 65% of its area. Clearance sampling
checks a route from inside a door to the bedside, accounting for furniture,
screens, and floor holes. This is room-local access: connecting rooms across
floors and stairs is future work.

A usable room automatically gains Frogman or Cube Boy, using the existing
GameView character meshes and face overlays. Stable floor-derived resident
IDs preserve the character through load and undo/redo. Residency and comfort
are recomputed from committed geometry, so invalidating the bedroom removes
its occupant and restoring the bedroom restores the same character. There is
one occupant per usable floor footprint. Occupied rooms fade their front walls
in the world camera; clicking a resident's status chip opens the room.

Comfort starts at 40/100. A pillow adds 12, a blanket 16, lighting up to 12,
storage 12, and a rug 8. A window supplies 6 lighting points; a lamp supplies
12. Bedding must belong to the usable bed's mattress. Categories are capped,
so additional copies never stack comfort. The score and Settled/Comfortable/
Delighted status update on commits and undo/redo. Paper color has no effect.
Room status shows missing requirements when the bedroom is not usable.

This stage does not add credits, material varieties, daily routines, or a
store. The item definitions keep support/coverage requirements separate so
material requirements can be introduced without rewriting room recognition.

## Focus and input feedback

`GameControls` loads desktop or mobile defaults and follows the active pointer
kind on hybrid devices. Desktop uses a cursor-following reticle; touch keeps
it centered. Both use the same world aim for highlighting and selection,
primary dragging to pan, and secondary/two-finger dragging to rotate. Crafting
always follows the actual pointer. Native trackpad pan/zoom is supported.

Plane focus preserves the incoming azimuth and perspective lens, tips only
enough to read the grid, and eases over 650 ms. Same-level neighboring tiles
(including diagonal neighbors) remain at 18% of their normal opacity; more
distant context fades out. Context is not selectable while crafting. Back or
pinching out restores the cached world pose and fades the surroundings back in.

Live strokes follow the permitted straight or curved edge toward the pointer
before the next node is reached. Reaching a node pulses the completed segment in the line color; a recognized craft brightens the entire trace. These transient effects
do not add history entries or alter the committed geometry.

Crafting supports two local backtracking gestures with Scissors active. Hold
within 24 screen pixels of the preceding node for 500 ms to remove the newest
node and return the trace to that preceding node. Desktop hover works without
a button; touch uses a held drag. Leaving the target cancels the hold. Scrubbing
near the newest node also removes it: two reversals of at least 10 pixels,
within a 28-pixel radius and 700 ms, distinguish deliberate erasing from jitter.
The erased node cannot immediately be re-added until the pointer leaves it.
While a closed loop is held it stays ready until release or cancellation. Dots
no longer flash: idle dots are half their previous size, and selected dots grow
and fill with the line color over 140 ms. Removing a selection shrinks it back.
Glow remains on selected dots and the trace.
Backtracking during a drag shares that drag's undo transaction; hover edits
have independent undo entries. Neither gesture spends or refunds paper.

The past-point hold also rewinds to any earlier non-start node, keeping that
node and removing its entire suffix as one undoable edit. Merely passing over
an earlier node does not rewind: the pointer must stay near it for 500 ms.
The nearest dot determines the target so neighboring dots cannot steal a hold
intended for the start, current endpoint, or a new point. The start remains
reserved for loop closure; scrubbing the current endpoint can reopen a loop.

Floor acetates repeat their stored motif across the floor without resizing
recipes. Copies share coincident nodes, retain curved controls, and omit edges
whose flattened geometry crosses a boundary or hole. Original node indices
and example paths remain stable. A persisted tiled marker makes expansion
idempotent when loading existing saves. Bedroom grids use the same expansion.
World hover previews the first acetate as softly glowing dots on the object's
surface. Hover changes crossfade over 220 ms; focus uses those same world-space
dots and fades in available paths during the camera transition.

## Daylight and wall reveal

The scene shares `DayNightLighting.day()` with GameView: 0.7 ambient GI,
0.25 white sun key, and 0.3 opposing fill. Lighting remains world-oriented
as the camera rotates. This uses the existing renderer's ambient model.

`WallRevealSettings` centralizes the cutaway tuning in tile units. At a
camera-to-target distance of 4 or less, front-facing walls near the look-at
point fade to 8%; they return smoothly by distance 8. Reveal is strongest
within one tile of the room center and ends at 2.5 tiles, so panning away
restores the enclosure. The facing blend spans dot products 0 to 0.25,
following GameView's wall cutaway. Other stories are excluded by a vertical
look-at band. Doors and windows follow their room's walls. Below 35% opacity,
wall objects do not intercept world selection. Crafting the wall itself keeps
it visible. These are camera effects and never change geometry or saved state.

## Developer settings

The `devtools` control opens Crafting, Lighting, and Camera tabs. Controls apply
live; Save writes versioned `settings.json` alongside `world.json` in the
application support `protoplane_concept` directory. Reload reads that file.
The settings adapter reuses serialized atomic writes and last-valid backups,
with validation and visible load/save errors. Settings are independent of
world history. Available controls are grid path visibility (off by default),
ambient GI, sun intensity, and wall reveal/restore distances.

Ground and wall lattices now permit only orthogonal neighbor connections;
collinear fill still reaches farther nodes through their intermediate dots.
Saved grids are upgraded without modifying committed object outlines. Dots
advertise local connectivity: square for straight orthogonal links, circle
for curved or diagonal links, star for direct connections to every other node.
The same glyphs appear in hover previews and crafting. Custom grids supply
explicit connections; dots never grant additional links.

Crafting zoom interpolates between the cached angled entry pose and a pose
looking along the plane normal. Pinch, native trackpad zoom, and mouse wheel
share a persistent zoom scale across gestures: 1 is semi-focused and 2 is
fully face-on. The camera retains perspective and fits the grid to the available
viewport. Zooming out below 0.9 exits to the cached world pose; it no longer
requires a large pinch from every new gesture.

Devtools → Crafting → Clear world removes crafted objects, derived planes,
residents, and drafts, and restores the 64 ground candidates and paper balances.
It saves through the normal storage pipeline and is one undoable transaction.
Developer settings remain independent of world reset.

Full focus transports the incoming screen-up through the shortest change in
look direction, then selects the closest of the plane's four quarter-turn
orientations. This avoids the world-up singularity on horizontal floors and
keeps grid axes parallel to screen axes. Zoom input retargets a 220 ms eased
response from the currently displayed scale; exiting first settles through
the semi-focused pose before handing back to the world camera.

Crafting now enters at full focus by default. `entryFocusLevel` in settings.json
(and Devtools → Camera) ranges from 0 for the angled semi-focus pose to 1 for
full focus, defaulting to 1 for older settings files too. The optional view
constructor parameter of the same name overrides the saved value. The angled
3D preview remains available independently.

Full-focus orientation also considers the current viewport's usable width and
height after control margins. Each quarter-turn is scored by the distance
needed to fit the actual plane outline. Orientations within 2% of the best fit
are tied, then resolved by proximity to the transported incoming screen-up.
Thus long pieces align with a portrait or landscape window while the nearer
180-degree alternative avoids a flip. Window/device size changes recompute the
pose through the existing camera transition. Full focus uses the fitted camera
distance rather than the semi-focus context-distance minimum.

Devtools → Camera now includes Disable focus zoom, enabled by default (also
for existing settings files missing the new field). With it enabled, inward
pinch/wheel input leaves the entry focus pose unchanged; outward input past a
10% gesture threshold dismisses crafting. Turning it off restores continuous
semi-to-full focus zoom. Entry focus level remains independently adjustable
from 0 to 1 and both values persist through Save/Reload in settings.json.

Devtools → Crafting → Reset drawing on release optionally clears the entire
uncommitted trace when a drawing pointer lifts. It defaults on and persists
as `resetDrawingOnRelease`. Reset happens inside the drawing transaction,
without spending paper or adding a redundant undo entry for an empty drag.
Volume gestures and committed objects are unaffected.

## Recognition priority and transformation

Recipes carry an integer `priority` (lower wins); equal priorities use stable
family order. The creation preview shows the first recognized family instead
of a candidate chooser. Create still confirms the preview and its paper quote.
The controller's explicit choice API remains available for authored fixtures.

Selecting a furnished object exposes Transform when its actual outline has
other valid meanings on the source plane's grids. The picker shows alternative
names and incremental material quotes. Transformation retains ID, outline,
holes and paper color, preserves depth when valid, or adopts the new recipe's
default depth. Added side area is charged; reductions do not refund paper.
Collision/support checks run before commit, surface grids regenerate for the
new family, and the change persists with exact undo/redo. Structural pieces,
openings, screens, and objects with dependents are protected for now.

Valid scissors drawings sustain a line-colored glow while held and commit only on
release. This includes harvesting, new paper, closed cuts, open recipes, and
boundary-to-boundary splits. Readiness uses commit validation, including balance,
overlap, and support constraints, without changing the world. A closed path is
frozen while held; cancellation or a second finger restores its previous draft.
Each drawing and successful action is one saved undo transaction. Apply remains
for depth edits. Transform remains available for existing furnishings.

Paper removal retains its original material, tumbles 10–30 degrees, drifts down
80 logical pixels, and fades over 400 ms. Disconnected removed pieces animate
independently; mixed natural colors remain together on connected sheets. Splits
keep both pieces and pulse only the seam. Placement fills white inward from all
boundaries (including holes) for 75% of its duration, then settles into its final
color/pattern. Temporary coplanar textures and distance masks are baked once;
a fragment shader handles the reveal without per-frame polygon offsets.

Devtools → Crafting exposes Effect duration (100–1,000 ms), Haptics, and Screen
shake. Removal uses a medium haptic; placement/splits use a light haptic. Shake
is capped at 2 logical pixels for 140 ms and moves scene content without moving
controls. Reduced motion uses a 100 ms fade and disables tumble/shake.

Effects never delay commits, saves, or the next drawing. Undo/redo, navigation,
world switching, and Clear world discard effects and their temporary resources;
redo does not replay feedback. A material/action profile resolver permits later
material-specific animation variants. Existing material appearance filters apply
to effects as well as the completed paper.


## Fused crafting surfaces

Touching coplanar floor pieces, or touching coplanar wall pieces, share one
crafting surface when their paper material and thickness match. Corner contacts,
gaps, different elevations and different materials stay separate. The union
preserves holes. Selecting either piece in the scene opens the shared surface;
its grids extend across the join so drawings can span both original footprints.
The joined structural geometry renders once, eliminating the internal edge shade.

`CraftSurfaceFusion` retains the constituent objects and their original support
coordinate frames. Surface aliases expose the same union in their own coordinates;
existing attachment references, grid node indices and room ownership survive.
Each shared surface lists all supporting objects. Explicit object editing still
edits a constituent support; the shared crafting surface is rebuilt afterward.
Fusion is derived after commits and loading, so undo/redo restore it without an
additional material charge or save-format migration. Furniture remains separate;
this rule currently applies to structural floors and walls.

Fused surfaces now have one canonical navigation node. Surface aliases and
superseded wall candidates contribute no duplicate exits; directional queries
from a retained surface alias resolve to the canonical node. Ownership/support
relations still retain the constituent identities.

Wall candidates are regenerated along the simplified union boundary, with IDs
based on their boundary coordinates. Upper-floor candidates use the combined
footprint and aggregate wall supports. Older coordinate frames remain as hidden
support records for existing attachments and explicit edits, but are excluded
from scene picking and navigation. Occupied historical frames are retained across
rebuilds. Rendered structural volumes use the fused footprint. Room enclosure
checks project actual wall coverage onto each authored room boundary, allowing a
long regenerated wall to support multiple original floor footprints. Undo,
redo and load rebuild the same derived representation.

## Soft geometry edges

Crafted objects and previews receive soft shading along their surface boundaries,
including holes and sidewalls, in both world and crafting views. This is a local
edge-shading approximation, not physically computed ambient occlusion or a cast
shadow on neighboring objects. Empty protoplanes, grid connections and landscape
patch seams do not receive the effect.

`SurfaceEdgeShadingCache` groups coplanar faces and unions their outlines before
baking an inner edge mask. Slab and triangle boundaries therefore do not acquire
shadows. The band is 0.025 world units wide. Rectangular surfaces share one 48×48
nine-slice mask, retaining the band width during depth animation. Irregular
profiles use at most 512×512 pixels each, with an 8 MiB cache budget; a profile
that exceeds the available budget omits its shading. Masks are shared across
matching profiles regardless of position or material. Changed geometry rebuilds
only affected profiles; camera motion, highlighting and opacity changes reuse
existing textures.

`ScenePainter` composites the cached mask immediately after each face's fill,
using that face's perspective transform, near-plane clip and opacity. This keeps
shadows off cutouts and foreground geometry and fades them with revealed walls.
The overlay follows material appearance adjustments, preserving depth cues on
brightened paper. Wireframe views skip the effect. There is one additional image
draw per shaded face, no full-screen AO/depth pass and no per-frame blur or
polygon offset. Temporary placement/removal animations retain their own existing
appearance; the completed mesh carries the edge shading.

Unused masks are released after scene synchronization. World switching, hot
reload and view disposal clear owned images. Pixel regressions cover outer and
hole edges, unchanged interiors and slab seams, perspective and transparency.
A depth-animation regression verifies that rectangular geometry reuses one mask
through 90 frames; reported paint timings measure CPU command recording only.

## Adjacent crafting planes

While crafting, swipe two fingers together toward a screen edge to move to the
adjacent face in that direction. Travel is 12% of the viewport's shorter side,
clamped to 48–96 logical pixels. Native trackpad pan/zoom events use the same
navigation path. Each contact sequence moves at most one face; a missing
neighbor leaves the current plane active. A meaningful pinch or rotation locks
out navigation for that sequence. Pinching retains crafting zoom/exit behavior.
Drafts remain attached to their original plane, camera focus eases to the next
plane, and Back restores the world pose from before entering crafting.

### Entities and three query views

The canonical entities remain `CraftPlane` and `CraftObject`, identified by their
existing stable IDs. A protoplane and a crafted surface are both finite
`CraftPlane` entities. `WorldPlane` is the infinite mathematical picking/camera
plane; it is not itself a bounded mesh or world entity. No save migration or
second authoritative world state is introduced.

`ProtoplaneController.navigationGraph` derives three views from those entities:

- **Surface navigation:** `neighbors[planeId]` returns directed shared-edge
  portals, their complete endpoints on the displayed source face, destination
  ID, coplanar/fold type, and same-volume preference. Querying a direction visits
  only this plane's exits. Projecting the swipe ray through the portal segment
  handles off-center partial exits; angular fallback handles edge-on projections.
  Same-volume exits win directional ties, then distance and stable ID break ties.
- **Dependencies:** `relations.outgoing(entity)`, `incoming(entity)` and
  `dependents(entity)` query placement, derivation, support and attachment edges.
  References include an entity kind, so plane and object IDs cannot collide.
  Edges point from prerequisite to dependent. Breadth-first closure visits each
  reachable entity once, including upper planes with multiple supports. A support
  relationship alone does not imply a swipe destination or character walkability.
- **Spatial proximity:** `spatial.query(MapAabb(...))` returns plane/object
  references whose construction bounds intersect a world-space box. It is a
  broad-phase candidate query; picking, visibility and collision still require
  their exact geometry tests. Actual height/depth is retained here. Stylized
  renderer details are not authoritative collision geometry.

Navigation geometry removes the existing structural thickness and display
separations in a single adapter. Portals are then mapped back onto each visible
source. Only positive-length shared boundaries connect planes; corner contacts
and coincident sheets do not. All boundary rings participate, including holes,
and separate shared segments remain separate exits. Structural occupancy is
subtracted from the source region, so a small floor does not hide an entire
ground tile. Completely covered source planes retain outgoing aliases after
creation; arriving from elsewhere selects their crafted surfaces.

### Spatial index and update costs

`CraftSpatialIndex` is a median-split bounding-volume hierarchy (BVH), reused for
boundary candidate discovery and world entity bounds. It stores each primitive
once and handles rotated faces, vertical walls, long edges and flat bounds.
Only edges whose padded boxes intersect undergo the collinear-overlap test,
which follows Boost.Geometry's projected-interval method. Directional ray tests
use Boost's Cartesian Cramer's-rule approach.

The existing `MapOctree` remains useful for tile streaming. A quadtree suits
terrain or a single plane's local dots, but cannot express arbitrary vertical
and stacked surface relationships. An octree can accelerate proximity, but
spatial proximity does not encode shared boundaries or ownership. Its current
implementation also duplicates spanning items across intersected cells. For
these construction surfaces, a BVH is a better initial broad phase. See
[PBRT's BVH discussion](https://www.pbr-book.org/4ed/Primitives_and_Intersection_Acceleration/Bounding_Volume_Hierarchies)
for the distinction between partitioning primitives and partitioning space.

Entity-map writes invalidate the cached snapshot immediately; a subsequent query
rebuilds it once. Draft, material selection and camera changes reuse the cache,
and cache access itself is O(1), without comparing all plane/object entries.
Clear, load, edits, direct entity replacements and undo/redo use the same path.
Replace entity geometry rather than mutating its exposed vectors in place.

This is a lazy snapshot rebuild, **not incremental topology maintenance**. The
median builder sorts at each level, costing O(E log² E) for E boundaries. Spatial
queries prune irrelevant branches; exact boundary work depends on the number of
candidate contacts, and dense coincident geometry can still be quadratic.
Polygon subtraction adds work local to each occupied source. Stored adjacency
uses O(E + A) space for boundaries/connections, and swipe selection is O(d) for
source degree d. Dependency queries cost O(reachable entities + relations).
The transient boundary BVH is released after graph construction; the entity BVH
and adjacency lists are retained.

The deterministic scaling regression compares 256 and 1,024 square planes. It
asserts candidate-work growth, not wall-clock time: these fixtures require
5,160 and 21,576 exact boundary comparisons respectively, approximately 4.2×
work for 4× the planes. Timings printed by the test are debug-run observations,
not device frame-budget guarantees.

### Growing this foundation

The current renderer and collision system retain their existing consumers; the
new spatial and dependency query APIs are available for gradual adoption.
Camera navigation does not imply a valid resident route through a wall or floor.
Doors, stairs and movement clearance need their own traversal policy/edges.

For substantially larger or frequently edited worlds, the next change should
make `_derivePlanes` publish an explicit entity change set. Use the dependency
closure to find affected surfaces, remove both directions of their old portals,
and query the spatial index around their old and new bounds to reconnect local
neighbors. Refit/reinsert affected BVH entries and periodically rebuild for
quality. Publish the resulting graph atomically with a world revision; discard
stale asynchronous builds after undo/load. Merely adding dirty flags now would
not make updates local because `_derivePlanes` currently replaces all derived
planes on each structural commit.

Keep semantic attachment frames/edge provenance separate from render offsets as
new plane types arrive, replacing the current generated-ID adapter at that
boundary. Retain stable entity IDs and typed relations across all derived views.
Large worlds can combine a coarse chunk/octree for streaming with per-chunk BVHs
and explicit cross-chunk portal IDs. This avoids committing game semantics to
one spatial tree or requiring an ECS rewrite before there is a measured need.

Reset drawing on release controls incomplete drafts only. Valid open recipes and
closed actions commit on release in either mode. With reset disabled, incomplete
paths persist across drags; invalid completed actions retain actionable errors.


## Harvestable paper landscape

The preserved Pastel preset begins covered in five natural paper colors: Coral, Butter, Sage, Mist,
and Sand. A seeded world-space Perlin field creates continuous, softly grained
patches across tile boundaries. Placed paper remains solid-colored with crisp
edges. The natural layer uses a cached 16-subdivision polygon field per tile;
interpolated band boundaries avoid square pixel edges. These exact polygons
supply the cached texture bake and material accounting. Following GameView's
Perlin landscape approach, normal rendering uses a shared GPU texture atlas:
256 pixels per tile, one-pixel gutters, and one perspective-correct sprite per
tile. Harvesting rerasterizes only changed slots; camera movement, hover, and
drawing reuse the atlas. The original polygon renderer remains a fallback for
near-plane clipping and explicit geometry debug views.

A closed ground drawing harvests any remaining natural paper inside it. Mixed
cutouts collect only untouched portions. A drawing entirely on cleared backing
uses the existing floor recipe instead. Cuts overlapping placed objects are
rejected. Harvesting never consumes inventory, removes the ground plane, or
changes adjacent-plane navigation. There is no regrowth or cross-tile cutting.

Collected material totals 128 units per square world unit, divided among the
actual colors inside the cutout. Fractional yields accumulate per color across
cuts and saves. The existing paper carousel cycles through all five colors;
a compact color/yield display appears on completion. Ground dots use a 5×5
orthogonal lattice; old nine-node indices survive migration, with new nodes
appended and legacy long steps expanded through intermediate dots.

Loop closure previews the harvest yield without changing inventory or depletion.
Pointer release commits both as one saved undo transaction; pointer cancellation or a
second finger restores the pre-drag world without awarding material. API harvests
outside an active drag commit immediately. Undo/redo restore material, depletion,
and drafts together. Pastel worlds and Clear world start at 256 units per color.

Version 2 saves record the generation version, seed, harvested regions, and
fractional remainders. Old saves retain their original balances, receive 256
Mist and Sand units, and mark existing ground-object footprints harvested
without awarding material. Balances can exceed the former 12,800-unit ceiling.
Tile geometry caches survive ordinary scene refreshes, and unchanged tiles
reuse their geometry when history or loading replaces the world state.


### Ink worlds and collectible patterns

Ink remains available alongside Paper (the new default) and Pastel in the developer Crafting tab. Pastel keeps `world.json`; Ink uses `world-ink.json`, with independent
atomic backups. Switching cancels the current gesture, retries and flushes saves,
and refuses to switch on failure. Loaded controllers remain in memory, retaining
each world's history, selected material, and drafts. Clear world affects only the
selected world. Settings remember the selected preset.

Stable material IDs replace serialized colors in version 3. Versions 1 and 2
migrate as Pastel; objects, balances, and depletion are preserved. Ink starts with
256 White, Black, Dots, and Lines units and no Red or Blue. Its seeded field is
calibrated over the starter domain for approximately 40/20/15/15/8/2 percent area
coverage respectively. Both accents occur in the starter world; Blue is rarer.
Harvest accounting uses material area, including patterns, at the same 128 units
per square world unit with material-keyed fractional remainders.

Ink has no pastel grain. Dots occupy about 20% of white paper and diagonal lines
25%, with 16 repeats per world unit. Ground bakes these into its existing atlas;
crafted faces use cached repeating GPU textures with stable planar coordinates,
including extrusion sides. Cuts preserve the original material and texture phase.
Inventory uses cached pattern swatches. Lighting remains grayscale, backing is
mid-gray, and controls/highlights are neutral. Material definitions and preset
identity participate in ground atlas cache keys; replaced atlas images are disposed.

Validation includes representative-seed coverage, pattern collection and crafting,
cuts, save migration/recovery/isolation, switch failure, retained history/drafts,
and dirty-slot atlas reuse. The same live debug camera-pan check measured median
ScenePainter 0.29 ms (p95 0.74 ms), GPU raster 0.45 ms (p95 0.71 ms), across 63
frames. No per-pattern geometry is generated during camera movement.

### Profiling landscape rendering

The ScenePainter and GroundTextureAtlas timeline events are available in Flutter
DevTools. PaintStatsProbe records submitted faces, draw calls, and paint time.
A fresh 64-tile landscape normally submits 64 sprites (128 triangles), rather
than tens of thousands of colored polygons. Atlas images are replaced only on
content changes and disposed when replaced or when the view closes. Hot reload
rebuilds the GPU cache while retaining the model and camera.

Protoplane resolution defaults to three cells per side (four points per side).
Devtools → Crafting → Protoplane cells selects integers 1–5 and persists as
`protoplaneCells` in settings.json. The live view applies this to ground,
wall-candidate and upper-floor grids, including loaded candidates and newly
derived ones. Crafted surfaces retain their contextual motif grids. Resolution
changes preserve object geometry and paper/landscape state, but discard drafts
and session history whose node indices refer to the previous lattice.

Devtools → Style exposes separate Landscape and Crafted geometry appearance
profiles: Brightness (−1–1, neutral 0), Contrast (0–2, neutral 1), Saturation
(0–2, neutral 1), and Hue (−180–180°, neutral 0). Contrast scales RGB around
mid-gray; brightness adds a uniform offset. Alpha is preserved. Settings apply
live to plain surfaces and textures and persist in settings.json. Older
appearance settings retain hue/saturation; retired dark/light fade values are
ignored and brightness/contrast begin neutral.

## Grid feedback and connection styles

Devtools → Crafting → Line color opens an HSV and six-digit RGB hex picker.
The default is chartreuse (`#7FFF00`); selected dot fills, trace glow, and split
seams share it. This is interface feedback and does not recolor paper materials.
The preference is included in the existing settings Save/Reload flow.

Connections selects Orthogonal neighbors (square dots), Diagonal neighbors
(circle dots), or Any point (star dots). Diagonal mode adds only the adjacent
row/column diagonals, never arbitrary long or knight-move edges. Long straight
gestures can traverse intermediate permitted neighbors. All edges still respect
plane boundaries and holes. The default remains Orthogonal neighbors.

The setting applies to ground, wall-candidate, and upper-floor protoplanes;
authored recipe grids retain their own connections. Mode changes preserve node
indices, construction, inventory, and history. They cancel the active gesture
and discard only drafts whose edges are no longer allowed. New protoplanes and
history restoration use the selected mode. Grid metadata persists dot semantics,
so a diagonal 3×3 center remains a circle even when it reaches all eight neighbors.

Loop closure is provisional while the drawing pointer is held. Staying within
24 screen pixels of the start keeps the closing segment snapped; pulling out
of that zone removes only the repeated start node immediately, so the same
drag can continue toward a different point. This bypasses past-point dwell for
the closing segment only. Releasing a valid closed loop commits normally and
the complete drag remains a single undo transaction.

Landscape tile colors and patterns now reuse GameView's existing
`assets/textures/paper/white.jpg` grain. A 60% multiply overlay uses the shared
two-world-unit repeat, aligned in world coordinates across tile boundaries.
The image loads once per view and is baked into dirty atlas slots; camera
movement and hover reuse the atlas. Exact harvest geometry/material colors and
paper accounting are unchanged. World switches retain the loaded texture;
leaving the view disposes the shader and image.

Closed-region paper placement now uses a fixed 200 ms double fill instead of
the falling/reveal animation: white sweeps from the projected region's bottom
to top during 0–100 ms, then the paper's current color repeats the sweep during
100–200 ms. Both passes clip to the actual outline and holes in screen space,
so they remain bottom-to-top for floor and wall planes at any orientation.
Placement starts without shader baking, has no camera shake, and hands back
to the normal object mesh at 200 ms. Reduced-motion mode crossfades the same
colors instead of sweeping. Removal/split and open screen effects retain their
existing behavior and duration settings.

Crafting strokes transition from the configured chartreuse to white over
100 ms only when closed on the start point and `drawingReady` confirms a valid,
affordable operation. Open or invalid strokes retain chartreuse. On release,
a snapshot of the stroke (including its live partial edge) fades out over
750 ms regardless of commit success or release-reset settings. This visual
snapshot survives draft clearing/creation without adding history entries.
Retained drafts reappear when drawing resumes; stored geometry is unchanged.

Devtools is a non-modal left inspector, sized to the current window and capped
at 320 logical pixels wide. Its vertical bounds follow the measured header and
crafting footer, with a gap on both ends. Contents render at 75% of normal
Flutter sizing. Slider labels and values share a row; tabs scroll horizontally
and footer buttons wrap on narrow screens. The title, tabs and footer stay
fixed while tab contents scroll independently.

The viewport background is a three-stop vertical gradient: blue at the bottom,
purple at the midpoint and warm orange at the top. Devtools → Style includes a
gradient preview and Bottom/Middle/Top color pickers with HSV and hex entry.
Colors persist as `backgroundColors` in settings.json; old files use the new
default palette.

Paper grain now has independent Texture strength (0–1), Texture scale
(0.25–8 world units per repeat), Texture brightness (−1–1) and Texture contrast
(0–2). The existing Landscape controls are labeled Landscape fills / patterns.
Their appearance filter is baked into the colored fills before the independently
filtered grain is composited, rather than filtering the completed tile. Changes
invalidate atlas slots only when style values change; pan/hover reuse them.
Texture settings persist separately as `paperTextureAppearance`,
`paperTextureStrength`, and `paperTextureRepeat`. Defaults retain the previous
60% grain strength and two-unit repeat.

Harvested landscape regions now leave genuine transparent holes. The tile
atlas has no opaque backing under cuts, paper grain clips to remaining paper,
and dirty slots overwrite old pixels with source blending (including alpha).
Fallback mesh geometry also omits harvested regions. Thus the current
background gradient shows through after removal, including existing saved
cuts. A render-cache version forces older opaque slots to refresh.

## Applying landscape style edits

Landscape texture and fill/pattern sliders now edit an isolated
`LandscapeStyleDraft`. They update their labels without mutating active settings
or invalidating the atlas. Update applies all pending landscape edits in one
rebuild; Save also applies pending edits before writing settings. Reload resets
the draft to the saved values. Closing without Update/Save discards only those
pending landscape edits. Background and crafted-object controls remain live.

The baked atlas remains the gameplay path: camera movement samples existing
tile sprites rather than regenerating paper. The prior slider path rebuilt all
64 slots on every value event. A local CPU/raster benchmark measured 16 updates
at 1,711,556 µs and 1,024 rasterized tiles before staging; with staging it measured
9,490 µs and zero new tiles, followed by one explicit 64-tile Update at 150,380 µs.
These are test-environment CPU timings, not device GPU frame-rate measurements.
Regression tests assert atlas identity and rasterization counts rather than
fragile wall-clock limits. Fully continuous live style changes would favor a
runtime shader, but explicit application keeps normal gameplay inexpensive.


## Layered Paper islands

Paper is a separate preset in `world-paper.json`, with independent atomic backups,
inventory, drafts and undo history. On the first launch after this addition it
becomes the selected preset; subsequent selections are remembered. Existing Ink
and Pastel saves retain their terrain, materials and balances. World-save version
4 adds sheet definitions and layer depletion; versions 1–3 remain readable.

The starter white sheet is 5×5 units, centered at the origin and rotated +4°.
The 8×8 northeast sheet is rotated −3°, with a two-unit gap between the complete
stack bounds on each map axis. Map northeast is +X/+Y (world +X/−Z). White,
graphite and cork have thicknesses 0.03, 0.06 and 0.18 units. Each lower sheet is
rotated independently and sized to contain the one above with a 0.10-unit margin.
The surface uses restrained white/off-white grain rather than material bands.

Sheets own polygon footprints, elevation, thickness and depletion. Stable tile
windows and the existing spatial index partition them for editing; no octree is
needed. Exposed polygons drive picking, harvesting, rendering, placement support
and navigation. Partial perimeter fragments, including tiny triangles, remain
valid. Tile grids keep their node identities as material disappears.

Tap exposed material to focus its tile. Focus stays anchored across all depths
in that tile. A closed outline resolves the highest exposed layer with a
positive-area intersection; touching an edge alone does not select that layer.
Scissors clip to that layer's exposed area and commit on release, leaving lower
layers untouched. Graphite still requires the eraser. Removing cork opens a hole
through the island. Cuts remain single-tile operations.

Place resolves the same highest intersecting layer and clips the footprint to
its exposed support. Disconnected fragments become separate objects in one
transaction, with one area-based material charge and matching completion effects.
Empty intersections do nothing. Operation targets and clipped previews are cached
against the outline and tile-column revisions. Graphite and cork are resources only, with
zero initial balance; white starts at 256 and is the only crafting material.
All three yield 128 units per square unit, with persisted fractional remainders.
Terrain supporting construction cannot be harvested underneath it.

Devtools → Crafting includes Tile grid opacity (0–100%, default 12%), independent
of dot/stroke appearance and internal grid connections. The focused grid's label
identifies terrain focus as Ground.

Ground uses shared, world-anchored atlas slots at 128 pixels per tile. Cache keys
include sheet geometry and intersecting depletion, so undo/load also invalidate
only changed slots. Harvesting updates its vertical tile column; sidewalls cache
by sheet revision and use complete sheet/cut boundaries, never internal tile
seams. Depth-sorted atlas sprites interleave with outward-facing sidewalls and
undersides; the older flat-ground render path remains unchanged. Camera motion
reuses textures. Unit/widget tests cover both viewport orientations, recovery,
legacy worlds, yield conservation, layered support, navigation, and cache reuse.


### Graphite eraser

Graphite uses an Eraser instead of closed scissors outlines. Selecting exposed
Graphite automatically selects the eraser; White and Cork still use scissors.
The eraser has a round 0.055-world-unit radius and scrubs a world-aligned 16×16
cell grid within the selected tile. Swept pointer segments cover skipped input
samples. Squares pop for 180 ms as they are removed; at most 96 visual fragments
are retained, with no meshes or textures allocated per particle. Reduced motion
omits the particles. Crafting dots are hidden while erasing.

Each touched tile stores just a 32-byte depletion bitmask (base64 in save version
5). Untouched tiles allocate no mask. Legacy polygon cuts are preserved. A
transient area lookup is prepared once at gesture start, then pointer moves use
bit tests and swept-rectangle hit tests. A cell is removable only when all its
remaining graphite is exposed and it does not support construction; clipped
island/legacy-cut edge cells yield their actual remaining area. Partly covered
cells wait until their covering paper has been removed. A full square yields
0.5 units, using the shared fractional balance system.

Pointer events are batched once per frame. Surviving bits coalesce into rectangles
for the cached geometry/atlas; graphite and the newly exposed cork update in the
selected column. Graphite sidewalls cache per tile and neighboring boundary
masks, avoiding whole-sheet polygon subtraction and internal tile seams. Camera
motion does not rebuild these caches. The brush remains on its original layer
throughout a scrub; release retains the tile's focus and tool. The eraser resolves
exposed graphite in the focused column regardless of the focus anchor's depth.

A scrub is one undo/save transaction. Its live yield and depletion are provisional
until release. Cancellation, a second finger, tool/world changes or leaving the
view restore the gesture snapshot and discard pending input. Revisiting erased
cells never yields material twice. The eraser affects only the selected tile;
Place continues to build white paper on exposed support.

### Pencil marks and discovered motifs (Paper world)

Landscape white paper counts as an existing floor: draw furniture directly on
it without cutting and placing another sheet. Pencil, motifs and mark erasing
work directly on its remaining material. Save version 8 permits stable terrain
tile IDs as mark owners; depletion clips marks, and history restores them.
Lower exposed layers remain accessible to scissors and resource erasing.
Terrain marks share the bounded pencil cache and composite in the existing
atlas depth pass.

Placed and landscape white Paper-world surfaces use a fixed half-tile scissor lattice (2×2
cells), with quarter-tile pencil dots (4×4 cells). Their original support-plane
coordinate frame is the lattice frame: cutting, fusion and depth changes never
fit a replacement grid to a fragment's bounding box. Recipe eligibility is
inherited from the support; the automatic recipe-grid carousel is hidden on
placed paper. Ink and Pastel behavior is unchanged in this feature.

`pencil.dart` holds exact segments, material clipping, coincident-coverage
subtraction, intersection splitting and motif recognition. The scissor graph
contains only the half-tile lattice and committed marks, split at crossings.
Pencil presentation jitter never enters this graph. New coverage costs 4,000
thousandths of graphite per unit of local length, rounded once per completed
drag or stamp. Retracing is free; insufficient inventory leaves the preview
uncommitted. Erasing removes touched committed segments without refunds.

Save version 6 adds `pencilMarks`, `motifs`, `graphiteMilli` and `nextStrokeId`.
Marks have stable stroke IDs and are stored per constituent object, in that
object's persisted support-plane coordinates. Queries transform and deduplicate
those marks on fused work surfaces; new marks are distributed to their original
members. Structural edits clip each member's marks to retained material.
Extrusion moves their drawn face without adding marks to sidewalls. Versions
1–5 load with empty marks and discoveries; Paper drawing grids are regenerated.
Undo restores geometry and graphite but retains discoveries learned in the
current world. Loading a world replaces that knowledge, and clearing the world
clears it.

The four initial motifs are Parallel lines, Crosshatch, Cross and Diamond.
Recognition checks complete required segment coverage under quarter-turns,
including reversed or subdivided strokes and additional marks. A complete tile
must remain present. Discovered motifs appear only with Pencil, support rotated
tile previews and atomic placement, and emit one discovery notification.

Mark revisions invalidate affected drawing graphs separately from structural
adjacency. Active previews repaint without rebuilding scene geometry. Committed
marks use deterministic local graphite variation and an 8 MiB, 32-tile texture
cache at 256×256 pixels per tile. Camera motion does not bake textures. If the
visible working set exceeds the cache, excess tiles use vector drawing rather
than omit marks. Face-local compositing uses existing perspective, depth sorting,
and surface opacity, with mark opacity .8 while crafting and .35 in 3D.

Regression coverage lives in `test/protoplane/pencil*_test.dart`, including
geometry, ledger and knowledge persistence, migration, fused support frames,
splitting and extrusion, pointer cancellation, narrow layouts, and rendered
pixels through holes.

Separate follow-up: retire Ink and Pastel worlds and consolidate their production
code paths around Paper. Legacy world files should not be deleted as part of
that cleanup.

Focused context is adjustable in the Crafting dev-tools tab with **Context tiles**
(0–4, default 1) and **Context opacity** (0–100%, default 35%). These settings
persist independently of world saves; older settings use the defaults. Context
is selected around the full support footprint, including fused surfaces, on the
same level. Camera framing reserves room for the editable surface between the
controls while fitting the surrounding context into the viewport. Neighbor
traversal interpolates both camera pose and mesh opacity over 650 ms; outgoing
context stays present until its fade completes.

The **safe zone** is the central viewport rectangle left between the measured
header/status area, left toolbar, right sidebar, and bottom controls, including
platform insets and an 8-pixel clearance. It updates after layout, so tool
changes, wrapped status text, window resizing and phone rotation change the
usable area. Full focus fits the active plane to this rectangle without changing
its proportions and centers it in the rectangle rather than the screen. Its
limiting dimension reaches the rectangle boundary. Semi-focus retains the wider
context framing. Refitting is deferred while a drawing or erasing gesture is
active, then animated normally.

**Dev Tools → Camera → Safe zone** toggles a non-interactive outline and subtle
fill. The toggle is persisted and defaults off; it changes only the diagnostic
graphic, not the fitting behavior. `safe_zone_test.dart` verifies asymmetric
projection fits for floor and wall planes, and `safe_zone_view_test.dart` checks
real control layout and pointer transparency at desktop and phone sizes.

Scissors are cut-only: their completion APIs can harvest, remove, or split paper,
but cannot fall through to recipe placement on empty/depleted support. Use
**Place** for additions in every world. Entering an existing object's Edit action
selects Scissors. Construction and harvesting regression fixtures select their
intended tool explicitly.

**Dev Tools → Crafting** has separate **Cutting line color** (red by default) and
**Addition line color** (chartreuse by default) pickers. Both persist. Older
settings retain their existing addition color and receive the default red cut
color. Stroke previews and completion effects use the corresponding tool color.

An invalid released cut or addition retains only its 750 ms fading visual trace;
it discards the pending draft without changing geometry or inventory, showing a
candidate/recipe panel, or reporting a validation banner. This also applies when
Reset drawing on release is disabled. Valid volume editing keeps its Apply panel.

## Gesture diagnostics

Devtools → Camera → Gesture overlay enables read-only map/crafting telemetry,
persisted as `showGestureDebug` (default false). Each contact gets a stable
colored P-label, hollow start marker, filled endpoint, directional drag line,
start/end screen coordinates and dx/dy in logical screen pixels. The readout
also includes pointer IDs, input kind and buttons. Two-finger movement shows
the centroid displacement, its screen cardinal intent, and the actual
`PlaneSwipe` result: Pending, Pinch / rotation, Consumed / blocked, or the
accepted Right/E, Left/W, Up/N or Down/S swipe. Accepted verdicts stay latched
as the camera transitions; no second recognizer drives navigation.

Released/cancelled traces remain until the next gesture starts. The IgnorePointer
overlay does not intercept drawing, panning or navigation. Native trackpads show
the OS pan centroid because Flutter does not expose individual contact positions.
Scroll events are labeled separately with their delta vector, which helps
identify devices sending scroll signals rather than native pan/zoom sequences.
The readout uses the crafting safe zone to avoid the existing control bars.


The inspector is mounted inside the game view rather than a dialog route.
There is no dimming scrim or input barrier outside it; the map remains pannable.
In focused mode, primary dragging while inspecting pans the camera along the
active plane instead of drawing, without changing gameplay state or history.
The dock reserves space in the focus safe zone and temporarily replaces the
left crafting tool strip; top controls, paper selection and the crafting footer
remain accessible. Closing restores the tool strip. Panel state and unapplied
landscape edits survive camera panning and parent rebuilds. Color-picker dialogs
also use a transparent barrier to avoid tinting the scene during color selection.

### Area discovery fog and orbit limits

Paper islands are discrete discovery areas, keyed by their stable island IDs.
Area footprints use all original sheets, so depletion never changes entry
boundaries. The starter begins revealed. Moving the orbit camera's ground
target into another area calls the idempotent
`revealArea(areaId, source: 'camera')`; other gameplay systems can call that API
and subscribe to `onAreaRevealed`. Zoom, orbit rotation and focus transitions
do not constitute entry. The notification fires only on a new discovery.

Save version 7 adds `revealedAreas`. Migration reveals the starter and islands
with construction or depletion. Discovery survives ordinary crafting undo and
gesture cancellation. Clear world starts a new discovery epoch; undoing/redoing
that reset restores the corresponding discovered set. Loading never replays
reveal notifications. Existing atomic writes, backups and save-before-switch
behavior remain in use.

Fog is a direct canvas fragment shader, independent of terrain drawing. A
256-square world-space distance texture uses two channels for distance precision;
mask generation runs in an isolate and changes only with area definitions or
discovery. A single reusable periodic noise texture supplies two drifting cloud
layers sampled at different virtual heights. Manual bilinear sampling avoids
distance-field bands and works on both Skia and Impeller (samplers remain global,
rather than function arguments). Camera updates supply ray uniforms only.
The fog repaint boundary does not repaint the scene during idle animation.

An 800 ms mask crossfade reveals a new area. Focus supplies a temporary clear
rectangle without changing discovery or rebuilding the mask. Hidden-surface
picking uses the stable geographic field, not moving cloud noise. The shader
has a static, interpolated-vertex fallback, including during loading. Animation
pauses for hidden tickers, app backgrounding, disabled fog and reduced motion.
Replaced images and shader instances are disposed.

Devtools → Fog supplies Paper clouds, Charcoal mist and Background haze themes,
independently retained colors/settings, arbitrary base/highlight color pickers,
opacity, clear margin, edge softness, cloud scale, contrast, drift and apparent
depth. Reset theme restores that theme; Reveal all areas persists discoveries.
Disabling the overlay does not erase discovery. Fog defaults to Paper worlds;
legacy Ink and Pastel terrain is unchanged.

Devtools → Camera supplies Nearest distance and Farthest distance (defaults
2 and 25 world units, range 1–60, minimum separation 0.5). Changes clamp orbit
distance and pending zoom targets together; focus poses remain independent and
the return pose respects updated limits. Paper orbit zoom has strict bounds;
other map-camera consumers retain their existing spring overshoot. Paper pan
bounds encompass both stacks with a two-unit margin.

Validation: discovery, migration, malformed state, backup recovery, reset
history, strict camera limits, fallback rendering, theme persistence and
overlay-only repaint/cache reuse have regression tests. Non-animation widget
fixtures explicitly freeze fog; the dedicated overlay suite exercises live
cloud ticks. Run `flutter run -d macos --profile -t tool/fog_profile.dart` for
a fresh unsaved world and matched 360-frame camera pans; timings and portrait/
landscape theme captures are written to `/tmp/fog-profile.json` and
`/tmp/fog-*.png`.

On 2026-11-05, Apple M5 / macOS 26.6.2 / Impeller Metal, fixed 900×700 logical
viewport: p95 raster time was 0.589 ms fog-off and 0.607 ms fog-on (+0.018 ms).
Idle clouds caused zero scene paints; camera panning rebuilt zero distance
masks, atlas slots or wall meshes. These are desktop measurements, not an
iPhone performance claim.

## Pencil presentation

The pencil now uses a six-pixel grey live stroke with a soft halo, following the
pointer between quarter-grid snap points. A successful release commits the
same exact pencil geometry/accounting as before, while a presentation-only
360 ms melt thins, fades and gently drops small sections of the live stroke to
reveal the textured graphite underneath. Rapid strokes retain independent
bounded trails; reduced-motion mode fades without dropping/fragmenting them.
Cancellation removes the live stroke; undo and plane/world changes clear transient trails.

Persistent graphite replaces sine-wave jitter with coordinate-hashed irregular
knots: alternating straight runs and small linear kinks, plus variable ink
opacity and width. The pattern is deterministic in paper coordinates and keeps
its orientation when segment order reverses. Camera changes never reroll or
rebake it. Logical pencil segments remain straight and retain existing cutting,
recognition, persistence and paper/graphite costs. A texture-cache render version
invalidates old periodic appearances without migrating stored pencil marks.
