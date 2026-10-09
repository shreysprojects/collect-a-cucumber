# Research: menus + HUD UI (pets system)

Source: the local snapshot `new-map-cucumber-game/live-2026-09-22/` (2026-09-22). Line numbers below are
the snapshot files' line numbers (`L<n>`); `tree L<n>` = `_gui_tree.txt` line. Nothing was read from Studio.
Unknowns that need one read-only Studio look during implementation are marked **[READ IN STUDIO]**.

Files read in full: `StarterGui.CucumberMenus.{MenuController, MenuClient, ShopController, IndexView,
IndexController}`, `StarterGui.CucumberHUDDesign.{BaseHUDController, BaseHUDClient, HUDClient, SlowModeClient}`,
`ReplicatedStorage.Modules.{ButtonFX, Notify, NumberAbbrev}`, `_gui_tree.txt`, the relevant parts of
`EggHatchClient`, `PetHatchService`, `PetsCatalog`, `CucumberMutations`, `HotbarClient`, `PortalHudClient`,
`PlacedCucumberCardClient`, `BenchBonusClient`, `CucumberLiftClient`, `StrengthProgressionServer`, and the repo
builders `hud-shop/{build_shop.lua, build_hud.lua, install.lua}`, `build-mode/build_buildmenu.lua`,
`base-save/build_adminpanel.lua`.

---------------------------------------------------------------------------------------------------------

## 0. Contradictions / surprises vs PLAN.md (section 2 and related) and RULES.md

| # | PLAN / RULES says | Live code says | Consequence |
|---|---|---|---|
| C1 | PLAN §2: MenuController "Assumes a left-menu opener for every panel." | True (`MenuController` L91 `hud.LeftMenu[name]:WaitForChild("Open" .. name)`, **no timeout**). PLAN does not mention L102-104: `BaseMode` becoming true calls `show(nil)` and closes **every** panel. | A Pets panel would slam shut every time the player walks into their own plot. Needs a per-panel rule (only Shop/Index close on base entry). |
| C2 | PLAN §9: HUDClient "Wire the new Pets opener if not handled entirely by MenuController". | HUDClient owns only the Counters "+" (L185-201, writes `OpenRequest`). Shop/Index opener clicks + hover are owned by MenuController (L92-95). | MenuController should own the paw's `Activated` + hover. **No HUDClient edit needed.** Do not connect the paw in two scripts. |
| C3 | PLAN §2/§11: do not reuse Manage, "whose behavior already belongs to base management". | `LeftMenu.Manage.ManageButton` has **no click handler anywhere** in the live code (only the hover pop in BaseHUDController L234-241). There is an **unwired, unregistered `CucumberMenus.ManagePanel`** (tree L225-246) with attrs `DefaultTab=Pets`, `IntendedOpener=StarterGui.CucumberHUDDesign.LeftMenu.Manage.ManageButton`, `UIOnly=true`, plus `Tabs`, `Pages` and `Templates.PetRow` / `Templates.CucumberRow` (1044x102 rows). | Someone already mocked a pet list under Manage. Following the PLAN (separate Pets panel) means two pet UIs exist in the tree. Do not register, edit or delete ManagePanel; mention it in the handoff so the user can decide. Its PetRow may be a useful visual reference **[READ IN STUDIO]**. |
| C4 | PLAN §14 "Existing systems": "Slow Mode still sets WalkSpeed 16". | `StrengthProgressionServer` L26 `SLOW_MODE_SPEED=25`; `CucumberLiftClient` L570 literal 25 ("was 16, 2026-09-22"). | Regression tests must expect **25**, not 16. |
| C5 | RULES: "Never destroy `CucumberHUDDesign`'s TopStatus frame". | New Map's `CucumberHUDDesign` has **no TopStatus** (children: 4 scripts, `LeftMenu`, `Counters`, `NightTimer`; tree L10-151). The rule comes from Place1's `StarterGui.HUD` (memory hud-top-slot). The top-centre element here is `Counters`. | Nothing to preserve by that name; do not create one. Keep `Counters` untouched (PortalHudClient and BenchBonusClient lay out against it). |
| C6 | PLAN §11 "Match existing panel transitions" vs RULES "UI motion should be Heartbeat-stepped". | MenuController's open/close transitions **and** its hover pops use **TweenService** (`animate`, L15-21). BaseHUDController / ShopController / HUDClient pops use `ButtonFX.Animate` (Heartbeat). | Keep MenuController's tweens for consistency (PLAN says keep transition behaviour), but tests in an unfocused Studio must not rely on screenshots of the panel fading in: read `Content.Visible` / `OpenPanel` / text values, or wait for focus. New motion in PetView should use `ButtonFX.Animate`. |
| C7 | PLAN §11 hatch: "show inherited material/mutations on the revealed pet". | `EggHatchClient.BuildPet` (L366-383) never applies a look to the pet; only the egg gets `CucumberMutations.ApplyLook` (L348). | Add `pcall(CucumberMutations.ApplyLook, pet, info.Material, info.Mutations)` in BuildPet. |
| C8 | PLAN §8.3 step 8: update the three `Opened` paths (busy / watchdog / normal). | They are L515 (busy), L527 (watchdog), L537 (normal). The watchdog sets `Busy=false` but **not** `Token`, so if the reveal finishes after the 95 s watchdog, L535-537 fires `Opened` **a second time**. | Server must treat duplicate `Opened(token)` idempotently; client fix: bump `Token` in the watchdog. |
| C9 | PLAN §10 PetHatch payload. | Current `Begin` payload (`PetHatchService` L295-307): `EggName, EggKey, EggDisplayName, Scale, Material (may be nil), Mutations (comma STRING, "" when none), Pet, PetDisplayName, Rarity, Percent, Chance`. | UI must parse mutations with `CucumberMutations.Parse`, not expect an array. |
| C10 | "Cash HUD green". | `PlacedCucumberCardClient` L40-42: HUD cash green `65,235,20`, stroke `12,12,12`. The repo mirror `hud-shop/build_hud.lua` L24 still paints CashValue **gold** (255,200,60) and `hud-shop/*.lua` are **stale** vs live (diffed: MenuController lacks the 0.86 fit factor, transparent dimmer and BaseMode close; ShopController lacks the tab Outline + live-rescroll; HUDClient lacks the strength spring). | **Never re-run `hud-shop/install.lua`, `build_shop.lua` or `build_hud.lua`** - they would overwrite 2026-09-13/15/18 live work. Patch from `live-2026-09-22/` copies only. |
| C11 | Money format. | HUDClient's `Compact` (L41-54) floors everything below 1000 to an integer ("0" for 0.5). `NumberAbbrev.Abbrev` keeps up to 2 decimals below 1000 ("0.5", "3.75", "7.8"). | Pet rates/totals must use `NumberAbbrev.Abbrev`, never a copy of `Compact` - a $0.50/s Cucumber Deer would read "$0/s". |

---------------------------------------------------------------------------------------------------------

