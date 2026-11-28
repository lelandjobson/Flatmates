# Surface-driven construction

This revision replaces ground paper placement and inflation with a single closed Volume stroke. A fresh world starts with four landscape pips. A room costs 16 building units per square unit, and its first successful loop unlocks the rest of the world. Open strokes fade without committing. Landscape geometry is invisible; its actual grid nodes and edges still control drawing, support and ownership.

## Tools and surfaces

- Landscape: Volume.
- Interior floor: Pencil and Paper.
- Walls: Pencil, Scissors and Fold.
- Cloth sheets: Fold.
- Blankets and completed door leaves: selection and inspection.

Pencil regions remain reusable. Paper places indoor cloth; Fold produces a blanket. Scissors can trace a closed opening or three sides of a floor-touching rectangle, leaving a vertical hinge. A hinged flap remains closed until Fold opens it toward the edited side. Obstructed swings are rejected. Shared wall cuts and folds update both adjoining rooms in one undo action. Connected rooms can provide a resident's route to outdoors.

## Camera and presentation

The current room is framed in straight-down perspective using the window's usable dimensions. Ordinary dragging does not leave this view floating between rooms. Two-finger swipes move to an adjacent room in the opposite direction of the gesture: swipe left to move right. Pinch moves once per gesture between fitted room, neighborhood and parcel-overview levels. These room gestures are limited to the normal overhead presentation.

Faces and Objects selection use the crafting marquee convention: left-to-right containment and right-to-left crossing. Selecting or activating a tool pins its surface. Focus stores a parent camera and selection context. Parallel oriented faces use face-on framing; differently oriented selections use isolated inspection. Back, background double-tap and zoom beyond the entry threshold pop one focus frame.

The background retains a three-stop gradient, with deep teal, indigo and purple defaults. The horizon haze follows the top color. Devtools' appearance controls include Bottom, Middle, Top and Background darkness; darkness affects the gradient and haze together. White construction paper retains its brightness.

## Implementation and persistence

- `surface_policy.dart`: tool capabilities.
- `surface_construction_controller.dart`: authoritative grids, direct room strokes, wall cuts and folds.
- `architecture.dart`: collinear shared boundary intervals. Ambiguous old seams retain independent panels.
- `protoplane_surface_view.dart`: selection, nested focus and direct gestures.
- `protoplane_room_camera.dart`: fitted room framing and discrete navigation.
- World version 13 stores opening progression, room names/colors and opening hinge/door state. Shared wall associations derive deterministically from persisted room boundaries. Legacy objects and drawings retain their original representations.
- Housing reviews and grid/selection paths are cached; camera changes do not rebuild housing geometry.

## Validation commands

Run focused regressions:

```sh
flutter test test/protoplane/surface_construction_test.dart test/protoplane/surface_rules_test.dart test/protoplane/surface_view_test.dart test/protoplane/room_camera_test.dart test/protoplane/housing_test.dart test/protoplane/housing_rules_test.dart test/protoplane/background_texture_settings_test.dart
```

Native desktop profile:

```sh
flutter run -d macos --profile -t tool/construction_profile.dart --dart-define=ROOMS=4
```

The profile includes world navigation, marquee selection, room isolation, wall focus and door folding. It writes `/tmp/surface-profile-4.json`. Desktop timings do not establish mobile performance; mobile needs a separate device profile.

### Desktop measurements

Development profile snapshots are saved in `docs/benchmarks/`. The four-room baseline world frame median was 4.708 ms; the latest measured surface-construction run was 4.315 ms. Construction evaluation/commit median was 10.914 ms after caching room panels, surfaces, triangulations and sweep obstacles. The combined door-fold/undo input p95 fell from about 100 ms during development to 35.670 ms. These runs use different presentations and are not a controlled renderer-only comparison; timings include local machine scheduling and do not predict mobile performance.

For an interactive, unsaved four-room preview, add `--dart-define=PREVIEW=true` to the profile command. No benchmark input is generated in preview mode.
