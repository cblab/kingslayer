# DESIGN.md

## Purpose

This file describes the intended design direction beyond the current live prototype.

It is a planning document.

It is **not** the hard source of truth for the current build.
If this file conflicts with `RULES_v1.md`, then `RULES_v1.md` wins.

To reduce confusion, each section carries a status:

- `implemented`
- `next`
- `planned`
- `open`

---

## 1. Core design philosophy
**Status: implemented**

Kingslayer should remain:

- systemic
- readable
- local-first
- mechanically legible
- small in architecture
- rich in emergent outcomes

The design should favor:

- direct causal rules
- actor-level state changes
- visible collapse and power transfer
- minimal hidden systems

The design should avoid:

- premature manager-heavy architecture
- abstract simulation layers without gameplay payoff
- hidden institution logic that obscures causality

---

## 2. Current prototype direction
**Status: implemented**

The current prototype is centered on:

- a player-controlled melee unit
- rulers
- royal guards
- free knights
- local aggro
- succession on ruler death
- guard collapse on ruler death
- periodic free-knight injection
- structured debug logs for reading system behavior

This is the valid base to build from.

---

## 3. Future role model
**Status: planned**

Target long-term role set:

1. Free Knight
2. Companion
3. Royal Guard
4. Ruler

Meaning:

- **Free Knight**: independent unit
- **Companion**: follows a free knight / small band leader
- **Royal Guard**: elite ruler-bound escort
- **Ruler**: sovereign combat unit tied to crowns/territory

Important:
This 4-role structure is **not** yet live in the codebase.

---

## 4. Companion concept
**Status: planned**

Companions are intended as the small-band analogue of royal guards.

Design intent:

- a free knight may gather a small personal band
- companions follow and fight for that leader
- they are more personal and lower-scale than royal guards
- they are not yet a live prototype feature

Potential future behavior:

- companions claim combat allegiance through their current leader
- if their leader rises into rulership, companions may convert upward into ruler-bound guards
- the small band should stay legible and limited, not become a full army system

---

## 5. Multi-kingdom ruler model
**Status: planned**

The intended direction is that a ruler starts with one kingdom but may later hold multiple kingdoms.

This makes the system more personal than institutional.

Desired consequence:

- empires are tied to the survival and competence of a ruler
- a bad loss can unwind a large domain quickly
- snowballing exists, but remains fragile

This is a design target, not current live logic.

---

## 6. Guard cap model
**Status: planned**

Future target:

- royal guard capacity is **global per ruler**
- not per kingdom
- default target cap: max 5 royal guards per ruler

Reason:

- avoid infinite escort scaling
- create imperial overstretch
- make conquest increase exposure instead of only increasing strength
- keep ruler-centered power readable

Important:
This is **not** yet the enforced live model in code.

---

## 7. Ascension conversion
**Status: planned**

If a free knight with companions becomes ruler, the intended direction is:

- current companions convert upward into royal guards
- only within the small cap system
- the rest of the ruler’s future guard strength rebuilds over time rather than appearing instantly

This preserves continuity while preventing instant full-army jumps.

This system is not yet implemented.

---

## 8. Guard rebuild over time
**Status: open**

Future likely direction:

- rulers should not instantly regenerate full escort strength
- guard strength should rebuild over time under explicit rules
- rebuild should remain simple and visible
- no hidden macro economy should be required for the first version of this feature

Open design question:
- what exact trigger creates new guards
- timer-based, territory-based, or location-based rebuild
- whether rebuild happens globally or at designated spawn points

---

## 9. Loot and equipment
**Status: planned**

Future design may include lightweight equipment and loot.

Direction:

- dead units may drop equipment
- equipment should stay mechanically simple
- readable combat consequences matter more than item complexity

This must remain subordinate to core simulation clarity.

No full inventory-heavy RPG layer is desired in the current direction.

---

## 10. Kingdom abstraction
**Status: open**

There is a future design interest in crowns, territories, and kingdom continuity.

But the project should be careful here.

The system should not jump too early into a deep kingdom-management architecture.

Preferred sequence:

1. stabilize actor-level combat and succession
2. stabilize escort collapse and rebuild
3. add companion layer
4. only then consider more explicit crown/territory logic

Reason:
institutional logic before stable actor logic will hide bugs and blur causality.

---

## 11. Architecture direction
**Status: implemented / planned**

Current preferred architecture direction:

- keep the prototype actor-centric
- let `world.gd` coordinate world-level transitions
- let `unit.gd` hold unit behavior
- add new files only when a system is clearly real and mature

Future extraction into separate systems is acceptable only when a mechanic becomes both:

- stable
- large enough to justify separation

Do not extract systems early just for aesthetics.

---

## 12. Design guardrails
**Status: implemented**

Even as the project grows, keep these guardrails:

- no architecture bloat
- no fake complexity
- no hidden macro layers without gameplay payoff
- preserve direct causality
- prefer visible state transitions
- preserve strong debug visibility
- keep the simulation inspectable

---

## 13. What this file is not
**Status: implemented**

This file is not permission to implement everything listed here.

It is a design map.

Implementation still requires:
- an explicit task
- compliance with `RULES_v1.md`
- respect for current prototype scope