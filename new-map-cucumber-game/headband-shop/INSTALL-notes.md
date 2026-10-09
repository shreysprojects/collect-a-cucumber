# Headband shop - install notes (server half)

Files in this folder, and where each one goes in the DataModel:

| File | Parent | Class | Name |
|---|---|---|---|
| `HeadbandsCatalog.lua` | `ReplicatedStorage.Modules` | ModuleScript | `HeadbandsCatalog` |
| `HeadbandService.lua` | `ServerScriptService` | Script | `HeadbandService` |

Push the catalogue **before** the service - the service `require`s it with `WaitForChild`, so a
wrong order only stalls, but a missing module stalls forever.

---

## 1. The one edit you must make by hand

`ServerStorage.DataService` (ModuleScript) - add **one line** to its `TEMPLATE` table, right after
the `CucumberCollection` line, so the shape reconciles into every existing profile
(`profile:Reconcile()` does this automatically on load):

```lua
local TEMPLATE = {
	Coins = 0,
	Playtime = 0, -- seconds in game across all sessions
	Strength = 0, -- + Strength upgrade level per bench-press rep (GymService)
	CucumberCollection = {Seen = {}, Families = {}, BestRequired = 0, BestSize = 0, TotalSecured = 0},
	Headbands = {Owned = {}, Equipped = ""}, -- headband shop (HeadbandService): Owned[name] = true
	PlotLevel = 0, -- plot size upgrade level 0..6 (PlotUpgradeService)
	Upgrades = {BenchPress = 1},
}
```

The line to add, verbatim:

```lua
	Headbands = {Owned = {}, Equipped = ""}, -- headband shop (HeadbandService): Owned[name] = true
```

Also worth adding to that module's header comment, where it lists the saved template:
`Saved template (profile.Data): Coins, Playtime, Strength, CucumberCollection, Headbands, PlotLevel, Upgrades.`

**The service works without this edit** - `State(player)` creates and normalises
`profile.Data.Headbands` lazily on first use, and ProfileStore saves whatever is in `profile.Data`.
Make the edit anyway: without it a brand-new profile has no `Headbands` key until the player first
touches the shop, and `REMOVED_KEYS` / `Reconcile` have nothing to hold on to.

Do **not** add anything to `VALUE_ORDER` (that builds the replicated `player.Data` NumberValues, and
headbands replicate as player attributes instead), and do **not** touch `player.leaderstats`.

---

## 2. DataModel paths this code expects to exist

Already in the place (recon-confirmed):

- `ServerStorage.DataService` - `Get` / `Increment` / `GetData` / `RequestSave` / `OnProfileLoaded`
- `ReplicatedStorage.Modules` - the service requires `HeadbandsCatalog` and `NumberAbbrev` from here
- `ReplicatedStorage.Assets` - the folder the headband models go under (see below)
- `Workspace.Map.Lobby` - with the attribute `LayoutReady`, set by `ServerScriptService.LobbyLayoutServer`
- `Workspace.Map.Lobby.Shops["Buy Shop"]` - the empty open-fronted stall the prompt is built on
- `Workspace.Map.Lobby.Floor` - used to find the walkable Y under the booth (a raycast is the fallback)

Created at runtime by `HeadbandService`, so nothing to make by hand:

- `ReplicatedStorage.Remotes` (find-or-create, as every other server script does)
- `ReplicatedStorage.Remotes.HeadbandAction` - **RemoteFunction**
- `ReplicatedStorage.Remotes.OpenShopDialog` - **RemoteEvent**
- `Workspace.Map.Lobby.Shops["Buy Shop"].TalkAnchor` - invisible anchored Part, a **child of the
  booth Model** so `LobbyLayout.Apply()` carries it along; rebuilt every server start
- `…TalkAnchor.TalkPrompt` - ProximityPrompt, tagged `ShopBoothPrompt`, attribute `Shop = "Headbands"`

## 3. The art (still in Blender)

Create the folder `ReplicatedStorage.Assets.Headbands` and put the 12 uploaded models in it, each a
**Model** named exactly as the catalogue's `Name`:

```
Sweatband  RedBandana  CamoBand  CucumberBand  StrawBand  LeafCrown
SteelBand  CactusBand  FrostBand  GoldBand     LavaBand   ChampionBand
```

Authoring contract (the service builds the Accessory around it):

- the band's ring is centred on the **model origin**, ring axis along **+Y**
- the **front** of the band faces **-Z** (the direction a character faces)
- scaled for a default R15 head: 1.2 studs across

If a model is missing the service prints
`[HeadbandService] no model for <Name> yet (expected ReplicatedStorage.Assets.Headbands.<Name>) -- nothing worn`
and carries on - buying, equipping, saving and the shop UI all keep working. A bare `MeshPart` at
that path (instead of a Model) is tolerated too.

The service is the only thing that touches `Assets.Headbands`; the shop UI reads it through
`HeadbandsCatalog.ModelOf(name)`, which returns `nil` rather than erroring while the art is absent.

## 4. Contract for the client half (dialogue + shop UI)

```lua
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
Remotes:WaitForChild("OpenShopDialog").OnClientEvent:Connect(function() ... end)   -- prompt triggered
local Action = Remotes:WaitForChild("HeadbandAction")
local ok, message = Action:InvokeServer("Buy", "GoldBand")   -- also ("Equip", name) and ("Unequip")
```

- both calls return `ok: boolean, message: string` - toast `message` through
  `ReplicatedStorage.Modules.Notify` (`Notify.Success` / `Notify.Error`), the PlotUpgradeClient shape
- a call inside 0.3 s of the last one returns `false, "Slow down"`
- state arrives as **player attributes**, not a remote:
  - `EquippedHeadband` - the collection name, `""` when nothing is worn
  - `OwnedHeadbands` - owned collection names, comma-joined in tier order, e.g. `"Sweatband,CamoBand"`
  - watch them with `player:GetAttributeChangedSignal("OwnedHeadbands")`
- prices, display names, tier order, blurbs and card colours all come from
  `require(ReplicatedStorage.Modules.HeadbandsCatalog).List()`
- the booth prompt is `Style = Default` on purpose - `CucumberPromptClient` draws every `Custom`
  prompt, and this one should look like the stock Roblox key badge

## 5. Behaviour worth knowing

- Tier 1 (**Sweatband**, free) is granted to every profile on load. It is **owned, not worn** - a
  fresh player is bare-headed until they equip something.
- Buying does **not** auto-equip, unless the player is wearing nothing at all (which includes their
  very first purchase).
- The worn item is an `Accessory` named `Headband_<Name>` - the first Accessory in this game, chosen
  deliberately because it survives respawn and Roblox does the head fit for us. Teardown finds it by
  the `Headband_` name prefix, so nothing else on the character is disturbed.
- Fit maths, if a band ever sits wrong: `HAT_ATTACHMENT_Y = HEAD_HAT_Y (0.6) - BAND_LIFT (0.28) = 0.32`
  at the top of `HeadbandService`. Raise `BAND_LIFT` to float the band higher off the skull.

## 6. Testing in Studio

Set the workspace attribute `HeadbandDev` (a string) - it acts on the first player in the server and
clears itself:

| Value | Does |
|---|---|
| `coins:5000` | adds 5 000 Coins |
| `give:CucumberBand` | grants ownership without charging |
| `equip:GoldBand` | grants + equips (skips the price check) |
| `reset` | back to owning only the Sweatband, wearing nothing |

Expected output at server start:

```
[HeadbandService] 12 headbands (Sweatband free .. Champion Band 50M Coins), Remotes.HeadbandAction + Remotes.OpenShopDialog ready
[HeadbandService] shopkeeper prompt on Buy Shop at 1162.4, -225.8, 217.2 (tag ShopBoothPrompt)
```

(the prompt's coordinates are computed at runtime from the booth's pivot and part bounds, so they
move with whatever `LobbyLayout` decides that server start - the numbers above are only indicative)