## 1. MenuController (`StarterGui.CucumberMenus.MenuController`, 150 lines, 4-space indent, no header comment)

`Controller.Start(gui, hud)` (L5) - `gui` = the PlayerGui copy of `CucumberMenus`, `hud` = `CucumberHUDDesign`.

- **Panel registration** L6: `local panels = {Shop = gui.ShopPanel.Content, Index = gui.IndexPanel.Content}` -
  direct indexing (errors if a panel is missing). A panel entry is the **`Content` CanvasGroup**; the outer
  Frame is reached as `panel.Parent`.
- `dimmer = gui.Dimmer` (L7). State: `connections, activeTweens, activeName, revision, destroyed` (L8-11).
- `animate(instance, duration, goals, style, direction)` L15-21: **TweenService**, one live tween per instance
  (cancels the previous one). Default Quad Out.
- **fit()** L23-32: for every registered panel: `design = panel.Parent.Size`; `width = max(1, design.X.Offset)`,
  `height = max(1, design.Y.Offset)`; `scale = min(1, (gui.AbsoluteSize.X - 32)/width, (gui.AbsoluteSize.Y - 44)/height) * 0.86`;
  `panel.Parent.ResponsiveScale.Scale = max(0.25, scale)`. Runs at Start (L128) and on `gui.AbsoluteSize`
  change (L109). **The outer frame's Size must be pure Offset (design px)** or the maths collapses.
  Edit-mode snapshot value 0.6634 (tree L161/174/226). Worked numbers for a 1140x735 design:
  1920x1080 (usable ~1920x1022) -> 0.86; phone 844x390 landscape (usable ~332 tall) -> 0.337.
- **show(name)** L33-71 (`name=nil` closes): ignores unknown names (L35); `revision += 1` token;
  `activeName = name`; **`gui:SetAttribute("OpenPanel", name or "")`** (L39).
  - opening panel (L41-49): if it was hidden -> `Position = (0.5,0.54)`, `GroupTransparency = 1`,
    `MotionScale.Scale = 0.9`; `Visible = true`; tween Position -> (0.5,0.5) + GroupTransparency -> 0 in 0.24 s
    (Quad Out); `MotionScale` -> 1 in 0.32 s (Back Out).
  - other visible panels (L50-56): tween to Position (0.5,0.53) + GroupTransparency 1 (0.16 s Quad In),
    MotionScale 0.94 (0.16 s); `Visible=false` after 0.17 s if still inactive (revision-guarded).
  - dimmer (L58-70): open -> `dimmer.Visible = true`, `BackgroundTransparency = 1` (transparent since a live
    edit: "Keep outside-click dismissal without darkening the game"); close -> after 0.18 s `dimmer.Visible=false`
    and every panel `Visible=false`.
  - Required children therefore: `<X>Panel` (Frame) > `ResponsiveScale` (UIScale) + `Content` (CanvasGroup) >
    `MotionScale` (UIScale) + `CloseButton` (GuiButton).
- **hover(button, target)** L74-87 (the "HoverScale" contract): `target = target or button`; `base =
  tonumber(target:GetAttribute("HoverBaseScale")) or 1`; reuses/creates a UIScale named **`HoverScale`** on
  `target`; MouseEnter -> `base*1.035` (0.12 s), MouseLeave -> `base` (0.12 s), InputBegan MouseButton1/Touch ->
  `base*0.97` (0.08 s), InputEnded -> `base` (0.1 s). TweenService.
- **Opener loop** L88-98: for each panel: `Visible=false`, `GroupTransparency=1`;
  `local opener = hud.LeftMenu[name]:WaitForChild("Open" .. name)` (L91, infinite wait);
  `opener.Activated` toggles (L92-94); `hover(opener, opener.Parent)` (L95 - the HoverScale lands on the
  **LeftMenu.Shop / LeftMenu.Index frame**, not on the TextButton); `panel.CloseButton.Activated -> show(nil)`
  (L96) + `hover(panel.CloseButton)` (L97).
- L99-101: every `GuiButton` in `gui:GetDescendants()` with attribute `PurchaseTemplate` gets `hover(item)`
  (only at Start - runtime-created cards are not covered).
- L102-104: **`hud` attribute `BaseMode` -> true closes whatever is open** (see C1).
- L105 dimmer `Activated` -> close; L106-108 `Escape` (not gameProcessed) closes.
- **OpenRequest hook** L110-126: `gui` attribute `OpenRequest = "<Panel>[:<Section>][#<nonce>]"`, parsed by
  `request:match("^(%a+):?([%w_]*)")` (letters-only panel name; `#n` is just a nonce so repeats re-fire);
  unknown panels ignored; a non-empty section is written to the **outer frame's** `RequestedTab` attribute
  (cleared to "" first, then set in `task.defer`); then `show(name)`. Works for `"Pets"` / `"Pets:Reserve#3"`
  unchanged once Pets is in `panels`.
- **api** L129-148: `Open(name, section)`, `Close()`, `Toggle(name)`, `GetOpenPanel()`, `Destroy()`
  (disconnects + cancels tweens).

## 2. MenuClient + the other CucumberMenus controllers

`MenuClient` (LocalScript, 6 lines, compact style, no header):
```lua
local playerGui=script.Parent.Parent
local hud=playerGui:WaitForChild("CucumberHUDDesign")
local menus=require(script.Parent.MenuController).Start(script.Parent,hud)
local index=require(script.Parent.IndexController).Start(script.Parent,menus)
local shop=require(script.Parent.ShopController).Start(script.Parent,menus)
script.Destroying:Connect(function() shop.Destroy();index.Destroy();menus.Destroy() end)
```
Controllers are `Start(gui, menus) -> {Destroy=...}`; MenuController.Start must not yield long (it gates the
others). Controllers learn "my panel opened" from `gui:GetAttributeChangedSignal("OpenPanel")`.

**IndexController** (54 lines): `open()` = `gui:GetAttribute("OpenPanel")=="Index"` (L13); `refresh` (L15-27)
invokes `Remotes.CucumberCollectionBook` (RemoteFunction) with a loading/dirty guard, shows
`view.Status("Loading your collection...")`, retries after 1 s on `data.Retry or not data.Ready`, error text
"Collection unavailable - reopen to retry"; refreshes on `Remotes.CucumberAdventure` payload Kind
`Records`/`BookChanged` (L31-33); `EquipReward.Activated` debounced 0.35 s -> `EquipCucumberCollection:FireServer`
(L35-40); **ContextActionService `BindAction("CucumberCollectionBook", ..., false, Enum.KeyCode.J, Enum.KeyCode.ButtonR3)`
-> `menus.Toggle("Index")`** (L41-45, passes while a TextBox is focused). Keys already used elsewhere: J/ButtonR3
(Index), Q/ButtonY (CucumberPlacementClient QuickPlace), E (prompts), R (rotate), X/ButtonB + ButtonA/ButtonR2
(lift), Backquote (hotbar grid), ButtonR2 (DesertHunt). **P and ButtonL3 are free** for a Pets toggle.

