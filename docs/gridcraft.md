# Gridcraft language

Grid puzzles are authored in the puzzle editor and played in the grid puzzle view. Use these words in code, comments, and the editor.

A **level** is one blueprint step (`GridStep`). A **blueprint**, also called a **craft**, is the ordered list of levels (`GridBlueprint`). Both words mean that list. `CraftV1` and the 3D crafting blueprints are a different system. The puzzle editor groups blueprint files into puzzle-collection folders. A level is still a blueprint step.

In play, a **collection** is that folder, and a **puzzle** is one blueprint in the folder. Puzzles run in collection order: name, then id. The grid puzzle view opens both from two buttons. Finishing a puzzle slides the next one in from offscreen right, then drops the finished puzzle and puts the new one back at the coordinates it was authored with. Finishing the last puzzle shows the victory screen for the collection.

A **blueprint piece** is one closed ring on a level. It is a separate part. A tool cannot cross its boundary. Paper may be cut along a penned edge, up to that edge, and onward only when the next collinear edge allows it. An open polyline is also a valid drawn shape: it is not joined back to its first point, and the blade still stops on it. A **paper piece** is a `PapercutPiece` on the runtime sheet. Do not call a paper piece a blueprint piece.

An **attachment** changes how a tool behaves. It is authored on the level. The player does not toggle it during play.

A **level permutation** changes the level’s environment or what the player can see and select. Darkness, mirror axes, and no-fold zones are permutations.

A **collectible** is an entity a tool must collect to pass the level. Color gems and number gems are collectibles. Color gems are collected in groups: the first color opens that group, and taking another color before the group is finished fails the level. A cut can still start anywhere on the paper edge. Number gems are the entry points onto the paper: while one remains, a new cut starts at a number gem, and the blade can return to the paper only at one. A gem disappears when the blade takes it. Every gem must be taken before the level is cleared. The gem, piece, or other entity that causes a failure flashes red, then the level restarts.

A **failure condition** restores the level to its state before any moves: the sheet, cuts, folds, collectibles, tool-use counters, and rotation. The camera pan and zoom stay where they are.

Tools start with unlimited uses. A level may set a **tool filter** that lists the tools which are available and, optionally, how many uses each one has. Each tool defines what a use means. Scissors spend grid-unit length along the cut. The folder spends one use per fold or unfold. The hole punch spends one use per punch. Select and quarter-turn rotation do not spend uses.
