# RULES.md

This file defines the canonical gameplay rules for **Kingslayer**.

It is the source of truth for simulation behavior and gameplay invariants.
Not every rule here must already be fully implemented, but changes must not silently contradict it.

## 1. Core World Model

- The world contains **9 kingdoms**.
- Each kingdom always has:
  - **1 territory**
  - **1 crown**
  - **1 current ruler**
- A kingdom is never rulerless.
- A ruler starts with one kingdom but may later control **multiple crowns and kingdoms** through conquest.

## 2. Core Roles

There are four gameplay roles:

- `FREE_KNIGHT`
- `COMPANION`
- `ROYAL_GUARD`
- `RULER`

Women and men can occupy all four roles equally.
There is no separate gameplay logic by gender.

## 3. Core Conquest Rule

Kingslayer is built around **last-hit conquest**.

When a `RULER` dies:
- the actor responsible for the **last valid hit** determines succession
- there is **no power vacuum**
- succession is immediate

This is the core source of political change in the game.

## 4. Succession Rules

### 4.1 Valid succession trigger
Succession may only happen when the dying unit was truly a `RULER` at death time.

Implementation note:
- use `role_at_death`
- deaths of non-rulers must never trigger ruler succession

### 4.2 Last-hit rule
If a valid claimant delivers the final hit on a ruler, that claimant determines who receives:
- the crown
- the territory
- ruler status

### 4.3 Winner-takes-all ruler succession
If a ruler controls multiple kingdoms and is killed, the succession event transfers the conquered ruler’s holdings according to the last-hit rule.
The game is intentionally personal and fragile: a dominant ruler can still collapse through a single fatal mistake.

## 5. Loyalty Claim Rules

### 5.1 Royal guards
`ROYAL_GUARD` never claims a crown for itself.

If a `ROYAL_GUARD` lands the killing blow on an enemy ruler:
- the crown is claimed for that guard’s current `RULER`
- not for the guard itself

Royal guards are loyal agents, not independent claimants.

### 5.2 Companions
`COMPANION` behaves as the small-band analogue of `ROYAL_GUARD`.

If a `COMPANION` lands the killing blow on an enemy ruler:
- the crown is claimed for its current `FREE_KNIGHT` leader
- not for the companion itself

Companions fight for their leader, not for personal kingship.

## 6. Free Knights and Companions

A `FREE_KNIGHT`:
- may travel alone
- may attack other free knights, bands, rulers, and guards
- may recruit up to **2 companions**

A `COMPANION`:
- belongs only to a `FREE_KNIGHT`
- cannot exist without a valid free-knight leader
- does not grant ruler status
- acts as loyal support for its leader

## 7. Rulers and Royal Guards

A `RULER`:
- may not recruit companions
- may have up to **5 royal guards total**

A `ROYAL_GUARD`:
- protects its ruler
- fights for its ruler
- does not become ruler directly
- claims ruler kills for its ruler

## 8. Guard Capacity and Rebuild

Royal guard capacity is organized **per ruler**, not per kingdom.

This is a hard rule.

- each ruler has a **global maximum of 5 royal guards**
- this cap does **not** increase with additional conquered kingdoms
- guard rebuild refills only the ruler’s personal guard stack
- conquered kingdoms do **not** generate separate local royal-guard stacks

This is intentional.
Expansion increases territory and exposure, but not elite protection capacity.

## 9. Ruler Death and Guard Collapse

When a ruler dies:
- the old ruler is removed
- succession is resolved immediately
- the dead ruler’s guard structure breaks

Canonical rule:
- the old ruler’s guards do **not** remain attached to a dead or invalid ruler
- no stale ruler/guard binding may survive ruler death

If the implementation uses disband behavior:
- the dead ruler’s guards must disband cleanly
- they must not silently auto-rebind to the new ruler unless explicitly designed for that system version

## 10. Companion-to-Guard Transition

If a `FREE_KNIGHT` becomes a `RULER` through conquest:
- its current companions are converted into `ROYAL_GUARD`
- at most the existing companion cap applies immediately, meaning normally up to **2**
- additional royal guards, up to the ruler cap of 5, must rebuild over time

This creates an intended vulnerability window after conquest.

## 11. Rebuild Rule

Royal guards do not respawn instantly.

- dead royal guards are gone
- missing royal guards rebuild only over **time**
- time is the only rebuild resource
- rebuild is gradual, not instantaneous

There is no gold, food, dynasty, or population simulation behind guard rebuild.

## 12. Spawn Rule

New knights enter the world mainly through **spawn**.

- spawn is the main population source
- the world should not depend on family or dynasty simulation
- spawn placement must avoid unfair or absurd immediate ruler pressure where possible

## 13. Territory Bonus

A ruler gains a **5% defensive bonus** inside its own territory.

- this bonus applies only in territory the ruler controls
- this is a local territory advantage, not a global stat buff

## 14. Combat Model

Combat is exclusively **melee**.

There are:
- no ranged weapons
- no projectiles
- no ranged kill-steals

Core combat loop:
- units move
- units enter melee
- hits deal damage
- units die at `HP <= 0`

## 15. Equipment and Loot

Equipment exists in four quality tiers:

- `NORMAL`
- `PLUS_1`
- `PLUS_2`
- `PLUS_3`

There is:
- no durability damage
- no junk-state system

### Loot rule
When a combat-capable unit dies:
- exactly **one** equipped item is dropped
- selection is random from the actually equipped items

Hard assumption:
- every combat-capable unit must carry at least **one lootable equipped item**

### No full loot
A kill never transfers full equipment.
Each kill yields only one loot item.

## 16. Progression

Kingslayer has two progression scales:

### Small progression
- kill free knights, bands, and other combatants
- improve equipment incrementally

### Large progression
- kill rulers
- gain crowns
- gain territories
- expand political control

## 17. Intended Empire Dynamics

The game is intentionally unstable at the top.

A dominant ruler may hold many kingdoms, but still has:
- only one body
- only one global royal-guard cap
- only finite reaction capacity

This is deliberate.
The game should allow late dominance, overextension, mistakes, collapse, and reversals.

## 18. Non-Negotiable Invariants

The following must never be broken silently:

1. Non-ruler deaths must not trigger ruler succession.
2. `ROYAL_GUARD` never claims kingship for itself.
3. `COMPANION` never claims kingship for itself.
4. A dead or invalid ruler must not retain active guards.
5. A kingdom must never remain without a ruler.
6. Guard capacity is global per ruler, not additive per kingdom.
7. Companion capacity is max 2 per free knight.
8. Royal guard capacity is max 5 per ruler.
9. Expansion must not automatically multiply elite protection.
10. Last-hit succession remains the canonical conquest rule.

## 19. Out of Scope Unless Explicitly Added

Do not silently add:
- dynasty systems
- children or inheritance trees
- diplomacy
- story or quests
- multiplayer
- complex economy simulation
- full population simulation
- abstract strategic auto-resolution systems

Kingslayer should stay grounded in readable, local, combat-driven conquest mechanics.