**IndexView** (119 lines): `View.Start(gui, previews)`; renders into `gui.IndexPanel.Content`
(`CucumberGrid` ScrollingFrame, `BiomeTabs` ScrollingFrame, `CollectionCount`, `CollectionProgress.Fill`,
`EquipReward` {LockIcon, Label, Gradient}, `Footer`, `BestLift`, `Header.Subtitle`). Cards = `gui.Templates.CucumberCard:Clone()`,
tabs = `gui.Templates.BiomeTab:Clone()`; **every render destroys and re-clones all cards** (L12-14, L77-90) -
fine for ~10 cucumbers, too heavy for a large pet inventory (PLAN asks for preview pooling).
Viewport recipe `addViewport` (L15-35): `ViewportFrame:ClearAllChildren()`, `WorldModel "PreviewWorld"`, model
clone `PivotTo(CFrame.Angles(0, math.rad(-18), 0))`, `GetBoundingBox`, `Camera "PreviewCamera"` FOV 32,
`distance = max(size.Y, size.X/(232/151), size.Z) * 1.95`,
`CFrame.lookAt(cf.Position + Vector3.new(.1,.18,1).Unit*distance, cf.Position)`, `vp.CurrentCamera = camera`.
Card colours (L66-84): see palette §9.

**ShopController** (239 lines, tabs, dated header): `Shop.Start(gui, menus)`; pills = descendants with
`PurchaseTemplate` (L81-92); `PromptProductPurchaseFinished` -> `ButtonFX.SUCCESS_SOUNDS` + `ButtonFX.Flash` +
`Notify.Success("Purchase complete!")` (L93-102); tabs from `TabRail` children with attr `Section` (L105-109),
tab scale via `TabScale` UIScale (Heartbeat, L116-127); `ScrollTo(section)` Heartbeat scroll (L142-163, note in
header L15-17: ScrollingFrame CanvasPosition / AbsoluteCanvasSize / AbsoluteWindowSize share screen-pixel space
under the panel UIScale, so no scale maths); `RequestedTab` listener (L182-185); re-select on
`OpenPanel=="Shop"` after 0.05 s (L206-213); dev hook `ShopPanel` attr `ShopDev = "tab:<Section>" | "buy:<n>"`
(L217-228). Returns `{Destroy, Select}`.

## 3. Panel instance structure (template for PetsPanel)

`CucumberMenus` ScreenGui: Enabled, **DisplayOrder 60**, IgnoreGuiInset false, attrs `OpenPanel`,
`CollectionIntegration`, `PurchaseIntegration` (tree L153). ResetOnSpawn **[READ IN STUDIO]** - write
PetController so it works either way (full `GetState` on Start, clean `Destroy`).

Children (tree L154-246): `MenuController, MenuClient, IndexView, IndexController, ShopController`,
`TextButton Dimmer` (S 1,1, V=false, Z=1), `ShopPanel`, `IndexPanel`, `Folder Templates`, `ManagePanel`.

