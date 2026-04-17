# AGENTS.md

## Purpose

This file tells coding agents how to work in this repository.

It does **not** define the game design in full.
It defines workflow, scope control, source-of-truth order, and implementation discipline.

---

## Source of truth

Use this order when making decisions:

1. The explicit user task in the current prompt
2. `RULES_v1.md`
3. `DESIGN.md`
4. The live codebase
5. `README.md`

If two sources conflict:

- `RULES_v1.md` beats `DESIGN.md`
- `DESIGN.md` beats `README.md`
- `README.md` is onboarding only and may lag behind the code
- Never reintroduce old architecture just because it appears in older docs

If there is tension between docs and code, preserve the current hard rules and make the smallest change that satisfies the task.

---

## Current project reality

This prototype is currently **actor-centric**, not manager-centric.

The main live gameplay logic is concentrated in:

- `scripts/world.gd`
- `scripts/units/unit.gd`

Do **not** create new manager systems, kingdom systems, loot frameworks, or deep abstractions unless the user explicitly asks for them.

Do **not** revive placeholder architecture from older project ideas unless the current task explicitly requires it.

---

## Working style

- Make the smallest viable change that solves the task
- Prefer patching existing logic over introducing new systems
- Preserve working behavior unless the task explicitly changes it
- Keep logic local and readable
- Avoid speculative refactors
- Avoid architecture expansion
- Avoid “preparing for the future” unless the user asked for that directly

---

## Scope discipline

Unless explicitly requested, do **not** add:

- new managers
- new scenes
- new UI systems
- new camera systems
- new save/load systems
- loot systems
- inventory systems
- kingdom simulation layers
- large refactors
- broad renames
- new frameworks

If a task can be completed inside an existing file, do it there.

---

## Gameplay-rule discipline

`RULES_v1.md` contains the hard gameplay invariants for the current prototype.

Treat those rules as binding.

`DESIGN.md` contains target-state ideas and future mechanics.
Do **not** silently implement design ideas from `DESIGN.md` unless the task explicitly asks for them.

Example:
- If `DESIGN.md` mentions companions, multi-kingdom rulers, or loot, that does **not** mean those systems already exist
- Do not write code as if planned systems are already live

---

## File discipline

When possible:

- `scripts/world.gd` owns world-level coordination
- `scripts/units/unit.gd` owns unit behavior
- scenes should stay simple
- avoid spreading one small mechanic across many files

Before adding a new file, ask:
1. Is this required?
2. Can the change stay inside the existing prototype structure?
3. Will a new file make Codex more or less likely to drift?

Default answer: keep it in the existing files.

---

## Allowed change pattern

Preferred order:

1. inspect the relevant existing file(s)
2. identify the smallest stable patch point
3. change only what is required
4. preserve existing logs and debugging signals where practical
5. summarize exactly what changed

---

## Logging and debugging

Do not remove useful structured debug logs unless the task explicitly asks for cleanup.

If you add new behavior that affects combat, succession, roaming, guards, cooldowns, or spawning, preserve observability.

---

## Rules for ambiguity

If the task is ambiguous:

- do not invent a large system
- do not fill gaps with speculative architecture
- choose the smallest interpretation consistent with `RULES_v1.md`
- keep future-facing ideas in `DESIGN.md`, not in live code

---

## Out of scope by default

The following are not assumed to exist unless explicitly implemented in code and requested in the task:

- companion role
- full kingdom layer
- loot/equipment economy
- weapon rarity systems
- persistent dynasties
- macro strategy systems
- deep AI planners

---

## GDScript typing rules

- Use explicit static types for all new or modified GDScript variables, parameters, returns, arrays, and dictionaries.
- Do not use `:=` when the expression could infer `Variant`.
- Prefer:
  - `var x: int = ...`
  - `var ok: bool = ...`
  - `var pos: Vector2 = ...`
  - `var cells: Array[Vector2i] = []`
  - `var anchors: Dictionary[String, Vector2] = {}`
- Use integer division `//` for grid math.
- Avoid mixed int/float expressions in tile and cell calculations.
- If a value may be ambiguous, cast explicitly with `int()`, `float()`, or `bool()`.
- Treat Godot parser warnings about type inference as real errors and fix them immediately.

---

## Success criterion

A good change in this repo is:

- small
- local
- reversible
- rule-consistent
- easy to inspect
- hard to misinterpret later