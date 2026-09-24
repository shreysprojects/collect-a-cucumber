--[[---------------------------------------DESCRIPTION------------------------------------------
	UI manifest for this place. Each key is spawned by GUIFramework.

	Parent     = path under PlayerGui. Omit to parent into Graphics. An empty path ({}) puts
	             the Interface straight into PlayerGui: use it when the Interface is a whole
	             ScreenGui with its own DisplayOrder (race bar, charge bar, hint).
	Module     = ServerStorage.Modules.UserInterfaces child name (defaults to key)
	Interface  = frame name under ServerStorage.Assets.UserInterfaces[Module]

	Every UI lives here: its frames under ServerStorage.Assets.UserInterfaces[key], its logic
	in ServerStorage.Modules.UserInterfaces[key]. Nothing goes in StarterGui.

--------------------------------------------------------------------------------------------]]--

return {
	HUD = {
		Parent = { "HUD", "Base" },
	},
	-- Whole ScreenGuis, spawned into PlayerGui under the key's name.
	RaceProgressGui = { Parent = {} }, -- race bar, draws under the HUD (DisplayOrder -1)
	ChargeHint = { Parent = {} }, -- "HOLD TO LAUNCH" above the ride controls
	ChargeBar = { Parent = {} }, -- hold-to-launch bar, enabled while charging
	Gift = { Parent = {} }, -- "2x power!" checklist by the lobby present (GiftCircle ring)
}
