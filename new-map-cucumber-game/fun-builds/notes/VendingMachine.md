# VendingMachine: a working snack machine (2026-09-24)

It's free and cosmetic. It gives no Cash, no Strength and no boosts.

**Files**
* `FB\src\behaviours\server\VendingMachine.lua` → `ServerStorage.FunBehaviours.VendingMachine`
* `FB\src\behaviours\client\VendingMachine.lua` → `ReplicatedStorage.FunBehavioursClient.VendingMachine`
* Both use `B.Keys = {"VendingMachine"}`. The client sets `B.StepRange = 160`.
* Look-check tools only. None of these ship.
  * `FB\models\vend_pose.py`: sip-pose IK solve and renders.
  * `FB\models\vend_drop_preview.py`: drop strobe on the real prop.
  * `FB\models\build__VendSnacks.py`: hand-held snacks at 2×.
  * `FB\tools\vend_harness\`: an offline Luau run of both halves.

## What players see
1. **The prompt.** "Get a snack" (hold 0.3 s, 8 studs) sits at the keypad (`Pivot_KeypadCentre`). Anyone can use it.
2. **Cooldown.** Each player gets one snack every 8 s, shared across every machine. The server simply ignores extra presses. For the buyer only, the prompt then reads "Out of coins, wait a sec" (set locally, restored after 8 s).
3. **The snack.** The server picks Cucumber Soda (green can), Cola (red can) or Chips (yellow bag). It fires `Vend {Player, Snack, Seed, T0}` to all clients.
4. **The drop.** Every client replays it from `T0` (server time), so all clients stay in sync:

| t (s after T0) | What happens |
|---|---|
| 0.00 | Coin sound at `Pivot_CashSlot`. A keypad button blinks lime. |
| 0.16 | A second button blinks, with a Click. |
| 0.20 | A runtime copy of the stocked item appears over a stock slot of the **matching colour** (see "Geometry the client relies on"). It's 0.006 bigger, so it covers the stock item. The spiral pushes it to the glass, uncovering the "next" item behind it. |
| 0.55 | It tumbles down in front of the shelf lips and behind the glass (authored g = 48). Once inside the sill it moves over the chute and lies down, all hidden. |
| ~0.78–0.95 | It lands at `Pivot_DropPoint` on the chute floor (y 0.90) with a hop and a wobble. **CanDrop** thunk. |
| 1.00–1.18 | **DeliveryFlap** swings from its modelled rest `State_FlapAjar` (−22°) to `State_FlapOpen` (−78°) about `Pivot_FlapHinge` and the authored X axis. That swing goes INTO the chute. |
| 1.18–1.42 | The snack slides out under the flap, stands up and flies in an arc into the buyer's RightHand (Whoosh). |
| 1.40 (server) | The server welds the real snack into the hand. The flying copy waits there (up to 0.5 s) until the server's snack has replicated, then hides. |
| 1.45 | The flap is let go. It swings back, hits the frame at `State_FlapShut` (0°) with a DoorClose clack, then settles at the rest angle by 3.05 s. |

5. **Drinking or eating (every client poses the buyer).**
   * **Timing.** Sips start at 1.70, 2.50 and 3.30. Each raises for 0.26 s, holds for 0.26 s and lowers for 0.28 s. Between sips the arm stays up 35 %. A Gulp plays 0.3 s into each sip; for Chips it's pitched up 1.3× as a stand-in crunch.
   * **Arm pose.** In `RunService.Stepped`, after the Animator, the buyer's RightShoulder / RightElbow / RightWrist / Neck `Transform` blends toward `SIP_POSE`. It works for both Motor6D and AnimationConstraint; the joints are found by their Part1, or by `Attachment1.Parent` for constraints.
   * **Where the pose comes from.** An IK solve on the R15Rig in `assets/CucumberAnims.blend` (the same pipeline as CucumberLiftPoses). The fist ends up up-right of the face.
   * **The snack during a sip.** The snack's `SnackWeld.C0` is blended locally so the snack runs from the fist to the lips. Its bottom is 0.35 from the fist centre and its top is at the mouth. This is computed live from the Head and RightHand CFrames, so it follows any body shape.
   * **No stacking.** If the Animator skipped a joint in a frame (it still holds our last write, compared with `FuzzyEq`), the blend starts from the Animator's last real value instead. When the sip ends, that value is handed back.
6. **4.30: Burp.** `Sfx.Burp` plays at the head, and 16 green bubbles puff from the mouth (`rbxassetid://241594314`, the soft dot the portals use; Emit only, Rate 0). The snack gets `LocalTransparencyModifier = 1` on every client, and the **server destroys it at 4.9**.
7. **The sign, always.** NeonText ("SNACKS" plus the 1.50 price) hums at 93–100 % brightness. A few times a minute it hits a short "bad moment" and stutters to 60 % (`NEON_GATE / NEON_BUZZ / NEON_DIM`). Measured with a Perlin port, that's about 4.5 bursts and 18 blinks a minute, dimmed about 2 % of the time. It's driven by `math.noise(server time)`, so every client flickers together.

