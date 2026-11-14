# Protoplane concept

Open `protoplane_concept` in the developer menu (`/protoplane-concept`). This
prototype has its own world, paper inventory, history, and local save. It does
not change GameView or the grid-puzzle rules.

## Light pencil and regions

Orbit and Light pencil stay available in world and focus views. Orbit is the
teal first tool: primary or secondary drag rotates, middle drag pans, and wheel
or pinch zooms. Orbit surface taps enter focus. Existing two-finger and trackpad
navigation also works while crafting. Navigation cancels the active drawing
gesture and preserves completed light paths and regions.
Leaving focus selects Orbit, so the next drag or surface tap can navigate immediately.

Light pencil draws free glowing orange paths on any material. Pointer-down
chooses a surface and locks the stroke to its plane without moving the camera.
Light pencil, Cut, and Place use the configured drawing resolution and
connections, orthogonal by default. Connected coplanar tiles can be crossed;
different elevations and perpendicular faces remain separate. Physical object
ownership and original coordinate frames are retained.
Light pencil uses the same animated pips, six-pixel strokes, segment glow, and
cursor-following partial lines as Cut and Place, including in the world view.

A closed loop creates a region. Boundary-to-boundary paths subdivide existing
regions, including intersections with earlier paths. Incomplete paths remain
available to close or extend during the session. Region interiors do not
overlap; uncovered remainder areas are implied regions without orange outlines.
A program hover temporarily fills its target and previews the generated geometry.
Combine selects two adjacent regions, removes their internal seam and preserves
holes. Corner contacts and different planes cannot combine.

Each region has one use. A successful program consumes only its target; shared
boundaries needed by other regions remain. The consumed area can become implied
space again where material permits. Clear regions clears the workspace. Removed
lines fade, respecting reduced motion. Undo/redo restores regions and their use
alongside material edits. Regions survive focus changes and orbiting, but end
when leaving the prototype and never enter world saves.

## Program stickerbook

Open Programs with the book button, `/`, or Cmd/Ctrl+K. Search names and aliases;
arrow keys select a sticker, Enter chooses it, and Escape closes search. Drag a
sticker onto a region, or choose it and click/tap a region. Toolbar Cut, Place,
Eraser, Volume, and Combine icons can also be dragged onto regions; tapping
them retains their direct-tool behavior. The preview includes a numeric paper
quote. Invalid targets use red fill and a reason icon with an
accessible semantic description: size, orientation/material, collision, missing
support, insufficient paper, or an unusable outline.

The initial catalog is explicit:

- Cut removes the target material using existing cutting, harvesting, and
  dependency protections. Erase removes graphite and legacy marks.
- Place fills the outline with plain paper: horizontal floors or vertical walls.
  Direct open Place paths still construct walls/floors, and direct Cut and Eraser
  gestures remain available. Closed paths no longer infer furniture.
- Volume stages a selected paper region for depth adjustment. Apply commits the
  subdivision and consumes the region; Cancel changes nothing.
- House fits the largest supported grid-aligned rectangle fully contained in
  the region, accounting for holes and obstacles. Both dimensions must be at
  least one tile. Equal-area ties prefer the drop point, then stable coordinate
  order. An L-shaped three-tile region fits a two-tile house. It creates an
  editable floor, four walls, a doorway on the side nearest the drop, and a flat
  roof. Story height is 1, thickness .02, and doorway .25 × .7.
- Pool follows concavity and holes, preserving islands. It requires area .25
  and a connected interior after a .02 inward lining offset. It excavates
  terrain through depth .5, creates a paper bottom and lining, and renders water
  .05 below the rim. Unrelated structures and their supports are protected.
  Water is visual only and disappears if the editable basin is breached.
- Rug follows a supported horizontal region with a thin paper layer.
- Table fits a contained rectangle at least .5 × .5 and creates a .35-high table
  with a .03 tabletop and four legs.
- Picture Frame fits a vertical rectangle at least .25 × .25, with an empty
  center, border 10% of the shorter side, and depth .02.

