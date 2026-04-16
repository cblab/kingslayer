# RULES_v1.md

## Purpose

This file defines the **hard gameplay rules of the current live prototype**.

These rules are binding for implementation work.

This file is intentionally narrow.
It describes what currently exists and what must not be broken.

It does **not** describe all future plans.

---

## Prototype scope

The current prototype is a small real-time top-down/isometric combat simulation built around:

- a player-controlled unit
- free knights
- rulers
- royal guards
- click-to-move
- melee combat
- ruler succession on ruler death
- guard disband on ruler death
- structured debug logging
- periodic free-knight spawning

---

## Active roles

The current live prototype has exactly **3** active roles:

1. `FREE_KNIGHT`
2. `RULER`
3. `ROYAL_GUARD`

No other gameplay role is part of the live ruleset.

In particular, `COMPANION` is **not** part of `v1`.

---

## Combat basics

- Units can move
- Units can attack valid enemies in melee
- Units use health and die when health reaches zero
- The player can click to move and click units to attack
- NPC combat behavior is driven by local aggro and role-specific logic

---

## Ruler death and succession

### Hard rule 1
Succession must trigger **only** when a unit dies as a true `RULER`.

A non-ruler death must never trigger a power transition.

### Hard rule 2
On ruler death, the killer may become the new ruler **only** if the killer is a valid successor under the current rules.

### Hard rule 3
A `ROYAL_GUARD` may **never** directly become ruler.

If a royal guard lands the killing blow, direct succession is blocked.

### Hard rule 4
A unit in disband cooldown may **never** become ruler.

---

## Guard collapse on ruler death

### Hard rule 5
When a ruler dies, that ruler’s escort collapses.

There is **no** direct escort rebind to the successor.

### Hard rule 6
Former guards become free knights.

They lose their ruler assignment.

### Hard rule 7
Former guards enter a disband cooldown.

During that cooldown they are temporarily inactive and cannot immediately re-enter normal combat behavior.

This is a core rule of the prototype.

---

## Disband cooldown

### Hard rule 8
Disband cooldown is a real behavioral lock.

During the cooldown, a former guard must not:

- roam normally
- chase targets normally
- fight normally
- become ruler
- behave as an active escort

### Hard rule 9
After the cooldown ends, the former guard is again a normal `FREE_KNIGHT`.

---

## Royal guard behavior

### Hard rule 10
Royal guards are bound to a living ruler.

### Hard rule 11
If a royal guard loses its valid ruler reference, it must collapse out of escort state and become free again.

### Hard rule 12
Royal guards prioritize ruler protection and return behavior over generic free roaming.

---

## Ruler behavior

### Hard rule 13
Non-player rulers may search/move autonomously.

### Hard rule 14
Ruler roaming is lightweight local behavior, not deep strategic AI.

### Hard rule 15
Rulers may attack enemies they detect under the current local combat logic.

---

## Free knight behavior

### Hard rule 16
Free knights are the generic unbound combat role.

### Hard rule 17
Spawned free knights are not implicitly attached to factions, crowns, rulers, or kingdoms by default.

---

## Periodic spawning

### Hard rule 18
Periodic spawning currently creates `FREE_KNIGHT` units only.

### Hard rule 19
Periodic spawning must not silently create new systems such as loot, escort reassignment, kingdom rebalance, or macro AI.

---

## Debugging and observability

### Hard rule 20
Structured logs for major state transitions are part of the prototype.

Important gameplay changes should preserve visibility into events such as:

- ruler death
- succession
- guard disband
- cooldown start/end
- combat target changes
- attacks
- ruler search movement
- periodic spawn

---

## Out of scope for v1

The following are explicitly **not** hard live systems in `v1`:

- companion role
- loot system
- item economy
- weapon tiers
- persistent kingdom institutions
- global macro simulation
- dynasty simulation
- multi-kingdom rule system
- guard rebuild system
- inventory system

These may appear in future design discussion, but they are not live `v1` rules.

---

## Rule precedence

If implementation details vary, preserve these invariants first.

If future design ideas conflict with these rules, `RULES_v1.md` wins for `v1`.