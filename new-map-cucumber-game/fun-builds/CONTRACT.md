# Fun builds - contract for every agent (2026-09-24)

User request (New Map Cucumber Game, place 87967102884366):
> make some builds bigger that should be bigger (post lantern way too small, seesaw bigger/longer). make all the
> fun stuff functional - tv can be turned on to watch videos/decal slideshows, trampoline bouncy, seesaw functional,
> etc. build household things like appliances, couches, etc. improve ugly builds like the defence towers (freeze
> tower, laser gate ...). effects from defences, e.g. freeze tower hits put blue particles on each enemy hit.

Root: `C:\Users\shrey\OneDrive\Documents\RobloxGames\new-map-cucumber-game\fun-builds\` (below: `FB\`).
**You work on FILES ONLY.** Never call Roblox Studio or Blender MCP tools, never touch another agent's files,
never edit `FB\src\FunBuildKit.lua`, `FunBuildService.server.lua`, `FunBuildClient.client.lua`, `FunAssets.lua`
(ask for changes in your notes file instead). The integrator installs and playtests everything.

## 1. How builds work in this game (read-only background)
* Build mode sells `ServerStorage.Builds/<Category>/<Model>`. `BuildService` clones each into
  `ReplicatedStorage.PlaceableBuilds/<Category>/<Key>` = the *template*: all parts anchored, CanTouch off,
  an invisible `Hitbox` PrimaryPart around the bounding box, scripts/prompts stripped. Variant collections
  (parts prefixed `A_`/`B_`/`C_`) become one build each: Key `Lantern_A` keeps only the `A_*` parts.
* A player places a template clone into `workspace.Map.Lobby.Plots.<Plot>.Placed` with attributes
  `Owner` (UserId), `BuildKey`, `Level`, `PlotX/PlotZ/Yaw` and CollectionService tag **`PlacedBuild`**.
  Builds can be MOVED (whole model pivoted), SOLD (destroyed), restored on join (BaseSaveService clones the
  template again), and bashed by zombies at night: `BuildHealthService` sets **`Broken = true`**, fades every
  part to 0.65 transparency and turns collisions off; it mends later (`Broken = nil`) and restores them.
* NEW (integrator, 2026-09-24): templates are scaled by `BuildCatalog.SCALE` (e.g. Seesaw x1.8, Lantern_A x2.1,
  Trampoline x1.5, TV x1.45) and carry `Scale`, `AuthoredCentre` and every `Pivot_*` / `State_*` authoring
  attribute. Templates stream atomically (the whole model arrives at once on clients).
* Characters are ~6.1 studs tall (R15, taller at higher physique stages), WalkSpeed ~16-40, gravity 196.2,
  JumpHeight 7.2. Characters are **network-owned by their client**: to move/launch a character, set its
  velocity **on that player's client** (the server validates, never trusts). Joints are AnimationConstraint
  (not Motor6D) - accept both (`Kit.Joints`).
* StreamingEnabled is ON. Clients only have builds near them; everything client-side must cope with a build
  appearing/disappearing at any time (the framework does this for you).

## 2. The framework (already written - use it, don't re-implement it)
Files: `FB\src\FunBuildKit.lua` (shared helpers), `FB\src\FunBuildService.server.lua`, `FB\src\FunBuildClient.client.lua`,
`FB\src\FunAssets.lua` (all sound/video/picture ids). **Read all four before writing code.**

A behaviour = two ModuleScripts named after the build's BASE key (`Lantern` serves `Lantern_A/B/C`):
* server: `FB\src\behaviours\server\<Base>.lua` -> `ServerStorage.FunBehaviours.<Base>`
* client: `FB\src\behaviours\client\<Base>.lua` -> `ReplicatedStorage.FunBehavioursClient.<Base>`
Either half may be omitted if it has nothing to do (a server half is needed for prompts/seats/state).

```lua
-- server half
local Kit = require(game:GetService("ReplicatedStorage").Modules.FunBuildKit)
local FunAssets = require(game:GetService("ReplicatedStorage").Modules.FunAssets)
local B = {}
B.Keys = {"Trampoline"}            -- optional: which keys/base keys this module serves (default: its own name)
B.ActionRange = 40                 -- optional: max studs player<->build for Actions (default 40)
function B.Server(model, ctx)      -- runs once per placed build; return an optional cleanup function
end
B.Actions = {                      -- client -> server: ctx:Send("Channel", payload) on the client lands here
	Channel = function(model, player, payload, ctx) end,
}
return B