## Server snack (in the buyer's character)
* The root is an invisible Part `FunSnack` (size depth × length × depth). Its +Y is the snack's top and its −Z is the label side.
* Root attributes: `SnackKind`, `SnackLength` (studs), `SnackT0`.
* `Weld "SnackWeld"`: Part0 = RightHand, C0 = in front of the fist, upright. On R6 it welds to "Right Arm", but there's no pose.
* Every part is Massless and has CanCollide / CanTouch / CanQuery off.
* Sizes are at character scale 1 × `HumanoidRootPart.Size.Y / 2`, the same rule as CucumberLiftClient.
* Soda / Cola: 0.44 × 0.80 can, band, lid, rim, tab, plus a cucumber logo or a red stripe.
* Chips: 0.56 × 0.84 puffy bag, red crimps, white/red banner, two chips.
* The machine keeps its live snacks in its own set (not `ctx:Add`: that list only empties when the ctx stops, and a machine vends for hours). Each snack leaves the set when it is destroyed at 4.9 s. The behaviour's cleanup destroys whatever is left, so a sold, moved or broken machine takes its snacks away.
* On R6 (no `RightUpperArm` joint) the body is not posed: the snack stays in the plain "Right Arm" hold, and the gulps, burp, bubbles and vanish still play.

## Instance bookkeeping (fix pass 2026-09-24)
* **Nothing per vend goes through the ctx.** The drop copy's parts, the Gulp / Burp one-shot sounds and the burp puff attachment are made with `Instance.new` and tracked in the client behaviour's own `owned` set. Each one leaves the set when it is destroyed, and the cleanup destroys the rest. Only the once-per-machine anchors, the 5 machine sounds and the key flash are ctx-registered.
* **Far cameras.** `OnVend` only stores a small record per vend and first ends every vend older than 3.05 s. The drop copy's parts are built by the Step on its first awake frame for that vend (the Step sleeps beyond `StepRange` 160), and never if that is after 1.3 s. So a client far from the machine never builds drop parts, and holds at most the last few seconds of records. The sipper (buyer pose, gulps, burp) and the "wait a sec" prompt text still run at any distance.
* **Joints are always handed back.** If the server snack vanishes mid-sip (machine sold, moved or broken: the server ctx stops first), or a sip step throws, the sipper is released with `Unbind` before it is dropped. The client cleanup releases every sipper.

## Geometry the client relies on
* **Build parts:** `DeliveryFlap`, `NeonText`, `Hitbox`.
* **Attributes:** `Pivot_KeypadCentre / DropPoint / FlapHinge / CashSlot` and `State_FlapAjar / FlapOpen / FlapShut`. All have fallbacks.
* **Authored numbers** from `props/build_vending_machine.py`, converting Blender (x,y,z) to (x, z, −y):
  * shelf tops 2.02 / 3.74 / 4.60
  * stock front z −0.50, falling front z −0.60 (shelf lip −0.58, glass back −0.64)
  * sill top 1.94, chute floor 0.90, chute mouth z −0.98
  * keypad pitch 0.26
* **Stock slots**, reproduced with the prop's `random.Random(20260909)`:

| Snack | Stock colour | Slots (shelf top, x) |
|---|---|---|
| Soda | green cans | (2.02, x 0.350) and (3.74, x 0.460) |
| Cola | orange cans | (2.02, x 0.570) and (3.74, x 0.724) |
| Chips | the yellow bag | (4.60, x 0.724) |

