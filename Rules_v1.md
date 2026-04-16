# RULES.md

## Canonical runtime rules

1. There are four gameplay roles:
   - FREE_KNIGHT
   - COMPANION
   - ROYAL_GUARD
   - RULER

2. Only the death of a true RULER may trigger ruler succession.
   - Use role_at_death semantics.
   - Non-ruler deaths must never trigger succession.

3. Kingslayer uses last-hit succession.
   - A valid final hit on a ruler immediately determines the new ruler.
   - There is no power vacuum.

4. ROYAL_GUARD never claims rulership for itself.
   - A royal guard claims ruler kills for its current ruler.

5. COMPANION never claims rulership for itself.
   - A companion claims ruler kills for its current leader.

6. A FREE_KNIGHT may have at most 2 companions.

7. A RULER may have at most 5 royal guards total.

8. Royal guard capacity is global per ruler, not additive per kingdom.

9. A dead or invalid ruler must not retain active guard bindings.

10. Do not silently introduce dynasty, diplomacy, economy, multiplayer, or story systems.