House, Table, and Picture Frame consume the entire selected region even when
the fitted rectangle uses only part of it. The remainder becomes implied space.
There is no runtime craft recognition, inferred Transform picker, paid pencil
dwell, or motif creation UI. Previously saved objects and marks remain editable.

## Material and history

One square tile is 128 material units. The finite starter balance remains 256
white paper, with zero graphite and cork. Devtools → Crafting → Unlimited paper
is enabled by default, including migration from settings without that field.
It displays `∞`, bypasses white-paper deductions for direct tools and programs,
and preserves the finite balance. Turning it off restores normal accounting.
Quotes are always calculated from the same component geometry used for display,
collision, and supports: net planar area plus perimeter times depth.

Programs evaluate every step on a detached world before mutation. Application
revalidates current geometry, dependencies, inventory, and region availability.
A successful program commits geometry, balances, assembly metadata, region use,
history, and the save callback together as one undo action. Failed operations
change none of them. Volume consumes its region only after Apply succeeds.

## Implementation and persistence

`RegionWorkspace` stores plane frames, source references, disjoint regions,
remaining uses, and finite drawn boundaries. A shared surface resolver unions
connected coplanar work areas without transferring ownership. The program catalog
uses a common evaluation result containing preview geometry, quote, typed issue,
and staged world. Rectangle fitting tests fully contained cells, not just their
corners or centers. Polygon splitting uses the existing planar graph and Region
Booleans; lining offsets follow Boost.Geometry negative-buffer and miter-join
ideas ported to Dart, without a native dependency.

Program outputs are ordinary editable objects. Version 10 adds assembly identity,
component roles, support references, footprints, and reconstruction parameters.
Pool water derives from saved basin geometry and current lining/bottom components.
Readers retain earlier supported formats and preserve legacy marks, balances,
and applicable cut/depth edits. Session regions and previews are excluded.
Native storage retains serialized writes, atomic rename, valid backup recovery,
and protection against overwriting an unrecoverable damaged world.

## Validation

Run `flutter test test/protoplane`, relevant shared geometry/rendering tests,
`flutter analyze`, and `flutter build macos --debug`. Region/program tests cover
finite partitions, holes, fitting, atomic application, exact undo/redo, water
basins, supported furniture, stale targets, save round trips, and unlimited-paper
migration. Widget checks cover world/focus drawing, stickerbook search, cancellation,
and portrait, landscape, and desktop layouts. Legacy recipe helpers remain for
loading and regression fixtures; they do not drive the new creation UI.

## Bedrooms and flatmates

Existing bedroom objects, their attachment geometry, and resident evaluation
remain supported. Bedroom recipe families are not in the initial stickerbook;
legacy saves retain their grids and objects without resetting balances.

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
Orbit primary/secondary dragging to rotate, middle dragging to pan, and two-finger navigation. Crafting
always follows the actual pointer. Native trackpad pan/zoom is supported.

Plane focus preserves the incoming azimuth and perspective lens, tips only
enough to read the grid, and eases over 650 ms. Same-level neighboring tiles
(including diagonal neighbors) remain at 18% of their normal opacity; more
distant context fades out. Context is not selectable while crafting. Back or
pinching out restores the cached world pose and fades the surroundings back in.

Live strokes follow the permitted straight or curved edge toward the pointer
before the next node is reached. Reaching a node pulses the completed segment in the line color; a valid direct operation brightens the entire trace. These transient effects
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

Legacy floor acetates retain their stored grids and examples without resizing
existing objects. Copies share coincident nodes, retain curved controls, and omit edges
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

Reset drawing on release controls incomplete drafts only. Valid open structural paths and
closed actions commit on release in either mode. With reset disabled, incomplete
paths persist across drags; invalid completed actions retain actionable errors.


## Harvestable paper landscape

