# DanceFloor (client-only behaviour)

The dance floor is part of the DJBooth package. Everything is in `notes/DJBooth.md`, under the "Dance floor" section.

**File:** `src/behaviours/client/DanceFloor.lua` installs as `ReplicatedStorage.FunBehavioursClient.DanceFloor`. It has no server half.

**What it relies on:**
* the 16 `Tile_r<row>_c<col>` Neon parts, plus `PowerLight`
* the `State_Dim` / `State_On` attributes
* DJBooth builds' `Fun_Playing` / `Fun_StartedAt` state
* the DJBooth client module's `Live` table (optional)

**Local GUI:** `PlayerGui.FunDanceGui`, bound to key G.
