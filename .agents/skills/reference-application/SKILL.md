---
name: reference-application
description: >-
  Look up and port assets or old work from the sfapp reference application,
  the sibling repo of this project. Use when the user says reference
  application, reference app, sfapp, the old app, or asks to grab, match, or
  reuse something from that corpus.
---

# Reference application

**Reference application** means the `sfapp` repo:

`/Users/lelandjobson/Documents/GitHub/sfapp`

It sits next to this repo (`../sfapp` from the Flatmates root). Package name `sf_experiments`. It is a prototype corpus, not a package this app depends on.

Read `AGENTS.md` in that repo before searching. It is the map of views, rendering, crafting, geometry, and assets, and it has an **Extracting Components** section.

## Where to look

| Need | Start |
|---|---|
| A screen or interaction | `lib/views/`. Crafting workbench is `lib/views/crafting_test_view.dart` (`/crafting-test`). |
| A reusable widget | `lib/ui/` |
| Geometry | `lib/geometry/` |
| Rendering | `lib/rendering/` |
| Crafting rules | `lib/crafting/` |
| Images, blueprints, meshes | `assets/`, `assets/crafts/`, `assets/crafting_blueprints/`, `assets/models/` |

Search that tree by the user's words (tool name, view, widget, asset filename). Prefer the implementation the manifest names over a guess.

## Porting

1. Read the source. Copy only the part this task needs.
2. Put it in the matching Flatmates area and fix imports so it builds here. Do not add a dependency on `sfapp`.
3. Views are large prototypes. Recreate the behavior in the current screen. Do not paste a whole view file.
4. Geometry under `lib/geometry/` is pure Dart plus `vector_math` and can be copied more directly. Check what this repo already has first.
5. Assets: copy the file into this repo's `assets/` and declare it in `pubspec.yaml` if it is not already covered by a folder entry.
6. Do not edit `sfapp` unless the user asks for a change there.