Paper is the only world. Its layered terrain exposes white paper, graphite, and
cork; scissors harvest paper/cork and the eraser scrubs graphite. Yield is 128
units per square world unit, with fractional remainders persisted per material.
Harvesting clips to exposed material and updates affected atlas columns and
navigation. Placed paper remains smooth. Camera movement reuses the terrain
atlas (128 pixels per tile with one-pixel gutters).

Release commits geometry and inventory as one undo transaction. Cancellation
restores the unfinished gesture. Paper uses the shared drawing grid, without
requiring paid pencil marks.

### Paper-only runtime and persistence

Ink and Pastel have been retired. Their world selector, session manager, colored
noise terrain, collectible pattern atlas, and runtime recipe-grid generators
have been removed. The controller always creates layered Paper terrain, and
terrain is non-null throughout the Paper runtime. New creation uses explicit
programs and a shared drawing graph independent of legacy marks.
Authored legacy recipe examples remain in test fixtures for geometry coverage.

Paper continues to use `world-paper.json` and its atomic backup. Existing Paper
save versions 3–10 with layered terrain load through the same validator, retaining
objects, inventory, marks, discovery, and attachments. Serialized `preset: paper`
is kept as a compatibility discriminator, not a runtime switch. Retired presets
are rejected before mutating the current world. Existing `world.json` and
`world-ink.json` files are neither read nor deleted. Obsolete world preferences
are ignored when loading settings and omitted from newly saved settings.

This cleanup also fixes scissors incorrectly rejecting placed paper supported
by a graphite terrain plane, and clears cached terrain-edge crop boxes when
leaving focus. Paper save recovery, undo, scene transitions, crafting, and
material isolation are covered by the protoplane suite.

### Profiling landscape rendering

The ScenePainter and GroundTextureAtlas timeline events are available in Flutter
DevTools. PaintStatsProbe records submitted faces, draw calls, and paint time.
Visible terrain submits atlas sprites rather than per-fold geometry. Atlas images are replaced only on
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

The setting applies to drawing surfaces, including the connected coplanar
workspace. Stored legacy grid definitions remain available for existing edits. Mode changes preserve node
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

### Legacy graphite marks

Existing saved pencil marks retain exact clipping, material erasure, deterministic
texture appearance, and their stored balance data. New Light pencil paths live
only in RegionWorkspace and never spend graphite or discover/stamp motifs.

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

### Linear structural placement

Open Place paths on paper floors create walls; paths on walls create floors or
ramps. Paths follow the shared configured drawing lattice used by Light pencil and Cut. Closed outlines place plain floors or walls; furniture requires its explicit program.
Consecutive straight segments collapse into one sheet. All sheets in a polyline
validate and commit atomically, with one paper charge and undo entry.

`LinearAttachment` stores support identities, an edge in the original support
frame, extent and side in version 9 worlds. Each sheet has its own stable
construction frame and visible `surface-` plane. Height/Reach starts at one tile
and changes in quarter-tile steps; Flip changes which side of a wall supports a
floor/ramp. Shrinking does not refund paper. Existing dependency restrictions
protect attached objects; extent changes require an uncut rectangle. Fused
sheets resize together, and cuts on their shared work surface distribute retained
geometry and pencil marks back to their original members.

Implied protoplanes is a persisted devtools setting, off by default. Hidden
candidates remain as internal frames for legacy attachments and room evaluation,
but cannot render, receive picks, or become swipe destinations. Explicit linear
attachments add bidirectional navigation portals even through a floor's interior;
fusion canonicalizes those portals and removes internal constituent navigation.

Reverse traversal immediately removes the active stroke's tail for Place,
Scissors and Light pencil. It never erases committed marks or jumps across a bend.
Three compact pointer reversals cancel an active Place stroke (650 ms window,
12 px minimum legs, 64 px envelope); cancellation consumes the rest of that
pointer contact and creates neither objects, charges, nor an undo record.
Physical device motion is not used. Legacy screen objects remain loadable and
editable, while new open structural placement produces actual walls/floors.

Regression coverage: `linear_placement_test.dart`,
`linear_placement_view_test.dart`, and `stroke_reversal_test.dart`.

