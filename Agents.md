# AGENTS.md

## Project
Kingslayer is a Godot 4 prototype for an isometric 2D top-down conquest game with click-to-move movement, melee combat, rulers, royal guards, territory control, loot, and winner-takes-all ruler succession.

## Tech constraints
- Engine: Godot 4
- Language: GDScript only
- No C#
- Keep all code Godot-4-conformant
- Do not use deprecated Godot 3 patterns unless explicitly requested
- Prefer small, readable scripts over overengineered abstractions

## Working style
- Make small, focused changes
- Respect the existing project structure
- Do not invent large new systems unless explicitly requested
- Do not rename existing nodes, scenes, or files without a strong reason
- Avoid scope creep
- Prefer direct implementation over long explanations
- Always preserve a playable state if possible

## Architecture rules
- Keep data, simulation, and presentation separated where practical
- Do not build a full ECS/framework unless explicitly requested
- Favor simple Godot scene composition and small scripts
- Only introduce managers/components when they clearly reduce complexity
- Avoid hardcoded `get_parent().get_node(...)` chains when signals or exported references are cleaner

## Scene and file discipline
- Change only the files needed for the requested task
- Do not patch `.tscn` files carelessly with duplicated node/property blocks
- Each node in `.tscn` files must have a clean, valid block
- Avoid duplicate property assignments like multiple `polygon =` lines in the same node unless intentionally overwriting and clearly correct
- Prefer replacing a broken scene cleanly over repeatedly layering patches on top of it

## Input and gameplay rules
- Click-to-move is the control model
- The game is top-down/isometric 2D
- Movement and collision must feel stable before adding combat
- Do not add combat, AI, loot, camera logic, or kingdom logic unless the task explicitly asks for it
- Pathfinding/navigation should be robust before building combat on top of it

## Navigation rules
- Use Godot 4 navigation APIs only
- Prefer clear, debuggable navigation setups
- Avoid fragmented navmeshes when a single connected navigation region with holes is more stable
- Respect the existing world geometry
- Do not invent arbitrary blocker geometry if the scene already contains it

## Code quality
- Keep scripts short and focused
- Use clear names
- Remove dead or redundant logic when replacing it
- Do not leave half-implemented alternative paths in the same script
- Prefer robust minimal solutions over ambitious fragile ones

## Output format for tasks
For each task, provide:
1. A short summary of what changed
2. Which files changed
3. What to test in Godot
4. Any known limitation that still remains

## Never do this unless explicitly asked
- Add story, quests, diplomacy, dynasty systems, children, or meta progression
- Add multiplayer
- Add advanced UI polish
- Add final art pipelines
- Add unnecessary debug visuals to final scenes
- Refactor unrelated systems

## Priority order
When in doubt, prioritize:
1. Playability
2. Stability
3. Simplicity
4. Readability
5. Extensibility
6. Visual polish