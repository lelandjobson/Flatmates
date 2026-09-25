---
name: boost-geometry
description: >-
  Use Boost.Geometry as the reference for intersection, offset, buffer, and
  polygon operations. Use when implementing or debugging geometry, curves,
  cuts, safe zones, or when the user mentions Boost.
---

# Boost.Geometry reference

The Boost tree lives at `/Users/lelandjobson/Documents/GitHub/boost`. Geometry is under `libs/geometry`.

Before writing a new intersection, buffer, or robustness fix:

1. Search that tree for the operation (start with `include/boost/geometry/strategies/cartesian/intersection.hpp` for line and segment hits).
2. Follow the Boost approach in Dart. Do not add Boost as a package dependency.
3. Cartesian line hits use Cramer's rule: parameter `t` is 0 at the first point and 1 at the second. Parallel lines have a zero denominator. A hit on a finite segment keeps `t` in `[0, 1]`; a ray may fall outside that range when a cut is extended.