## Unified eraser

The crafting toolbar keeps Eraser available in world and focus views. Both former icons already selected the same tool;
their gesture paths are now consolidated as well. `beginErasing` starts one
transaction, `eraseStroke` batches pencil marks and exposed graphite together,
and `finishErasing` records/saves once. Marks use separately projected samples
on the active paper plane, while graphite samples use the graphite plane.
Moving between paper and exposed graphite no longer cancels mark erasure.
Graphite collection retains its masks, covered-material protections, credits
and pop feedback; clearing pencil marks still does not refund graphite. Undo,
redo and cancellation restore both targets and exact balances together.

Devtools → Camera → Safe zone fill controls focused framing from 0.5 to 1.0,
persisted as `safeZoneFill` (default 1.0 for new and older settings). It scales
both usable width and height around the measured safe-zone center. At full
focus, 1.0 fits the plane to the safe-zone boundary on its limiting axis; 0.5
shows it at half that width and height, without changing orientation or
stretching the geometry. Changes retarget the existing smooth focus transition
immediately and remain effective across resizing, panel docking and plane
changes. Semi-focus retains its context/distance constraints, scaled by the
same factor. Camera framing does not enter gameplay history or change geometry.

### Focus context volume

Devtools → Focus context groups the context radius and opacity with a six-plane
crop box and Hide orthogonal geometry. New settings default to two surrounding
tile rings, 35% context opacity, two tile widths of X/Z crop padding, 1.25 tile
widths above the focused surface, and 0.25 below. Crop is enabled and orientation
filtering is disabled. Existing explicitly saved radius/opacity choices survive.
All controls update live and use the normal settings Save/Reload adapter.

The crop box follows the focused surface's world-space bounds. X/Z padding
expands its horizontal footprint; Above/Below extend its vertical range. A wall's
full vertical extent is included before padding. Cropping is presentation-only:
faces crossing any of the six planes are clipped without deleting objects,
changing collision/support geometry, creating history entries, or charging paper.
The active surface and its aligned owner remain intact. Cropped sections do not
add cap geometry. Atlas sprites are clipped in screen space after the world-space
polygon has been clipped, preserving paper grain, transparent cutouts, and pencil
marks without rebaking the atlas. Fully contained sprites retain their existing
unclipped batching path. Other meshes and debug wireframes share the world-space
face clipper.

A surface is classified as a floor if its normal is within 15° of vertical in
either direction; every other orientation is classified as a wall, including
slopes. The orientation filter keeps the focused category and hides the other
category, including a supporting floor when focusing a wall protoplane. Upright
screen panels are classified as walls even though their source drawing plane is
horizontal. Classification follows surface orientation rather than object names
or individual side faces of a solid. At exact overhead focus, vertical wall faces
are edge-on; their physical thickness/top edges remain visible. Orbiting toward
semi-focus reveals their faces.

Freestanding walls drawn on landscape paper use the base of their world-space
outline as their context level, rather than their face midpoint. This keeps them
visible from their ground surface and keeps the ground visible from the wall,
subject to crop/opacity/orientation controls. Context remains non-interactive;
exiting focus restores ordinary world rendering and wall cutaway behavior.

Validation includes six-plane crossings and boundary contact, inclination
classification, crop bounds for horizontal/vertical planes, settings migration
and invalid values, constructed and landscape-anchored walls, orientation
filtering in both directions, wall protoplanes, live crop changes, world-state
preservation, exit restoration, and raster checks that ordinary faces and atlas
sprites are cropped while atlas holes remain transparent.

### Floor swipe destinations

Two-finger and trackpad swipes from floor-oriented planes select only adjacent
floor-oriented surfaces, using the same 15° inclination classification as focus
context. Wall and sloped-surface folds remain in the topology/dependency graph
and retain their existing navigation when starting on those surfaces; they are
excluded from floor swipe destinations.

