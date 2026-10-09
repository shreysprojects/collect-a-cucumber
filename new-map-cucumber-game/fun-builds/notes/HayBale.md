# HayBale - functional behaviour (2026-09-24, package GardenLife)

File: `src/behaviours/server/HayBale.lua` -> `ServerStorage.FunBehaviours.HayBale`. **Server only.** There is no
client half: `ctx:Seat` handles the prompt and the sitting pose. The HayBale is x1.3.

## What it does
`B.Keys = {"HayBale_B", "HayBale_C"}`, so the Round Bale (HayBale_A) runs nothing.
* **HayBale_B Square Bale**: one `ctx:Seat` named `HaySeat`, prompt **"Sit"**, distance 8, anyone may use it.
  - Its top face is on the straw at authored (0, 1.40, 0.10): the middle of the long side, 2.6 x 1.4 x 1.4 bale.
  - It faces the build's front (-Z), so the legs hang over the front face.
* **HayBale_C Hay Stack**: one seat on the **top** bale.
  - The top bale lies crossways at x 6.60, z -0.50, with its top at y 2.80. It overhangs the front bale.
  - The seat is at authored (6.60, 2.80, -1.00), near the front end of that bale, facing front. The knees clear the
    end and the legs dangle in front of the stack.
* Checked offline: the seat's top face lands at authored y 1.400 / 2.800 and its LookVector = the build's front.

## Relies on
The authored bale geometry from the Blender source (`props/build_hay_bale.py`: C3 = (x+0.20, Blender y 0.50,
z 3*0.70)), mapped with `Kit.CFrameToWorld`. No pivot attributes are needed.

## How to test
Place HayBale_B and HayBale_C, walk up and use the "Sit" prompt. On C the avatar sits on top of the stack facing
out. Seats: `workspace.FunBuildRuntime.<HayBale_B_...>.HaySeat`. HayBale_A has no prompt.

## Known limits
One seat per bale. The square bale is 3.4 studs long in game, too short for two avatars side by side.