-- client half
local B = {}
B.StepRange = 180                  -- optional: ctx:Step sleeps when the camera is farther than this
function B.Client(model, ctx) end  -- runs when the build streams in / is placed; return optional cleanup
function B.OnEvent(model, action, payload, ctx) end -- server ctx:Fire(action, payload) lands here
return B
```
**Everything created through ctx is destroyed automatically** when the build is sold, moved (the behaviour
is re-run from scratch at the new spot), broken (nothing runs while `Broken`), streamed out, or the server
restarts. Put anything you create through `ctx:Add(inst)` / `ctx:Part` / `ctx:Sound` / `ctx:Prompt` /
`ctx:Seat` / `ctx:Connect`, and restore any build part you animated (CFrame, Transparency, Color...) in your
cleanup function.

Server ctx: `Model, Key, Base, Variant ("A"/nil), Scale, Folder (workspace.FunBuildRuntime/<...>)`,
`ctx:Alive()`, `ctx:Connect(signal, fn)`, `ctx:Add(inst)`, `ctx:OnCleanup(fn)`,
`ctx:SetState(k, v)` (model attribute `Fun_<k>`, replicates; cleared on stop) / `ctx:GetState(k)`,
`ctx:Fire(action, payload)` (all clients) / `ctx:FireTo(player, ...)`, `ctx:Every(sec, fn)`, `ctx:Heartbeat(fn)`,
`ctx:IsOwner(player)`, `ctx:HumanoidOf(player) -> humanoid, root`, `ctx:Near(player, dist)`,
`ctx:Prompt(part, {Action, Object, Hold, Distance, Key, Name, Offset})` -> ProximityPrompt (Custom style,
drawn by the game's CucumberPromptClient; hidden automatically in build mode),
`ctx:Seat(worldCFrame, {Name, Size, Lie, LieLift, Prompt, Object, Distance, PromptOffset})` -> Seat (invisible,
anchored, no touch-sit; its "Sit" prompt seats the player; `Lie = true` lays them flat on their back with the
head toward the seat's LookVector - beds, hammocks, loungers), MEASURED in a playtest (2026-09-24): a lying occupant's pelvis sits on the seat, the head reaches ~2.5 studs toward
the seat's LookVector and the feet ~3.8 studs the other way, body ~0.8 above the seat top; a sitting occupant's root is ~1.9
above the seat centre. Seats' prompts disable themselves while occupied. `ctx:Part(props)` (helper part in the runtime
folder - NEVER parent helper parts inside the build model: the placement overlap test and the broken fade
would see them), `ctx:Sound(parent, FunAssets.Sfx.X, props)`.

Client ctx: `Model, Key, Base, Variant, Scale, Player`, `ctx:Alive()`, `Connect`, `Add`, `OnCleanup`,
`ctx:State(k)` / `ctx:OnState(k, fn(value))` (fires now + on change), `ctx:Send(action, payload)`,
`ctx:Step(fn(dt, serverNow))` (every frame, asleep when the camera is > StepRange away), `ctx:Every`,
`ctx:Sound`, `ctx:Part(props)` (local-only visual part), `ctx:LocalCharacter() -> humanoid, root, character`,
`ctx:Near(dist)`, `ctx:IsOwner()`, `ctx:CameraDistance()`.

Kit (both sides): `Kit.Key/Split/VName(model, "Light") -> "A_Light"`, `Kit.Scale`, `Kit.Hitbox`,
`Kit.Origin(model)` (world CFrame of the authored origin = floor centre), `Kit.ToWorld(model, authoredPoint)`,
`Kit.CFrameToWorld`, `Kit.Pivot(model, "PlankPivot") -> world Vector3` (reads `Pivot_PlankPivot`),
`Kit.Floor`, `Kit.Part(model, name)`, `Kit.Parts(model, prefix)`, `Kit.Rig(parts, pivotCF)` +
`Kit.PoseRig(rig, cf)` (rigid animation about a pivot), `Kit.IsBroken`, `Kit.OwnerId`, `Kit.State`,
`Kit.Now()` (server time - use it to keep clients in sync), `Kit.Joints(character)`, `Kit.MakeSound`.

**Geometry rule:** never hard-code world numbers. Every authored coordinate (the part dump, the `Pivot_*`
attributes, your own model's numbers) is in the build's AUTHORED frame (floor centre = origin, front = -Z,
+Y up) at scale 1: map it with `Kit.ToWorld` / `Kit.CFrameToWorld` / `Kit.Pivot`, and multiply authored
LENGTHS by `ctx.Scale`. Animate parts relative to where they ARE (`Kit.Rig` from their current CFrames).

## 3. Design rules for behaviours
* Anyone may use a build (like the boost pad), unless it would let people grief the owner (then `ctx:IsOwner`).
* Shared state lives on the SERVER (`ctx:SetState`); clients render it. Anything cosmetic and per-frame
  (animations, particles, screen content, music playback) runs on the CLIENT, driven by state + `Kit.Now()`
  so every client shows the same thing. Don't CFrame parts every frame on the server.
* Physics on characters (bounce, slide, push) happens on the local player's client for its own character.
* No economy impact unless the brief says so: no free Cash / Strength, no speed boosts stronger than a
  cosmetic nudge. Existing boost attributes (`SpeedBoostUntil` etc.) are OFF LIMITS.
* Sounds: only via `FunAssets.Sfx.<Name>` / `FunAssets.Music` / `FunAssets.TVChannels` (the integrator fills
  verified ids). If you need a sound that isn't listed, use the closest one and list the wish in your notes.
* GUIs (arcade, piano ...): built in code on the client, parented to PlayerGui, `ResetOnSpawn = false`,
  `IgnoreGuiInset = true`, Font `FredokaOne`, white text with a dark `UIStroke`, rounded (`UICorner`) panels,
  green (69,255,0)->(157,255,36) / red (230,30,30) buttons like the HUD, a close button, usable on touch
  (big buttons) and keyboard, `UIScale` from viewport size. Close it when the player walks > 20 studs away.
* Performance: at most one `ctx:Step` per build; no per-frame `GetDescendants`; cache parts; particle Rate
  modest (<= 30/s); lights <= 2 per build; every loop exits when `ctx:Alive()` is false.
* Use `pcall` around anything that can fail (asset loads, VideoFrame, Animator loads).
* Code style = the game's: tabs, `--..Section..--` comments, a header block comment explaining the behaviour.
* Syntax check every file: `powershell -NoProfile -ExecutionPolicy Bypass -File FB\tools\luacheck.ps1 <files>`
  (compiles without running; must print OK).

## 4. Models (Home furniture, rebuilt defences)
Author with `FB\models\primlib.py` (read its docstring) in `FB\models\build_<Key>.py` defining
`build(D, P) -> P.Model(D, "<Key>", category="Home").finish()`. Run it headless (parallel-safe):
```
& "C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" -b --factory-startup --python FB\models\run_one.py -- <Key>
```
-> `FB\models\out\<Key>.parts.json` + `FB\models\renders\<Key>_front.png / _three.png / _back.png` (a 6-stud red
blockout avatar stands beside it). **Look at your renders with the Read tool and iterate until it looks
good** - review renders, not code. Primitives: Block, Wedge, CornerWedge, Cylinder (axis X, round),
Ball (round), Ellipsoid (any size, Block+SpecialMesh Sphere). ROBLOX coordinates: +Y up, FRONT = -Z,
origin = floor centre, min y = 0. Cylinders/balls MUST be round (primlib asserts).
* Look: the game is a bright toy-like Roblox world. Match the existing prop palette - yellow f2c13d, blue
  3f79d4, red d9443c, near-black 23262c, off-white f2f0ea, wood 8a5a2b / 6b4423, metal 9aa7b8 / 3b4350 - and
  use real Roblox materials (Wood, WoodPlanks, Fabric, Leather, Metal, DiamondPlate, Glass, Marble, Ice,
  Neon sparingly for glows/screens, SmoothPlastic). Chunky readable silhouettes, bevel-like edges from thin
  trim blocks/cylinders, no z-fighting (overlap parts by >= 0.02 instead of coplanar faces).
* Scale for a 6-stud avatar: seat top 2.0-2.4, table top 3.0-3.3, kitchen counter top 3.6, bed top ~2.2,
  door/fridge height 7-8, lamp 7-9. Footprints on the 8-stud grid where natural (8 wide, 4 deep ...).
* Budget: furniture <= 70 parts, big appliances <= 90, defences <= 140. Tiny details `collide=False`.
* Name parts for the behaviour: every moving group shares a prefix (`Door*`, `Drum*`, `Burner*`, `Screen`),
  and record every point a behaviour needs with `m.pivot("Name", pos)` (hinge axes, seat spots, light spots,
  spout tips). Put `m.attr("Cost", n)` on every model.

## 5. Deliverables (every agent)
* your files under `FB\` only; a notes file `FB\notes\<Base or Key>.md`: what it does, part names / pivots it
  relies on, sounds wished for, how the integrator can test it (which prompt, which state to read), known limits.
* Final answer: a short JSON-ish summary (files written, luacheck result, render paths, open questions).
