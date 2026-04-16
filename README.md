# Kingslayer

A small Godot 4 top-down / isometric melee prototype focused on local combat, ruler death, guard collapse, and emergent power transitions.

This repository is intentionally compact.
The active prototype currently lives mainly in:

- `scripts/world.gd`
- `scripts/units/unit.gd`
- `scenes/World.tscn`
- `scenes/units/Unit.tscn`

---

## Current prototype

The current playable prototype includes:

- player-controlled click-to-move melee
- NPC melee combat
- three live roles:
  - `FREE_KNIGHT`
  - `RULER`
  - `ROYAL_GUARD`
- ruler succession on true ruler death
- escort collapse on ruler death
- disband cooldown for former guards
- lightweight ruler roaming / search movement
- structured debug event logging
- periodic spawning of free knights

This is a prototype for systemic behavior, not a finished game.

---

## Document map

Use these files in this order:

### `AGENTS.md`
How coding agents should work in this repo.

Contains:
- workflow rules
- scope control
- source-of-truth order
- implementation discipline

### `RULES_v1.md`
Hard gameplay rules for the current live prototype.

Contains:
- current binding mechanics
- non-negotiable gameplay invariants
- current prototype scope

### `DESIGN.md`
Future-facing design direction.

Contains:
- target mechanics
- planned systems
- open design questions

Important:
`DESIGN.md` is **not** the hard source of truth for the current build.

---

## Source of truth

When docs disagree, use this order:

1. explicit task
2. `RULES_v1.md`
3. `DESIGN.md`
4. live code
5. `README.md`

`README.md` is onboarding only.

---

## Repository focus

The repo currently favors a small actor-centric prototype architecture.

That means:

- world-level coordination stays local
- unit behavior stays local
- large manager hierarchies are not the default
- new systems should be introduced only when they are actually needed

---

## Project goals

The near-term goal is not content breadth.

The near-term goal is:

- stable local combat
- stable ruler death handling
- stable escort collapse
- readable emergent dynamics
- low architectural drift
- good debugging visibility

---

## Non-goals for the current stage

These are not assumed to be live systems unless explicitly implemented:

- companion role
- full kingdom simulation
- loot economy
- inventory systems
- dynasty systems
- large strategy layers
- manager-heavy architecture

---

## Running the project

Open the project in Godot 4 and run the main scene.

If additional setup details become necessary, add them here.
But keep this README short and operational.