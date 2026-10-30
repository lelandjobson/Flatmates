# Flatmates

## Grid puzzles

Level, blueprint, blueprint piece, attachment, level permutation, collectible, and failure condition are defined in `docs/gridcraft.md`. Use those words in gridcraft code and in the puzzle editor.

## Geometry

When a geometry operation is unclear — intersections, offsets, buffers, polygons, or numerical robustness — read the Boost.Geometry sources before inventing a new approach:

`/Users/lelandjobson/Documents/GitHub/boost/libs/geometry`

Cartesian segment and line intersection is `include/boost/geometry/strategies/cartesian/intersection.hpp` (`cartesian_segments`, Cramer's rule). Use that as the reference. This Flutter project does not take a Boost dependency; port the idea into Dart.

## UI text

Do not add instructional or explanatory prose to the UI: no gesture instructions, tutorial hints, helper paragraphs, or superfluous feature explanations. Keep visible text limited to necessary control labels, status/data, and actionable errors. Explain feature behavior in documentation or conversation instead. Lay out status and debug overlays together so text wraps without overlapping controls or other text, in both 2D and 3D views.