* **Flap posing.** The flap is posed relative to the **Hitbox**, never from a remembered world CFrame, and only while it moves. At rest it is never written, so a move / restart can't leave it floating at the old spot.
* **Cleanup** restores the flap to rest, the NeonText colour and the prompt text. It also releases any posed joints and the weld C0.

## Sounds (FunAssets.Sfx)
* **In use:** Coin, Click, CanDrop, DoorClose, Whoosh, Gulp, Burp.
* **Wishes for the integrator:**
  * a real **gulp** and a real **burp**: today both are "Bottle Pop 2"
  * a **crunch** for Chips
  * a short **spiral-motor whirr** for t 0.2–0.55
  * a **coin insert** clink

## How to test
* **By hand.** Place a VendingMachine, walk to its keypad (right-hand column), hold E on "Get a snack" and watch the glass, then the flap, then your hand. Press again within 8 s: nothing happens and the prompt says "Out of coins, wait a sec".
* **Client eval near the machine (triggers a real vend):**
  ```lua
  local pp
  for _, d in workspace:GetDescendants() do if d.Name == "VendPrompt" then pp = d end end
  pp:InputHoldBegin() task.wait(0.4) pp:InputHoldEnd()
  ```
* **Server check:** `player.Character.FunSnack` exists from +1.4 s to +4.9 s, with `SnackWeld.Part0 == RightHand`. `workspace:SetAttribute("FunBuildDev","list")` lists the machine.
* **Offline check (no Studio):** `cd FB\tools\vend_harness; py gen.py; luau test.luau`. It runs both halves against Roblox mocks with real CFrame maths and prints the item path, flap angle, weld C0, joint pose, sounds and cleanup. It also asserts that:
  * a whole vend adds nothing to either ctx's instance list
  * 60 vends heard by a far camera leave 0 drop parts behind
  * a camera that comes back mid-vend gets its copy, and the next vend prunes it
  * an R6 buyer gets no pose but still plays the gulps and burp
  * the server cleanup mid-sip destroys the snack, and the client then hands the shoulder back
  * the client cleanup leaves no drop parts, sounds or puffs

  It ends with "OK harness finished". Delete the generated `mod_*.luau` afterwards.
* **Renders** (`FB\models\renders\`):
  * `VendingMachine_drop_{soda_low,cola_mid,chips_top}_{front,three}.png`
  * `VendingMachine_flap_open.png`
  * `VendingMachine_hold_front.png`
  * `VendingMachine_sip_a_{front,dead,left,side}.png`
  * `_VendSnacks_{front,three,back}.png`

## Known limits
* **Sip pose accuracy.** The pose is tuned on the blocky R15 proportions. On Rthro or other bodies the fist lands near the mouth rather than on it. The snack stays attached to the fist, and its top sits at the live mouth point along the fist→mouth line.
* **Stepped conflicts.** Another client script that also writes the right-arm Transforms in Stepped (CucumberLiftClient while lifting) would fight for about 2 s if someone starts a lift during a sip. That's rare, because the cooldown covers most of the sequence.
* **Snack size jump.** The flying copy is machine-sized (0.24 × 0.49 studs at ×1.25). The hand snack pops in slightly bigger when it takes over.
* **Shelf lips.** The falling snack's back half passes through the shelf lips for about a frame. It's hidden, because its front face is 0.02 in front of them.
* **Local wait text.** "Out of coins, wait a sec" shows only on the machine the buyer used. Other machines still say "Get a snack" but ignore the press.
* **Streaming.** If a client streams the machine in after a vend, it skips that vend's animation.
* **Camera range.** A camera that comes within 160 studs more than 1.3 s into a vend sees no falling snack for it (sounds past 0.3 s late are skipped too); the flap still swings.
* **Please verify in Studio:**
  * `CFrame:FuzzyEq` exists. It's used in the no-stacking check, which runs inside a pcall. If it errors, the sip is skipped and a warning is logged.
  * Writing `AnimationConstraint.Transform` in Stepped shows on other clients. Every client poses the buyer itself, so it should.
