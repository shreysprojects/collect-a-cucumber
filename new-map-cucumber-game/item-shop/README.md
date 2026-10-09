# Item Shop + shop-cart displays (2026-09-23)

User: "1. Make the buy shop model include headbands and make it kind of display the thing its selling via
blender mcp. 2. Make the sell shop model into a buy stand (replace the sell text, keep it the same green theme
and all) and make it display the potions and boosts that we made. In our new models lets avoid using decals
like its being used currently, just display physical stuff. Make opening prompt on new buy shop model open
the second buy shop UI (the grow a garden style one). For the second buy shop make it hold all the boosts,
script every part of the UI, buying boosts, etc. Each boost very rare. Have a percent chance under each model
viewport like [1 in 10000] which is the chance that it would be in stock, make some boosts [1 in 100] then
other stuff like [1 in 10000+]."

Place: New Map Cucumber Game (87967102884366). NOT saved / published by me.

## What is in the place now
* `Workspace.Map.Lobby.Shops["Item Shop"]` (was "Sell Shop"): the green cart. SELL -> BUY letters (clones of
  the Buy Shop's B / U / Y RenderMeshes in the cart green 58,125,21), "BUY HERE!" A-frame, side board reads
  "POTIONS / BOOSTS" in stroke-letter Parts with a mini flask + a mini bolt, a MiniFlask on the A-frame where
  the two image guis were. On the counter: `ItemStand` (wooden riser + tray, 9 pedestals) and `ItemDisplay`
  = the nine `RS.Assets.Items` models cloned at x1.5 (back row Speed / Strength / Cash Potion, Holy Water,
  Warp Pearl; front row Golden Seed, Void Seed, Zombie Egg, Redemption Token, left to right for a customer).
  `ItemShopService` adds `ItemShopAnchor` + ProximityPrompt ("Open" / "Item Shop") 2 studs in front of the
  counter at runtime; Triggered -> `Remotes.OpenItemShop` -> the client opens the panel.
* `Workspace.Map.Lobby.Shops["Buy Shop"]` (headbands, HeadbandService's booth, unchanged name): `HeadbandRack`
  (wooden riser + board, 12 mannequin busts) and `HeadbandDisplay` = the 12 `RS.Assets.Headbands` models on
  the heads (tiers 1-6 front row, 7-12 on the riser, left to right for a customer); a MiniBolt replaces the
  Bolt image gui on its A-frame.
* Both carts: the Circle Light's decal cylinder (GradientRingCyl decals on a transparent RenderMesh) is gone;
  the floor disc, neon kerb ring and PointLight stay. ZERO Decal / Texture / ImageLabel instances remain
  under Lobby.Shops.
* Parked originals (cucumbers, slice trays, counter pets, SELL letters, CUCUMBERS/PETS letters, emoji + image
  gui parts, decal cylinders): `ServerStorage.__ShopGoods_2026_09_23.{ItemShop,BuyShop}`; full backups
  `backups/NewMap_LobbyShops_before-buy-stands_2026-09-23.rbxm` + `backups/NewMap_CucumberMenus_before-buyshop_2026-09-23.rbxm`.

## Scripts (`src/`, staged copies in `stage/`, installed through `stage/install_new.lua` + `pets-remake/serve.ps1`)
| Instance | What |
|---|---|
| `RS.Modules.ItemShopCatalog` (new) | ITEMS {Key, Price, Chance, Stock{Min,Max}, Type}, RESTOCK_SECONDS 300, DEV_CHANCE_DIV, ChanceText ("1 in 25K"), PriceText ("$2.5K") |
| `SSS.ItemShopService` (new) | one shelf per server: every restock each item rolls 1 in Chance (Stock.Min..Max units) else sold out; state = attributes on `Remotes.ItemShop` (Stock JSON / NextRestockAt / Restocks); `("Buy", key)` takes the Cash (DataService), gives via `ServerStorage.ItemAPI.Give`, refunds on failure; the cart prompt; Studio hook `Remotes.ItemShop` attr `ItemShopDev` = restock / stockall[:n] / stock:<Key>:<n> / clear / cash:<n> |
| `StarterGui.CucumberMenus.ItemShopController` (new) | rebuilds `BuyShopPanel.Content.ItemList` from `Templates.InStockItem` per catalog item (name / type / price / viewport picture / "1 in N" label under the picture), in-stock vs sold-out looks copied from the two templates, restock countdown, unaffordable price tint, BUY -> InvokeServer + sounds / flash / Notify toasts, `Remotes.OpenItemShop` -> `OpenRequest "BuyShop"`; hook `BuyShopPanel` attr `ItemShopDev` = open / close / buy:<Key> |
| `StarterGui.CucumberMenus.MenuController` (patched) | `panels.BuyShop = BuyShopPanel.Content`; a panel with no OPENERS entry is wired for close / dimmer / Escape / OpenRequest only |
| `StarterGui.CucumberMenus.MenuClient` (patched) | starts ItemShopController (pcall-guarded) |

Prices / chances (catalog): Speed Potion $2.5K 1 in 100 (3-12), Strength Potion $5K 1 in 100 (2-8), Cash Potion
$7.5K 1 in 150 (2-6), Warp Pearl $15K 1 in 250 (1-5), Holy Water $25K 1 in 500 (1-4), Golden Seed $50K 1 in 5K
(1-2), Void Seed $100K 1 in 25K (1), Zombie Egg $250K 1 in 10K (1), Redemption Token $500K 1 in 1K (1-2).
At these odds a shelf is usually empty ("restock #1: nothing in stock" is normal); tune `Chance` in the catalog
or set `DEV_CHANCE_DIV` for Studio.

## Fixtures (`blender/`)
`build_stands.py` (+ `run_stands.py`, headless: `blender.exe -b --python run_stands.py [-- Key]`) builds
ItemStand / HeadbandRack / ItemSign / MiniFlask / MiniBolt from itemlib PRIMITIVES ONLY (no asset upload:
no Open Cloud key on this machine) -> `blender/out/<Key>.parts.json` (+ slots / heads lists) and
`blender/renders/*.png`; `stage/install_stands.lua` rebuilds them as Parts, edits the carts and clones the
items / headbands onto the slots. The live Blender window belonged to the RAS session, so the build ran
headless in a fresh scene (same pipeline as `items/`). Stroke font: 3x5-grid bar glyphs (`GLYPHS`); a viewer in
front of a fixture sees model +X on their LEFT, so `stroke_text` lays glyphs out from +X to -X (the render at
yaw 0 proved the reading order). Cart frame: the big UnionOperation shell's local +Z is the customer side
(+X world for both carts), counter top = floor + 3.0, usable counter about 15 x 5.5 studs under an 8-stud roof.

## Verified (solo playtest on the isolated PetTest profile, 2026-09-23)
service booted (restock #1 nothing in stock at live odds, prompt at 1162.5, -225.8, 41.3 = 2 studs in front of
the counter); 9 live rows with '1 in 100' .. '1 in 25K' labels under the pictures, sold-out look, timer 04:57
counting, subtitle / 9 ITEMS; `OpenItemShop:FireClient` opened the panel (OpenPanel = BuyShop); after
`stockall` every row flipped to the in-stock look; buy Speed Potion: stock 12 -> 11, hotbar x10 -> x11, server
log "bought SpeedPotion for $2.5K (11 left)"; buy Zombie Egg (1 in stock): row flipped to Sold out / NO STOCK,
a second buy answered "Zombie Egg is sold out", an unknown key "Unknown item"; screenshots of both carts and
the open panel taken in play mode.
