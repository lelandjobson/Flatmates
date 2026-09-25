# Flatmates

## Geometry

When a geometry operation is unclear — intersections, offsets, buffers, polygons, or numerical robustness — read the Boost.Geometry sources before inventing a new approach:

`/Users/lelandjobson/Documents/GitHub/boost/libs/geometry`

Cartesian segment and line intersection is `include/boost/geometry/strategies/cartesian/intersection.hpp` (`cartesian_segments`, Cramer's rule). Use that as the reference. This Flutter project does not take a Boost dependency; port the idea into Dart.
