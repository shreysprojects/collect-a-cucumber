--.. MusicClient (LocalScript, StarterPlayerScripts)
--.. Starts the lobby track (SoundService."Background Music") through MusicManager with a
--.. fade-in and mirrors the LocalPlayer attribute "MusicMuted" into MusicManager.SetMuted,
--.. so a future settings UI only has to set that attribute. "SFXEnabled" = false on the
--.. LocalPlayer silences SoundController.PlayFX the same way.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local MusicManager = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("MusicManager"))
local player = Players.LocalPlayer

local music = SoundService:WaitForChild("Background Music", 15)
if not music then
	warn("[MusicClient] SoundService.Background Music is missing")
	return
end

MusicManager.Register(music)
local function applyMute()
	MusicManager.SetMuted(player:GetAttribute("MusicMuted") == true)
end
player:GetAttributeChangedSignal("MusicMuted"):Connect(applyMute)
applyMute()
if not music.IsPlaying and not MusicManager.IsMuted() then
	MusicManager.Play(music, 1.5)
end
