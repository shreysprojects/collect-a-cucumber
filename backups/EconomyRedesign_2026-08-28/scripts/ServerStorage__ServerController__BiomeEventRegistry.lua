--[[
	BiomeEventRegistry
	THE single place to define biome events. Add an entry to Events below and
	the whole stack picks it up:

	  * the post-boss event selector cycles through it (respecting
	    MinPlayersInBiome at selection time)          [BreakablesService.StartEventChallenge]
	  * the admin panel can start/stop it per biome,
	    in several biomes at once                     [AdminPanelService "StartEvent"/"StopEvent"]
	  * the biome travel popup ("X started in Y! Go
	    there?" + Teleport) fires when it begins      [BiomeActivityPromptClient, via meter attrs]
	  * the boss bar shows EventName + countdown
	    while it runs                                 [BossBarClient generic "Active" branch]
	  * it auto-ends after Duration seconds with the
	    standard "over" toast                         [BreakablesService BeginEvent/StartEvent]

	Fields per event:
	  Id (string, unique)      wire id used everywhere (meter EventId attribute)
	  Name (string)            player-facing, ALL CAPS like the others
	  MinPlayersInBiome (int?) selector-only gate: the rotation offers this event
	                           only when at least this many players are in the
	                           biome at SELECTION time (admin starts ignore it).
	                           Default 0.
	  Duration (number?)       seconds; defaults to BreakablesService's 2-minute
	                           standard. Written to the meter as EventDuration so
	                           the boss bar's fill drains at the right rate.
	  EffectModule (string?)   name of a ServerController module exposing
	                           SetZoneEventActive(zoneName, enabled) -- called
	                           with true on start and false on EVERY end path
	                           (expiry, admin stop, admin overwrite). Use this
	                           for events with real logic (CucumberSmash keeps
	                           per-zone scores + podium rewards this way).
	                           Simple ambience effects can instead add a branch
	                           in BreakablesService.SetEventEffect.

	If the event needs its own boss bar layout (like CucumberSmash's
	"M:SS LEFT • YOUR SMASHES: N"), add an EventId branch in BossBarClient;
	otherwise the generic "EVENTNAME: M:SS" display is automatic. A custom
	popup accent color is one line in BiomeActivityPromptClient.EVENT_COLORS.
]]

local BiomeEventRegistry = {}

BiomeEventRegistry.Events = {
	{Id = "GoldenHour"; Name = "GOLDEN HOUR";},
	{Id = "SuperStrength"; Name = "SUPER STRENGTH";},
	{Id = "CucumberSmash"; Name = "CUCUMBER SMASH";
		MinPlayersInBiome = 2; -- a race needs racers
		Duration = 90;
		EffectModule = "SmashEventService";},
}

function BiomeEventRegistry.Get(eventId)
	for _, def in ipairs(BiomeEventRegistry.Events) do
		if def.Id == eventId then return def end
	end
	return nil
end

--.. the ServerController loader calls Initialize() on every child module
function BiomeEventRegistry.Initialize() end

return BiomeEventRegistry
