# Gridcraft language

Grid puzzles are authored in the puzzle editor and played in the grid puzzle view. Use these words in code, comments, and the editor.

A **level** is one blueprint step (`GridStep`). A **blueprint**, also called a **craft**, is the ordered list of levels (`GridBlueprint`). Both words mean that list. `CraftV1` and the 3D crafting blueprints are a different system.

A **blueprint piece** is one closed ring on a level. It is a separate part. A tool cannot cross its boundary. Paper may be cut along a penned edge, up to that edge, and onward only when the next collinear edge allows it. An open polyline is also a valid drawn shape: it is not joined back to its first point, and the blade still stops on it. A **paper piece** is a `PapercutPiece` on the runtime sheet. Do not call a paper piece a blueprint piece.

An **attachment** changes how a tool behaves. It is authored on the level. The player does not toggle it during play.

A **level permutation** changes the level’s environment or what the player can see and select. Darkness, mirror axes, and no-fold zones are permutations.

A **collectible** is an entity a tool must collect to pass the level. Color gems and number gems are collectibles. They are the entry points onto the paper: a new cut starts at a gem, and the blade can return to the paper only at one. A gem disappears when the blade takes it. Every gem must be taken before the level is cleared. The gem, piece, or other entity that causes a failure flashes red, then the level restarts.

A **failure condition** restores the level to its state before any moves: the sheet, cuts, folds, collectibles, tool-use counters, and rotation. The camera pan and zoom stay where they are.

Tools start with unlimited uses. A level may set a **tool filter** that lists the tools which are available and, optionally, how many uses each one has. Each tool defines what a use means. Scissors spend grid-unit length along the cut. The folder spends one use per fold or unfold. The hole punch spends one use per punch. Select and quarter-turn rotation do not spend uses.
