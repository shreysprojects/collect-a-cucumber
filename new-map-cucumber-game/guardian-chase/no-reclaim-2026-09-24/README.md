# Guardian catch: the cucumber stays where it fell (2026-09-24)

User: "make it so when hit by guardian and u have a cucumber, cucumber just drops but the guardian doesn't take it
back or put it back where it originally was."

## What changed (ServerScriptService.GuardianService, 4 surgical hunks in `stage/patches.json`)
- The catch already dropped the cucumber at the player's feet (CucumberCarryAPI.DropAtFeet, 2026-09-17). What could
  still bring it back was the DECOY rule: a carry that clears near a Chasing / Waking / LURKING guardian makes it
  go for the nearest field cucumber, take it home and re-plant it at its seat (PlantAtSeat) - and a catch near the
  seat put the guardian back to Lurking within a second of its own drop.
- Now the catch stamps the dropped holder `GuardianDropped = true` and remembers `entry.CaughtDropAt`; `OnCarryCleared`
  ignores a carry-clear within 1.5 s of that guardian's catch, and its decoy scan skips any `GuardianDropped` holder.
  The guardian goes home empty-handed and never comes back for it. A cucumber the player DROPS on purpose (the
  "Tap DROP to shake the guardian off!" mechanic) is still a decoy: a fresh holder without the mark.
- Header comment updated to match.

## Verified (solo playtest, test profile, 2026-09-24)
Server sampler (0.25 s): lift started at the Spawn field centre (CarryDev collect/win) -> Strawman Waking 0.5 s,
Chasing 0.8 s, "caught them" + Returning 1.5 s with one GuardianDropped holder at the player's spot (1074, -228, 127),
Lurking from 2.8 s; for the remaining 13 s the holder never moved, the guardian never carried anything
(no GuardianCarry weld) and never entered Reclaiming.

Backup: `backups/NewMap_GuardianService_before-no-reclaim_2026-09-24.rbxm`. Mirror: `orig/`, result: `patched/`.
Not saved / published by me.
