# In-game QA recipe (RAS - Dev solo playtest, chrrxs robloxstudio MCP)

1. Server eval (`eval_server_runtime`), hand a launcher out without touching the saved profile:
```lua
local p = game.Players:GetPlayers()[1]
local sf = require(game.ServerStorage.Modules.ServerFunctions)
local sapi = sf[2]
sapi:ClearLauncher(p)
return sapi:GiveLauncher(p, "<catalog display name, e.g. Snow Scoop>")
```
   Restore at the end with `sapi:GiveLauncher(p)` (no name = the saved EquippedLauncher).
2. Client eval (`eval_client_runtime`): wait for `vars.ChargeAnimation.Profile.id == <order>`
   (vars = `require(PlayerScripts.ClientMain.Utilities.Variables)`), then
   `PlayerGui:SetAttribute("DevChargeHold", true)`, ~0.7 s, `false`, and sample on Heartbeat:
   `controller.DidFire` time, the local `workspace.LauncherBallsLocal.LauncherBall` position,
   the ride ball `workspace.ActiveSnowballs.<Name>_Snowball` and its `LaunchOrigin` attribute.
   `vars.Functions:StopRide()` afterwards.
3. Freeze a frame for a screenshot: `mountainConfig.LAUNCH.ReleaseCamera.Hold = 30` (the config
   table is shared in the client VM), then override `controller._step` on the instance to pass
   dt = 0 once `Elapsed > fireAt + 0.03`, and `controller.Ball.Step = function() end` so the flying
   copy stays at the muzzle; `capture_screenshot`; remove both overrides (`= nil`) and restore Hold.