Landscape traversal uses four neighboring tile columns in the horizontal map,
independent of elevation. Each destination is the highest exposed layer with
remaining geometry in that column. Partial paper, including an isolated interior
scrap, is reachable; fully depleted columns, diagonals, and tiles beyond a gap
are not. The direction portal is projected at the source tile's height, so a
large height difference does not distort the intended screen direction. One
swipe still makes one step, retains per-plane drafts, and uses the normal focus
camera transition. There is no fallback through unrelated source layers.

Swipe exits are cached separately from structural adjacency during navigation
graph construction. The per-gesture direction query remains local to the active
surface's exits. Harvesting, construction, undo, and redo rebuild these derived
exits through the existing invalidation path. Regression tests cover height
changes in either direction, exposed-layer fallback after depletion, partial
geometry, empty gaps, floor/wall/slope filtering, and touch/trackpad integration.


### Baked landscape-paper folds

Natural white-paper terrain uses a seamless faceted-fold height study with broad
waves. `tool/generate_crumpled_paper.py` deterministically creates a 512×512
RGBA fold map containing two signed slopes and an eight-direction horizon
occlusion approximation. Its four-world-unit period is seamless, including the
height derivatives; it costs 1 MiB decoded and is shared across worlds. Python,
NumPy, SciPy and Pillow are offline authoring tools only.

A small fragment shader evaluates fixed diffuse lighting and cavity shading
when `HarvestMeshCache` bakes white-paper atlas slots. Camera rendering keeps
using the ordinary atlas image: no procedural noise, lighting, or shadow shader
runs during camera movement. World coordinates and a stable seed phase preserve
the fold pattern across tile boundaries, cuts and saves. Retained-paper masks
clip folds from holes. Graphite, cork, and placed/crafted paper do not receive
this texture. This is cosmetic bump relief with fixed baked lighting; geometry,
cut paths, marks, and navigation remain planar.

Devtools → Style → Landscape folds exposes Fold strength (0–2), Fold scale
(.25–4, larger values mean larger folds), and Baked shadow intensity (0–2).
All default to 1, including migration of old settings. Like existing texture
controls, these are staged until Update; fold-only updates invalidate white
terrain slots only. Strength 0 restores the previous smooth terrain appearance.
The existing surface appearance/fade filters apply after baking. Shadows are
intrinsic fold cavities, not dynamic object shadows; cut-edge and placed-paper
edge shading remain separate.

Tests cover pixel differences, shadow and scale controls, transparent cutouts,
material isolation, settings migration, narrow Devtools layouts, and unchanged
atlas identity/bake counters during repeated camera-style cache access.


Fold density (0–1, default .65) controls how much of natural paper receives fold
relief. Broad pockets uses a smooth world-space coverage field at .7 cycles per
world unit; Scattered patches uses 2.4. Both blend two deterministic noise scales
and soften transitions, reducing normals and cavity shading together. Density 0
is smooth and 1 reproduces the full uniform folds. Fold scale changes individual
fold size independently of pocket coverage. The two distribution choices and
slider are staged until Update and persisted with the other landscape settings.
The mask is evaluated only during atlas baking, adds no texture allocations,
and remains fixed through camera motion, cuts, and reloads. Tests compare pixel
coverage at multiple densities, both styles, exact repeat bakes, material masks,
and unchanged cache counters across 120 camera-style refreshes.

### Adjacent grid indicators

Floor and landscape crafting focus shows the first grid of each floor-swipe
destination as small, subdued dots. These are navigation context only: they do
not receive input, draw connection paths, or display another plane's draft.
The active crafting grid retains its existing larger dots and line effects.

Indicators follow the neighboring surface's height and are limited to the
navigation graph's available regions, excluding holes, depleted paper, and
areas covered by floor/wall geometry. Duplicate target planes and coincident
screen dots are drawn once. They use the visible mesh's context opacity and crop
box, fade in with focus, and are omitted in world mode, wall focus, and 3D preview.
The same passive overlay remains available while erasing. Geometry and navigation
snapshots remain independent of presentation; indicators do not change state,
accounting, drafts, or history.
