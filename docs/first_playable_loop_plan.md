# First playable loop: paper homes, residents, and rent

Status: saved implementation plan. This document describes intended work, not completed functionality.

## Summary

Build a complete loop: **draw a boundary → place building paper → inflate a room → cut a door → place indoor cloth → inflate a blanket → welcome friends → collect rent → expand.**

Building paper is **outdoor-only**; cloth is **indoor-only**. Eligibility follows the physical surface, independently of camera focus.

## Construction, materials, and focus

- Keep Pencil, Paper, and Inflate; add Scissors. Preserve centered targeting, ghost previews, yellow valid-target highlighting, and navigation outside Pencil.
- Ground building boundaries must enclose at least **1 square tile**, using tile-corner nodes.
- Building mats inflate into hollow, **one-unit-high rooms** with floors, roofs, and thin walls. Preserve footprint holes.
- Introduce explicit room objects with persisted openings and stable interior/exterior surface identities. Derive rendering, collision, drawing surfaces, and navigation from this shared geometry.
- Interior surfaces use the quarter-unit drawing grid. Cloth sheets inflate to **0.05-unit** blankets.
- Add material eligibility metadata supporting **indoor-only, outdoor-only, or both**. Building paper is outdoor-only; cloth is indoor-only. Do not add more materials yet.
- Resolve context from the actual target:
  - Interior floors, inward-facing walls, and ceilings are indoor.
  - Exterior ground, outward-facing walls, and roof tops are outdoor.
  - Attached paper layers inherit their supporting surface’s context.
  - Courtyards and footprint holes remain outdoor; door/window cuts and visual cutaways do not reclassify a room’s interior.
- Validate eligibility across the entire placement boundary. Reject placements spanning incompatible contexts rather than clipping them.
- Apply the same eligibility checks to previews, placement, and inflation, with fresh validation before committing. Invalid targets show neither fill nor ghost, consume nothing, and preserve tool/material selection.
- Keep the looping five-slot material picker stable; do not automatically switch materials as the reticle moves. Invalid placement attempts show concise errors such as “Building paper requires an outdoor surface.”
- Clicking a building with no tool selected enters room focus. Animate surrounding context away, hide the roof and camera-facing walls, and retain navigation. Only Pencil locks the camera.
- A compact exit control restores context and the pre-focus camera pose. Hidden faces cannot intercept targeting.
- Scissors previews and removes a closed drawn region from one wall:
  - A floor-touching cut at least **0.25 wide × 0.5 high** becomes a doorway.
  - A fully enclosed cut becomes a window opening.
  - Other valid cuts remain undesignated openings.
- Reject cuts that remove an entire wall, intersect existing openings, or invalidate attached-object support. Cutting is free and returns no salvage.

## Residents and manual time

- A small blanket must contain a grid-aligned **0.25 × 0.5** rectangle, allowing rotation. A large blanket must contain a **0.5 × 0.5** square. Smaller cloth remains decorative.
- Each qualifying blanket on an interior floor supports one Cube Boy when a traversable route connects an exterior doorway to it. Wall and ceiling cloth does not create sleeping places.
- Spawn a resident immediately when a new sleeping place qualifies. Persist identity, assigned blanket, rating, and occupancy history.
- Reuse character rendering and movement components for wandering within reachable room space and resting near blankets. Animation never advances gameplay time.
- Show entity names on hover, including small/large blanket designations. Compact resident inspection shows rating, rent, and rating contributions.
- Initial rating rules, capped at 100:
  - **40** for a usable sleeping place.
  - **+20** for a large blanket.
  - **+20** for a room window.
  - **+20** for at least **0.5 square units of accessible floor per resident**, excluding blanket footprints.
- Add a top HUD with day, phase, currency, and an advance control. Start at **Day 1 — Morning** and progress **Morning → Afternoon → Evening → next Morning**.
- Building is unlimited within each phase. Lighting follows the phase; elapsed real time never advances it.
- Overnight, atomically evaluate housing, pay eligible residents’ rent, resolve departures, advance the day, and save:
  - Rent: **4 + floor(rating / 20)** coins.
  - Departure probability below rating 60: **(60 − rating) / 100**.
  - No departure risk at rating 60 or above.
- A resident whose sleeping place becomes unusable remains until overnight, receives no rent, and leaves then. Repairs before overnight preserve the tenancy.
- After departure, replacement requires a usable vacancy with a higher rating than the departed resident had. Track this vacancy on the room so recreating the blanket cannot bypass the requirement.
- Show concise overnight income and arrival/departure results without instructional prose.

## Economy, architecture, and compatibility

- Paper inventory uses **16 units per square tile**. Placement consumes `ceil(area × 16)`, excluding holes; inflation is free.
- New games start empty with **32 building-paper units, 8 cloth units, and 0 coins**.
- Provide compact purchases beside the selected material: **16 building units for 20 coins**, or **16 cloth units for 12 coins**. Purchasing is allowed regardless of the current target context.
- With no residents and fewer than 12 coins, an emergency-supplies action tops inventory up to **16 building units and 8 cloth units**, without granting money or accumulating surplus.
- Charge parcel purchases to the new wallet using their existing displayed price.
- Reuse historical bedroom access/comfort logic, persistent resident assignments, movement, manual time HUD, and wall-cutaway behavior. Adapt them to the current construction world model rather than restoring parallel world stores.
- Reuse existing planar clipping and extrusion operations for room panels and openings.
- Extend resolved construction targets with physical context and room association. Centralize material eligibility and gameplay balance rules.
- Persist rooms/openings, residents/vacancies, day/phase, wallet, and deterministic departure state in the next save version.
- Preserve older objects and drawings unchanged. Legacy solid volumes stay solid; previously placed outdoor cloth or indoor building paper is not deleted. New placement and inflation must obey the new eligibility rules.
- Existing saves retain inventories and receive Day 1/Morning and zero currency.
- Construction, cutting, purchases, and immediate residency changes are atomic undoable actions. Each phase advance establishes an undo boundary. Saved overnight results prevent duplicated rent or rerolled departures.

## Validation and defaults

- Test the complete fresh-world loop through first rent, material purchase, and expansion.
- Verify indoor/outdoor eligibility on floors, both wall faces, ceilings, roofs, courtyards, and inherited layers. Focus and cutaway animations must never change eligibility.
- Verify invalid previews clear immediately, stale targets fail safely, and rejected actions consume no materials.
- Cover room shells, holes, cut classification, attachment support, interior grids, doorway access, blanket thresholds, shared rooms, crowding, and resident movement.
- Test rent, deterministic departures, improved-room replacements, emergency supplies, purchases, undo boundaries, and old/new save round trips.
- Verify mouse, touch, and trackpad navigation, focus transitions, Pencil locking, and accidental-placement prevention.
- Run relevant construction, geometry, drawing, navigation, resident, economy, persistence, and parcel tests plus Flutter analysis. Check desktop, portrait, and landscape layouts.

All numerical values are initial tuning defaults. Individual preferences, scheduled activities, hinged doors, window glass, and additional material types remain later additions.
