# Lift rebuild test recipe (solo playtest, chrrxs MCP)

Server side (eval_server_runtime / execute_luau target server):
- set the test account's strength: `game.Players.<name>.Data.Strength.Value = N` (DataService quiet flag not needed for a test)
- start a lift on the nearest cucumber: `workspace:SetAttribute("CarryDev", "collect:<name>")` (edge-triggered: nil it first when re-firing the same command)
- force the outcome without clicks: `"win:<name>"` / `"lose:<name>"`

Client side (eval_client_runtime):
- `player.PlayerGui:SetAttribute("LiftDevCPS", 6)` clicks the bar 6 times a second while it is up
- `player.PlayerGui:GetAttribute("LiftDevState")` = "idle" | "approach" | "lift 0.42" | "hoist" | "fail"
- sampler: a task.spawn thread that records the Icon's AbsolutePosition, the camera CFrame,
  LeftHand.Position (pose proof: Motor6D.Transform override on Stepped) and the holder pivot
  into PlayerGui attributes, read back with a second short eval (evals over ~20 s time out).

Expectations:
- ratio >= 3.5 (e.g. strength 100 vs a 3 kg slice): 2 clicks lift it (Gain 0.36 from Start 0.35)
- ratio 1 (strength 3 vs 3 kg): ~10 clicks against Drift 0.12/s; 6 cps wins in ~2.5 s
- ratio < 1 (strength 2 vs 3 kg): even 20 cps loses (Gain 0.019 x 20 = 0.37/s < Drift 0.55/s)
- after a win: player attribute CarryingCucumber set, CarryingCucumberKg = the kg, holder gone,
  CarriedCucumber on the shoulder; WalkSpeed restored to StrengthWalkSpeed; camera back to Custom
- after a loss: "Too heavy" toast, holder back at its base pivot, prompt re-enabled, Busy released