Common shape (all three panels):
```
Frame <Name>Panel   S={0,1140,0,735} P={0.5,0,0.5,0} A=(0.5,0.5) Z=2 BackgroundTransparency 1
  UIScale ResponsiveScale            (written by fit())
  CanvasGroup Content S={1,0,1,0} P={0.5,0,0.5,0} A=(0.5,0.5) Visible=false (GroupTransparency 1)
    UIScale MotionScale
    ... art, Header, CloseButton ...
```
**IndexPanel.Content** (tree L175-200) - the closest look to copy (FredokaOne, blue-teal):
| child | class | size | position | Z |
|---|---|---|---|---|
| Shadow (1 child) | Frame | 1120x694 | 10,30 | 2 |
| Body (6 children **[READ IN STUDIO]**) | Frame | 1120x690 | 10,23 | 3 |
| Header (2 children: `Subtitle` + presumably `Title`) | ImageLabel `rbxassetid://75227340977908` (red ribbon) | 390x103 | 22,0 | 12 |
| CloseButton (3 children; Shop's are `Rectangle` 102086640822931, `Plate` 111663825325576, `X` frame > `X` 73973960226016) | ImageButton | 86x86, A (0.5,0.5) | 1082,55 | 30 |
| BiomeTabs | ScrollingFrame | 1076x60 | 31,143 | 8 |
| CollectionCount | TextLabel FredokaOne | 750x37 | 36,206 | 10 |
| CollectionProgress (4 children) | Frame | 1067x21 | 36,250 | 5 |
| CucumberGrid (8 children: layout etc.) | ScrollingFrame | 1080x340 | 30,287 | 5 |
| Footer / BestLift | TextLabel FredokaOne | 704x25 / 704x23 | 44,646 / 44,674 | 10 |
| EquipReward (7 children, attr Unlocked) | TextButton | 305x54 | 796,645 | 10 |
| RewardBar (3 children) | Frame | 1090x69 | 25,637 | 8 |

`ManagePanel.Content` repeats Shadow / Body / Header / CloseButton at the same rects plus `Tabs` (1076x60 at
31,143, Z 7) and `Pages` (1076x500 at 31,207, Z 7).

**ShopPanel.Content** (tree L162-172, built by `hud-shop/build_shop.lua`, since restyled live):
`Background` ImageLabel 75881657992560 969x686 at 106,47; `Header` ribbon 333x93 at 70,0 > `Title "SHOP"`
(BuilderSans ExtraBold, UIStroke 5 px `DARK_RED 118,0,0` Contextual); `ContentPanel` 917x590 at 133,109 (PINK
240,195,195, stroke 4 DARK_RED) > `Catalog` ScrollingFrame (Size (1,-40,1,-40) at 20,20, `AutomaticCanvasSize=Y`,
`CanvasSize=0`, `ScrollingDirection=Y`, `ScrollBarThickness=8`, `ScrollBarImageColor3=150,40,40`,
`ElasticBehavior=Never`, `UIListLayout "CatalogLayout"` padding 12); `TabRail` (tabs 93x91 centred at x 46);
`CloseButton` 86x86 A .5 at 1067,56 Z 30.

`CucumberMenus.Templates` (tree L201-224): `CucumberCard` Frame 254x244 V=false (Corners, UIStroke Border,
UIGradient Gradient, StudTexture 14905298636, Number, CucumberViewport 232x151 at 11,28, NamePlate 244x61 at 5,177,
CollectedCheck 43x43, InnerRim (1,-10,1,-10) at 5,5); `BiomeTab` TextButton 145x47 V=false (UICorner, UIStroke,
UIGradient Gradient, InnerRim.Border, Label FredokaOne).
**GuiObjects inside a Folder under a ScreenGui still render** - every template must be authored `Visible=false`.

## 4. HUD: `StarterGui.CucumberHUDDesign`

ScreenGui Enabled, **DisplayOrder 20**, IgnoreGuiInset false, attrs `BaseMode`, `BenchMode`, `Reference`,
`StrengthImageAssetId=15403007921`, `StudTextureAssetId=14905298664` (tree L10). Runtime attrs written by
scripts: `BaseMode`, `BenchMode` (BaseHUDController L186-187), `BuildMode` (BuildMenuClient L1142/1159),
dev: `BaseDev`, `HoverDev`, `HUDDev`.

### 4.1 LeftMenu (tree L15-121)
`Frame LeftMenu` **S={0.0938,0,0.154,0} P={0.009,0,0.47,0} A=(0,0.5)** Z=1 + `UIAspectRatioConstraint Proportions`
+ `UISizeConstraint SizeLimits` (**values [READ IN STUDIO]**: `Proportions.AspectRatio/DominantAxis`,
`SizeLimits.MinSize/MaxSize`, and the live `LeftMenu.AbsolutePosition/AbsoluteSize` at 2-3 viewport sizes).
Children, in LeftMenu-relative scale (W = LeftMenu width, H = height):

| child | Size | Position | row / notes |
|---|---|---|---|
| Shop | (1, 0.455) | (0, 0) | top row. `OpenShop` TextButton S 1,1 Z 30 on top; Label "Shop" (0.59x0.65 at 0.38,0.15, BuilderSansExtraBold, `TextOutline` stroke); CartIcon + 6 CartOutline copies (±1 px offsets = drawn outline) |
| Index | (1, 0.455) | (0, 0.545) | bottom row. `OpenIndex`; Label "Index"; BookIcon 114745649194031 (0.32x0.84 at 0.025,0.07) |
| Build | (1, 0.455) | (0, 0) | V=false authored, attr Placeholder. `BuildButton` (Z 30), frame-drawn `BuildIcon` (UIAspectRatioConstraint + `Hammer`) |
| Manage | (1, 0.455) | (0, 0.545) | V=false, Placeholder. `ManageButton`, frame-drawn `ManageIcon` (3 Rails + 3 Knobs, UICorner'd frames) |
| BenchStrength | (**1.35**, 0.48) | (0, 0.545) | V=false, attrs Multiplier=16, PriceRobux=49, ProductId=0; `OfferButton`, RainbowGradient fill, Sunburst rays (HUDClient L212-217), Title "x16 Strength" / Price "ONLY 49" FredokaOne, `UIScale ButtonScale` |
| SlowMode | (**1.4**, 0.29) | (0, **1.1**) | directly under the Index row (Index ends at 1.0). `Track` (0.44x1, Corners, Outline, `Thumb` 0.33x0.8), Label "Slow Mode" (0.49x0.72 at 0.5,0.14, FredokaOne, Outline), `Toggle` TextButton S 1,1 Z 5 |

Every slot button shell (Shop/Index/Build/Manage/BenchStrength): `UICorner Corners`, `UIStroke Outline`,
`Fill` (0.964x0.91 at 0.018,0.045, Z 3) > `Corners`, `UIGradient ColorGradient`, `StudTexture` ImageLabel
14905298636 (S 1,1, Z 4), `InnerHighlight` (0.966x0.91 at 0.017,0.045, Z 5, 2 children). Per the build-mode
README/builder this is "dark 12,12,12 rounded frame + 2 px outline, white Fill with a 90-deg gradient + stud
texture at 0.4 transparency, InnerHighlight stroke, BuilderSans ExtraBold label with a 2.5 px dark outline,
transparent press button on top" (`build-mode/build_buildmenu.lua` L4-6, `Shell()` L47-61). Exact Shop/Index
gradient colours **[READ IN STUDIO]** - or clone the shell (recommended, §8).

Vertical map of the column (in H): Shop/Build 0-0.455 | gap | Index/Manage/Bench 0.545-1.0 (bench to 1.025) |
gap | SlowMode 1.1-1.39. Horizontal: slots 0-1.0 W, BenchStrength to 1.35 W (row 2 only), SlowMode to 1.4 W.

### 4.2 BaseHUDController (Build/Manage swap) + BaseHUDClient
`BaseHUDClient` = `require(script.Parent.BaseHUDController).Start(script.Parent)` + Destroying cleanup (1 line).
`BaseHUDController` (270 lines, dated header L1-28):
- constants L37-48: `HIDE_SECONDS 0.16`, `SHOW_SECONDS 0.30`, `SHOW_DELAY 0.08`, `ROW_STAGGER 0.06`, `SLIDE 0.42`,
  `SHRINK 0.82`, `FADE_END 0.85`, `HOVER_SCALE 1.035`, `PRESS_SCALE 0.97`, `HOVER_SECONDS 0.12`;
  **`SLOTS = {Shop = 1, Build = 1, Index = 2, Manage = 2, BenchStrength = 2}`** (L47);
  `HOVERED = {Build = "BuildButton", Manage = "ManageButton"}` (L48).
- `Controller.Contains(plot, position)` L51-56: plot-local |X|,|Z| <= half size + 6, -10 < Y < 60.
- `Snapshot(button)` L59-77 records every Background/Image/Text/UIStroke transparency < 1; `Apply(state)`
  L81-94 drives **Size and Position directly** (presence p: size x `SHRINK+(1-SHRINK)p`, slides left by
  `SLIDE*(1-p)` of its width, fades, `Visible = p > 0.001`); `Move` L97-123 Heartbeat via `ButtonFX.Animate`,
  token-cancelled; on tuck it resets the button's `HoverScale.Scale = 1` (L117-120).
- `Start(hud)` L125: `menu:WaitForChild(name)` for every SLOTS key (L130-141, infinite wait).
- **`setMode(inside, onBench, building)`** L148-188, `wanted` L155-161:
  `Shop = not inside`, `Index = not inside and not onBench`, `Build = inside and not building`,
  `Manage = inside and not onBench and not building`, `BenchStrength = onBench and not building`
  (`building` only counts inside, L150). A slot whose occupant is leaving makes the newcomer wait
  `SHOW_DELAY` (L162-166); first mode after spawn is applied instantly (`settled`, L145/172).
  Publishes `hud:SetAttribute("BenchMode", onBench)` and `("BaseMode", inside)` (L186-187).
- `update()` L189-211: dev `BaseDev = "inside"|"bench"|"outside"`; bench = `Humanoid.SeatPart:GetAttribute("LiePose")==true`
  (L200); inside = an owned plot (`Owner == UserId`) containing the root. Runs on Heartbeat every 0.1 s (L242-247),
  `CharacterRemoving -> setMode(false)` (L248), `CharacterAdded`, `BaseDev`, `BuildMode` changes (L249-251).
- Build/Manage hover pop (Heartbeat) L214-241; dev `HoverDev = "hover:Build" | "leave:Manage" | "press:Build"` L252-262.

### 4.3 SlowModeClient (`StarterGui.CucumberHUDDesign.SlowModeClient`, 74 lines, 1-space indent, no header)
Row = `hud.LeftMenu.SlowMode` (L5); remote `ReplicatedStorage.Remotes.SetSlowMode` (created at runtime by
`StrengthProgressionServer` L8-11); `Refresh(instant)` L11-30 reads player attr `SlowMode`, sets row attr
`Enabled`, thumb X 0.62 (on) / 0.05 (off), track colour on `84,237,18` T 0.28 / off `65,84,49` T 0.4, 0.18 s
TweenService; `Toggle.Activated` debounced 0.2 s -> `remote:FireServer(not current)` (L31-37).
**Visibility** L53-55: `row.Visible = hud:GetAttribute("BuildMode") ~= true and not onBench`; bench = SeatPart
named `LieSeat` or under a model tagged `PlotBench` (L43-52, 2026-09-19 user request). Server speed 25 (C4).

### 4.4 HUDClient (217 lines)
Counters binding (`player.Data.Strength` / `Cash` NumberValues, L130-152), `Compact` L41-54 (see C11), `Pop`
L57-69 (`PopScale` UIScale, 1.18 -> 1, 0.28 s Back, Heartbeat), strength spring L71-128, bench-mode 1.1x
strength row L81-101, night timer L155-182 (`workspace` attrs `CyclePhase` Day/Night/PreparingDay +
`PhaseEndsAt` vs `workspace:GetServerTimeNow()`, every 0.2 s: "in 4m 43s" / "ends in 8s" / "dawn..." / "soon"),
the "+" L185-201 (`ButtonFX.Prepare(addStrength)` -> FXScale hovered with TweenService 1.08; press =
`ButtonFX.Press` + `menus:SetAttribute("OpenRequest", ("Shop:Strength#%d"):format(n))`), dev `HUDDev="plus"`
L203-209, bench rays L212-217.

### 4.5 Other screen rects (for placement checks)
- **Counters** (tree L122-141): S=(0.3,0,0.09,0) P=(0.5,0,0,14) A=(0.5,0) + Proportions + SizeLimits; StrengthIcon,
  StrengthValue (+PopScale), AddStrength "+" (`OpenStrengthShop`), CashIcon 15402858705, CashValue (+PopScale).
  PortalHudClient hides Counters during minigames and stacks its timer against them.
- **NightTimer (bottom-left night indicator)** (tree L142-151): S=(0.15,0,0.055,0) **P=(0.009,0,1,-12) A=(0,1)** +
  Proportions + SizeLimits; ~42 px tall in practice (memory 2026-09-12); moon image 240651261 (drawn outline = 4
  offset copies) + `TimeLabel` (0.74x0.74 at 0.265,0.12). Covered by BuildMenu (DO 25, IgnoreGuiInset) in build mode.
- **Hotbar** (`HotbarClient`, runtime ScreenGui `Hotbar`, DO 5, IgnoreGuiInset false): `Bar` A=(0.5,1)
  P=(0.5,0,1,-10), AutomaticSize X, slots `clamp(floor(viewportH*0.075), 44, 64)` px, gap 6, up to 10 slots + "+N"
  chip, overflow `Grid` and `Tooltip` above it (L25-43, L67-84). Disabled in build mode.
- **Notify** toasts: centre (0.5, 0.66) of the screen, DO 2000 (§6.2) - they draw over an open panel's lower part.
- Lift bar (`CucumberLiftClient` DO 900): bottom-centre (0.5,0.87) A (0.5,1). Admin panel: top-right. MinigameHUD
  DO 22: top-centre + above the hotbar. BenchBonusGui DO 30: floating circles (72-108 px) while on the bench.
- **DisplayOrder stack**: Hotbar 5 < CucumberHUDDesign 20 < MinigameHUD 22 < BuildMenu 25 < BenchBonusGui 30 <
  AdminPanel 40 < EggRevealUI 50 < **CucumberMenus 60** < lift 900 < GameNotify 2000 < HatchRevealGlow 9999.
  The transparent full-screen `Dimmer` (DO 60) therefore swallows clicks on the HUD, hotbar and world while any
  panel is open (first click anywhere outside the panel just closes it).

### 4.6 Free space for the paw "Pets" opener
To the right of the **top row** (Shop/Build slot, y 0-0.455 H, x >= 1.0 W) nothing is ever drawn: BenchStrength
(1.35 W) and SlowMode (1.4 W) extend right only in rows 2 and 3; the swap motion slides buttons LEFT; Counters is
top-centre, NightTimer bottom-left (far below: LeftMenu is centred at 47 % height, SlowMode ends ~0.47+0.154x0.89
≈ 61 % of the screen height before constraints), hotbar/lift bottom-centre, admin top-right. Placing the paw in
row 2/3 would collide with BenchStrength or SlowMode. On touch devices the dynamic thumbstick lives in the
lower-left quarter - the top row (~39-46 % height) stays above it; verify on the mobile preset.

## 5. EggRevealUI (hatch card) - where the stat line goes

`EggRevealUI` ScreenGui DO 50, **IgnoreGuiInset true** (tree L248-262): `SingleLayer` / `TripleLayer` full-screen
Frames, `ClickCatcher` TextButton (V=false) > `Prompt` (0.7x0.085 at 0.5,0.92 A 0.5,1, FredokaOne, UIStroke),
**`SingleTemplate`** Frame S=0 P=(0.5,0.5) A=(0.5,0.5) V=false with:
| child | Size | Position (A 0.5,0.5) | font | notes |
|---|---|---|---|---|
| PetName | (0.25, 0.093) | (0.5, 0.88) | GothamBlack | UIGradient = `PetsCatalog.RARITY_GRADIENTS[rarity]`, text upper-cased display name |
| PetRarity | (0.2, 0.035) | (0.5, 0.94) | GothamBlack | UIGradient, upper-cased rarity |
| PetUnlocked | (0.2, 0.035) | (0.5, 0.82) | GothamBlack | **always hidden** (`EggHatchClient` L405-406) |
| PetChance | (0.24, 0.05) | (0.655, 0.315) | FredokaOne | UIStroke `ChanceStroke`, "[1 in N]" from `info.Chance` |

`EggHatchClient.BuildCard(info)` L385-415 clones it as "Single", parents to SingleLayer and **TweenService**-grows
Size 0 -> (1,0,1,0) (1 s Back Out); `CardOut` L417-420 shrinks to 0 at (0.5,0.8). So child Scale positions are
fractions of the full screen. PetName's box spans y 0.8335-0.9265.
**Recommended stat line**: new `TextLabel PetStats` S=(0.42,0,0.036,0) P=(0.5,0,0.80,0) A=(0.5,0.5), FredokaOne,
TextScaled, RichText, white text + `UIStroke` 2.5 px `12,12,12` Contextual, default `Visible=false`; text e.g.
`<font color="#41EB14">$3.75/s</font>  ·  Lucky Harvest 8%/min` (`#41EB14` = 65,235,20; amounts via
`NumberAbbrev.Abbrev`; fighters "Fighter +15% dmg"). Optional `PetTraits` line S=(0.42,0,0.03,0) P=(0.5,0,0.762,0)
filled with `CucumberMutations.ColorizeName(...)` / `CucumberMutations.Font(word, color, true)` (the HotbarClient
tooltip idiom, HotbarClient L174-199). Author both in the template with a builder (convention: instances are
authored, scripts fill them) and keep BuildCard nil-safe (`FindFirstChild`, hide when the payload lacks stats).
Reveal side-effects: `HideUi` (L255-270) disables **every other PlayerGui layer** (incl. CucumberMenus and
`GameNotify`) and all CoreGui; `PlayerGui.ChildAdded` hides layers created meanwhile (L272-274) - **a Notify toast
fired during a reveal is invisible**; restore in `RestoreUi` (L276-289).

## 6. Shared modules (exact APIs)

### 6.1 `ReplicatedStorage.Modules.ButtonFX` (235 lines, client juice, sounds via SoundController.PlayFX)
- Constants: `PRESS_SOUND = {"Button Pop", 0.3}` (L30), `SUCCESS_SOUNDS = {{"Cash Register", 1.5}, {"Magic Shimmer", 1.2}}` (L31),
  `FAIL_SOUND = {"Error", 1.2}` (L32), `LEVEL_UP_COLOR 255,221,51`, `LEVEL_UP_STROKE 82,62,10`, `SPARK_COLOR`, `SPARK_COUNT 45`, `FLOAT_RISE 70`.
- `ButtonFX.Sound(entry)` (L43-47): `entry = {soundName, volume}`, keyed `"ButtonFX:"..name`, MinInterval 0.05.
- `ButtonFX.Animate(duration, style, direction, fn, alive?) -> boolean` (L50-60): **yields** (Heartbeat loop);
  calls `fn(TweenService:GetValue(t, style, direction))`; returns false if `alive()` turns false. Wrap in `task.spawn`.
- `ButtonFX.Prepare(gui) -> UIScale` (L63-78): one-time; **re-anchors the element to (0.5,0.5) and shifts its
  Position** to keep it visually in place, stores attr `FXBasePosition`, adds UIScale **`FXScale`**.
- `ButtonFX.PopSequence(gui, steps)` (L81-97): `steps = {{targetScale, seconds, style?, direction?}, ...}`, token attr `FXToken`.
- `ButtonFX.Flash(gui, color, peakTransparency, duration)` (L100-118): child Frame `FXFlash` (ZIndex +5, copies the UICorner).
- `ButtonFX.Press(button)` (L120-127): press sound + 0.9 (0.05 s) -> 1.07 (0.1 s Back Out) -> 1 (0.1 s).
- `ButtonFX.Success(button)` (L129-136): success sounds + white flash (0.15 -> 1 over 0.4 s) + 1.18 (0.12 s Back) -> 1 (0.2 s).
- `ButtonFX.Fail(button)` (L138-152): Error sound + red `255,70,70` flash (0.55, 0.35 s) + 0.35 s horizontal shake,
  7 px amplitude, 3 cycles, around `FXBasePosition` (attr `FXShake` token). Calls Prepare.
- `ButtonFX.WorldBurst(board)`, `ButtonFX.FloatText(levelLabel, text)`, `ButtonFX.Celebrate(board, levelLabel, text)` (boards only).

### 6.2 `ReplicatedStorage.Modules.Notify` (230 lines; client only - `Show` returns early on the server, L176)
- `Notify.Show(text, color?, seconds?)` (L175-210), `Notify.Error / Warn / Success / Info(text, seconds?)` (L212-215),
  `Notify.Label()` newest label, `Notify.Labels()` all (tests).
- `Notify.COLORS`: Error `240,58,58`, Warn `255,160,60`, Success `92,225,92`, Info `255,226,120` (L36-41).
- Look: ScreenGui `GameNotify` (DO 2000, IgnoreGuiInset, ResetOnSpawn false), FredokaOne, TextScaled, width 0.92,
  height 0.15, text capped at 7.5 % of the screen height / 64 px, stroke = text colour x0.22, 10 % of the text
  height (2-6 px), newest at (0.5, 0.66), stack of 3 (`MAX_STACK`), `HOLD 2.0` s, `FADE 0.35`, pop 0.7 -> 1.

### 6.3 `ReplicatedStorage.Modules.NumberAbbrev` (61 lines)
- `NumberAbbrev.Abbrev(n) -> string` (L46-59): nil/NaN -> "0"; negative -> "-" .. Abbrev(-n); `math.huge` -> "inf";
  `< 999.5` -> up to 3 significant digits, trailing zeros trimmed (`>=100` integer rounded, `>=10` one decimal,
  else two decimals): 0.5 -> "0.5", 3.75 -> "3.75", 7.8 -> "7.8", 12.5 -> "12.5"; else mantissa + suffix,
  `999999 -> "1M"` roll-over: 1200000 -> "1.2M", 15728640 -> "15.7M", 5.4e12 -> "5.4T".
- `NumberAbbrev.SUFFIXES` (L15-27): K, M, B, T, Qa, Qi, Sx, Sp, Oc, No, Dc ... Vg ... Ce (index = power of 1000).
- Cash display convention: `"$" .. NumberAbbrev.Abbrev(x) .. "/s"` and `"+$" .. Abbrev(x)` (PlacedCucumberCardClient).

### 6.4 Pet / mutation display helpers already live
- `PetsCatalog.RARITY_GRADIENTS` (L176-185), `RARITY_GLOW` (L186-195), `RARITY_ORDER` (L196, Common 1 .. Mythical 6),
  `RarityOf(pet)`, `DisplayNameOf(pet)`, `ModelOf(pet)` -> `ReplicatedStorage.Assets.Pets[pet]` (L248-274), `ChanceText`.
- `CucumberMutations.MUTATIONS[i].Color` (L36-45), `MATERIALS.Golden.Color 255,200,30`, `Diamond 200,245,255` (L46-49),
  `Parse(str)` (L94, splits on commas/whitespace), `ColorOf(word)` (L240), `TextColor(c)` (lifts dark SHADOW/VOID, L253),
  `Hex(c)`, `Font(text, color, bold)` (RichText span, L268), `ColorizeName(name)` (L275), `ApplyLook(model, material, mutations, opts)` (L320).

## 7. GUI-authoring conventions (from the repo builders)

- **Builders are edit-mode Luau chunks run once through `execute_luau`**, idempotent, header comment block
  explaining what they build; "every instance is AUTHORED here (nothing is generated at runtime); <Controller>
  only wires ..." (`build_shop.lua` L1-9, `build_buildmenu.lua` L1-12). Sources can take the client script source as
  the chunk vararg (`build_hud.lua` L10, `build_buildmenu.lua` L13).
- Helper shape (`build_shop.lua` L59-92): `make(class, name, parent, props)` that defaults GuiObjects to
  `BorderSizePixel=0, BackgroundTransparency=1, BackgroundColor3=WHITE`, `ScaleType=Fit` on images,
  `AutoButtonColor=false` on buttons, `Text=""`/white on text; `stroke(parent, thickness, color, mode)` (UIStroke
  named "UIStroke"; Border default, Contextual for text); `label(name, parent, text, font, props)` (TextScaled);
  `gradient(parent, rotation, stops)`; `off(w, h) = UDim2.fromOffset`. `build_buildmenu.lua` names strokes
  `Outline` / `TextOutline`, corners `Corners`, uses `UITextSizeConstraint "SizeCap"` (MinTextSize 8).
- Idempotence pattern (`build_shop.lua` L219-236): fix the outer frame (Size offset, centred), add
  `ResponsiveScale` if missing, recreate `Content` as a CanvasGroup if it is not one, **destroy every Content child
  except `MotionScale`**, then `Content.Visible=false`, `GroupTransparency=1`, `BackgroundTransparency=1`; set a
  `Reference` attribute naming the builder; `print` an instance count.
- Design sizes are Offset pixels in a fixed canvas (1140x735 for menus) and fitted by `MenuController.fit`.
  HUD elements use Scale + `UIAspectRatioConstraint "Proportions"` + `UISizeConstraint "SizeLimits"`. Runtime-built
  pixel UIs (Hotbar, BuildMenu, lift) compute px from the viewport (`Fit`).
- Icons with no art are **frame-drawn** (BuildIcon.Hammer, ManageIcon rails/knobs, the Grid glyph): Frames with
  UICorner(1,0) circles + UIStroke. No paw image exists in the repo -> draw the paw the same way (one pad + 4 toes).
- Text outlines: UIStroke `ApplyStrokeMode = Contextual`; frame borders: `Border`. Button press area: a
  transparent full-size TextButton on top (Z 30) named `Open<Panel>` / `<X>Button` / `Press`.

## 8. Recommendations

### 8.1 The paw opener (HUD) - `CucumberHUDDesign.LeftMenu.Pets`
Recommended placement: a **direct child of `LeftMenu`** named `Pets` in the top row, to the right of Shop/Build:
- `Frame Pets` Position `(1.07, 0, 0, 0)`, Size `(0.455 * H/W, 0, 0.455, 0)` → simplest: Size `(1, 0, 0.455, 0)` plus
  a child `UIAspectRatioConstraint "Square"` (AspectRatio 1, DominantAxis Height) so it is a square of the slot
  height; ZIndex 2. Being inside LeftMenu it inherits the menu's aspect/size constraints on every screen.
- Shell: **clone `LeftMenu.Index`** (Corners, Outline, Fill{Corners, ColorGradient, StudTexture, InnerHighlight})
  and delete `BookIcon`, `Label`, `OpenIndex`; retint `Fill.ColorGradient` to a distinct pet colour from the
  existing palette, e.g. the admin/BuildCatalog gold `255,220,90 -> 240,170,20` with highlight `255,240,170`
  (or keep Index's). Add a frame-drawn `PawIcon` (UIAspectRatioConstraint 1; `Pad` ellipse + `Toe1..Toe4` circles,
  white fill + 2 px `12,12,12` stroke) on the upper ~62 %, a `Label` "Pets" (BuilderSans ExtraBold, `TextOutline`
  2.5 px dark, like Shop/Index) on the lower ~32 %, and a transparent **`TextButton OpenPets`** S 1,1 Z 30.
- Do **not** call `ButtonFX.Prepare` on `LeftMenu.Pets` (it re-anchors/moves the frame and adds `FXScale`, and
  MenuController's `HoverScale` + BaseHUDController's Size/Position driving already own it; two UIScales do not stack).
- Visibility: hide in build mode and (matching Slow Mode's 2026-09-19 rule) while lying on the bench; visible in
  and out of the base. Best done by BaseHUDController (it already animates tuck/return): see 8.4.
- Fallback option if LeftMenu parenting is rejected: a sibling Frame `CucumberHUDDesign.Utility` positioned from
  `LeftMenu.AbsolutePosition/AbsoluteSize` each resize - more code, same visual result.

### 8.2 MenuController edits (exact)
1. Top of module (after `local Controller = {}`), dated comment:
   ```lua
   -- 2026-09-22 (pets): panel -> opener paths are explicit; the Pets paw sits beside the left menu and is
   -- optional, so a missing PetsPanel or paw never blocks Shop / Index
   local OPENERS = {
       Shop = {"LeftMenu", "Shop", "OpenShop"},
       Index = {"LeftMenu", "Index", "OpenIndex"},
       Pets = {"LeftMenu", "Pets", "OpenPets"},
   }
   local OPTIONAL = {Pets = true}
   local CLOSE_ON_BASE = {Shop = true, Index = true} -- their openers tuck away inside the base
   ```
2. L6: keep Shop/Index; add `local petsPanel = gui:FindFirstChild("PetsPanel")`
   `if petsPanel and petsPanel:FindFirstChild("Content") then panels.Pets = petsPanel.Content end`.
3. Replace L91-95 with a resolver that walks `OPENERS[name]` from `hud`; for OPTIONAL panels use
   `WaitForChild(part, 10)` inside `task.spawn` (so Start never stalls) and `warn` + skip on nil; keep
   `connect(opener.Activated, toggle)` and `hover(opener, opener.Parent)` exactly as now. Write the timeout choice
   with an explicit `if OPTIONAL[name] then ... else ... end` - NOT `a and b or c` (a nil `WaitForChild(part, 10)`
   would fall through to the infinite wait).
4. L102-104: `if hud:GetAttribute("BaseMode") and activeName and CLOSE_ON_BASE[activeName] then show(nil) end`.
5. Optional: close on `hud` attribute `BuildMode` becoming true (build mode can start from the E prompt while a
   panel is open - the dimmer blocks mouse clicks but not the prompt key).
6. Optional (phones): per-panel margin, `local margin = tonumber(panel.Parent:GetAttribute("FitMargin")) or 0.86`
   in `fit()` L29, with `PetsPanel` attribute `FitMargin = 0.95` - Shop/Index unchanged.
   fit/show/OpenRequest/api need no other change; `"Pets"` passes the `%a+` pattern.

### 8.3 MenuClient edit
Start Pets **last** and guarded so a pet-UI failure never breaks Shop/Index:
```lua
local pets
local petModule=script.Parent:FindFirstChild("PetController")
if petModule then
 local ok,result=pcall(function() return require(petModule).Start(script.Parent,menus) end)
 if ok then pets=result else warn("[MenuClient] PetController: "..tostring(result)) end
end
script.Destroying:Connect(function() if pets then pets.Destroy() end;shop.Destroy();index.Destroy();menus.Destroy() end)
```
`PetController.Start(gui, menus)` must return quickly (wait for `Remotes.PetState`/`PetRequest` inside `task.spawn`
with a timeout and show "Pets unavailable" on failure) and return `{Destroy=...}`.

### 8.4 BaseHUDController edit (only if the paw lives in LeftMenu)
- L47: `SLOTS = {..., Pets = 1}` (top-row timing); L130-141: resolve `Pets` with `menu:FindFirstChild("Pets")` and skip
  the state when absent (explicit if, no `and/or`), keep `WaitForChild` for the original five.
- `wanted` L155-161: `Pets = not building and not onBench`. Apply/Move/Snapshot/hover-reset then just work
  (slides left 42 % of its width while tucking, resets `HoverScale` on tuck). Do not add Pets to `HOVERED`
  (MenuController owns its hover). Add a dated header paragraph.
- Alternative without touching BaseHUDController: PetController hides the paw from `hud` attrs `BuildMode` /
  `BenchMode` with its own `ButtonFX.Animate` fade (but then the motion differs from the other buttons).

### 8.5 PetsPanel builder (`pets-system/src/build_petspanel.lua`, edit-mode, idempotent)
Creates/refreshes `StarterGui.CucumberMenus.PetsPanel` only (never touches ShopPanel / IndexPanel / ManagePanel;
cloning their art read-only is fine), plus the paw in `CucumberHUDDesign.LeftMenu.Pets` and the two EggRevealUI
labels. Proposed tree (design px, 1140x735):
```
Frame PetsPanel  S=off(1140,735) P=(0.5,0.5) A=(0.5,0.5) Z=2 BackgroundTransparency 1
  @Reference = "Pets panel; built by pets-system/src/build_petspanel.lua; PetView/PetController wire it"
  @FitMargin = 0.95 (only if 8.2.6 is adopted)
  UIScale ResponsiveScale
  CanvasGroup Content  S=(1,1) P=(0.5,0.5) A=(0.5,0.5) Visible=false GroupTransparency=1
    UIScale MotionScale
    Shadow, Body          <- clones of IndexPanel.Content.Shadow / .Body (inspect Body's 6 children first)
    Header                <- clone of IndexPanel.Content.Header; Title "PETS", Subtitle "0 / 6 ACTIVE"
    CloseButton           <- clone of IndexPanel.Content.CloseButton (86x86, A .5, at 1082,55, Z 30)
    Frame SlotRow         at (36,132) 1068x112: UIListLayout Horizontal Padding 14; Slot1..Slot6 (166x112)
    Frame Toolbar         at (36,254) 1068x48: Sort{Income,Combat,Rarity,Newest} Filter{All,Active,Reserve}
                          BestIncome / BestCombat (EquipReward-style green 149,255,70 -> 63,204,28)
    ScrollingFrame PetGrid at (30,312) 650x316: UIGridLayout CellSize 200x228, CellPadding 10x12,
                          FillDirectionMaxCells 3, UIPadding 6, AutomaticCanvasSize Y, CanvasSize 0,
                          ScrollingDirection Y, ScrollBarThickness 8, ElasticBehavior Never; Empty label
    Frame Details         at (694,312) 410x316: ViewportFrame Preview, Name, Rarity, Traits (RichText),
                          CashLine (green), CombatLine, AbilityName, AbilityEffect, AbilityChance,
                          NextRoll / "Fighter: +15% damage", TextButton EquipButton 300x54
    Frame Footer          at (36,640) 1068x56: PetCash, CucumberCash, TotalCash (green, FredokaOne)
    TextLabel LockBanner  ("Finish defending your plot to change pets.", Warn orange), Visible=false
    TextLabel Status      (loading / error line), Visible=false
  Folder Templates        PetCard (200x228), SlotCard (166x112), Chip - all Visible=false
```
Fonts FredokaOne (Index look), outlines UIStroke Contextual `12,12,12` or darkened colour; rarity accents from
`PetsCatalog.RARITY_GRADIENTS`; chips from `CucumberMutations.ColorOf` / `TextColor`. Minimum text height about
30 design px (≈ 10-11 px at a 0.34 phone fit) - the whole canvas is uniformly scaled, so small text dies on
phones; consider a compact mode in PetView when `ResponsiveScale.Scale < 0.5` (Details as an overlay over the
grid, 2 bigger grid columns). Gamepad: `Selectable=true` on cards/buttons, `GuiService.SelectedObject` set on
open when `UserInputService.GamepadEnabled`; optional `ContextActionService` toggle on P / ButtonL3.
PetView should pool cards/ViewportFrames by PetId (IndexView's destroy-and-reclone is O(n) ViewportFrame builds per
render) and build previews only for rows near the viewport; hover/press pops on its own buttons with a
Heartbeat `ButtonFX.Animate` UIScale (MenuController hovers only openers, CloseButtons and PurchaseTemplate buttons
that exist at Start). Studio-only dev hook (`RunService:IsStudio()`), e.g. PetsPanel attr `PetsDev`.

---------------------------------------------------------------------------------------------------------

## 9. Palette, fonts, strokes (live values)

- HUD shell: dark `12,12,12` frame + 2 px Outline; green fill `157,255,36 -> 69,255,0`, highlight `208,255,106`
  (build_buildmenu/adminpanel `GREEN_*`); gold `255,220,90 -> 240,170,20` / `255,240,170`; night `120,140,255 ->
  55,70,200`; red `255,100,100 -> 230,30,30`; stud texture `rbxassetid://14905298636` at 0.4.
- Cash: green `65,235,20` + stroke `12,12,12` (PlacedCucumberCardClient L41-42); no cash icon on world UI.
- Index: tab active gradient `15,224,255 -> 0,170,240`, rim `128,245,255`; inactive `146,177,207 -> 74,113,148`,
  rim `184,213,238`; nameplate collected `23,222,158 -> 0,154,101` (rim `63,247,176`), not `113,157,190 -> 64,102,137`
  (rim `146,185,205`); EquipReward unlocked `149,255,70 -> 63,204,28`, locked `149,172,180 -> 104,130,143` (IndexView L66-84).
- Shop: `DARK_RED 118,0,0`, `PINK 240,195,195`, `GOLD 255,220,80`, section header stroke `90,30,10`, tab outline
  `45,43,25` 3 px, scroll bar `150,40,40`, Robux pill gradient `255,230,130 -> 255,128,0`.
- Slow Mode on `84,237,18` / off `65,84,49`. Notify palette §6.2. ButtonFX level-up gold `255,221,51` / `82,62,10`.
- Rarity: `PetsCatalog.RARITY_GRADIENTS` / `RARITY_GLOW` (Common white→mint, Uncommon lime→teal, Rare cyan→blue,
  Legendary yellow→amber, Mythical pink→sky). Mutation colours: `CucumberMutations.MUTATIONS[i].Color`.
- Fonts: FredokaOne (Index texts, Slow Mode, Notify, world cards, bench offer, EggReveal chance/prompt);
  BuilderSans ExtraBold (LeftMenu labels, Shop title, build menu); Montserrat Bold/ExtraBold (shop card amounts);
  GothamBlack (EggReveal name/rarity); Counters/NightTimer use a custom FontFace (tree "F=Unknown").
- Strokes: text = UIStroke Contextual (2-3 px on panel text, 2.5 px `TextOutline` on HUD labels, 2.4 px world cards,
  3 px `20,20,26` minigame, 4 px ButtonFX float); frames = Border (2 px HUD outline, 4 px shop pills/panel,
  1.5 px `InnerHighlight`). Notify strokes = text colour x0.22.
