# Fun builds: asset sources (2026-09-24)

This file lists every id in `fun-builds/src/FunAssets.lua`. It was researched with Creator Store search and asset
details, then load-checked in the edit data model of **New Map Cucumber Game** (place 87967102884366). The only
Studio change was a temporary folder, `ServerStorage.__FunAssetProbe`, and it was destroyed afterwards. No playtest was
run.

## How each asset was verified
* **Sounds:** a `Sound` in the probe folder, then `ContentProvider:PreloadAsync` returned `Success`, then
  `Sound.TimeLength > 0` within 5 s. Creator and title come from `MarketplaceService:GetProductInfo`.
  * One-shots were also played through an `AudioPlayer -> Wire -> AudioAnalyzer` chain that was never wired to an
    output, so nothing was audible. The peak envelope, sampled every 0.05 s, confirmed that the sound starts at once
    and doesn't clip. Rejected on that check: two static clips (0.7 s lead-in), one clock bell (clipped at full scale),
    one metal can (very loud clanging), and two TV on/off takes (near-silent).
  * The piano note's pitch was measured with `AudioAnalyzer:GetSpectrum()`, whose bins are 46.875 Hz wide
    (512 bins up to 24 kHz). The fundamental is 261-262 Hz, with harmonics at 522 and 1046 Hz, so it is C4 and
    `PianoRootHz` = 261.63. Two uploads labelled "C4" measured as C5 and were rejected.
* **Videos:** a `VideoFrame` in a ScreenGui. `IsLoaded` became true with `Resolution` 1280x720 in edit mode.
* **Images:** each decal id was resolved to its image id with `InsertService:LoadAsset` (the Decal's `Texture`), then
  the model was destroyed. The image id has AssetTypeId 1 and an `ImageLabel` preload returned `Success`. Every
  picture's thumbnail was looked at for family-friendliness and to confirm what it shows.

**Licensing:**
* **ProSoundEffects** (PSE), **APMOfficial** (APM Music), **DistrokidOfficial** and **Roblox** assets are licensed for
  use in any experience.
* The other sounds are public Creator Store uploads that load in this place.
* The paintings are public-domain works (artists who died before 1930). NASA/ESA space imagery is public domain.
  - "Lake", "Red Panda" and "Earth from Space" (uploader MichaelIsGr8) are marked CC0 by the uploader.
  - "Unsplash Mountain" is an Unsplash-licence photo.
  - The other nature, animal and food pictures are community decals. Their copyright status is unknown, but they
    passed Roblox moderation. Swap them if that matters.

## Sfx

| Key | Id | Title | Creator | Length | Verified | Notes |
|---|---|---|---|---|---|---|
| Boing | 6075441854 | Cartoon Spring Bounce Sound | MysteryMilo | 1.29 s | yes | "free spring sound for jump pads"; attack at 0.05 s |
| Creak | 9120839174 | Wood Door Creak Squeak 3 (SFX) | ProSoundEffects | 1.39 s | yes | |
| Whee | 9119197913 | Slide Whistle 2 (SFX) | ProSoundEffects | 1.35 s | yes | same id the "Slide Whistle" library sound uses |
| Thump | 9113535217 | Body Slam Low End Thump 2 (SFX) | ProSoundEffects | 1.18 s | yes | NEW key (Seesaw wish) |
| Splash | 9117823374 | Pool Jumps Splashes Water Impact Swimming 4 (SFX) | ProSoundEffects | 2.27 s | yes | |
| Crickets | 9112764546 | Crickets Night 1 (SFX) | ProSoundEffects | 36.0 s | yes | loop; faint distant traffic |
| Caw | 9118067220 | Raven 13 (SFX) | ProSoundEffects | 0.69 s | yes | NEW key (Scarecrow wish) |
| Rustle | 9114576499 | Giant Leaves 7 (SFX) | ProSoundEffects | 2.22 s | yes | NEW key (Bush wish) |
| Cheer | 1841221347 | Yeah (children's voices) | APMOfficial | 2.89 s | yes | replaces "Crowd Cheer" = PSE "Wrestling Crowd" (has boos) |
| Whoosh | 9126229255 | Whoosh By Fast Airy Swooshing Whipping Thuds (SFX) | ProSoundEffects | 1.02 s | yes | same id as library "Whoosh" |
| Zap | 116624744040072 | sfx_spark_explosion | zhasboss | 2.46 s | yes | same id as library "Zap" |
| Sparkle | 3199238931 | Pick_up_gem | thienbao2109 | 2.11 s | yes | same id as library "Magic Shimmer" |
| Click | 15675059323 | Roblox_UI_Bright_Click | Roblox | 0.37 s | yes | |
| TVOn | 9119973992 | Television Turn On And Off 2 (SFX) | ProSoundEffects | 6.70 s | yes | power-on pop at 0.1-0.2 s; faint tick at 5.3 s |
| TVOff | 78535264432518 | Old tv turn off | SnatchedOwl | 0.69 s | yes | |
| TVStatic | 96891705634188 | Tv screen static noise | Eight47284 | 2.10 s | yes | static from t = 0 (the TV plays it for 0.4 s) |
| Fizz | 123359260762085 | Opening Soda Can #2 | SinAwake | 2.47 s | yes | not used by any behaviour yet |
| CanDrop | 9114185361 | Drop Cans Bouncing 1 (SFX) | ProSoundEffects | 1.64 s | yes | quiet (peak ~0.09); raise Volume if needed |
| Coin | 16480549189 | Roblox_Pinball_Token_Insert_03 | Roblox | 1.90 s | yes | |
| ArcadeBlip | 16480580213 | Roblox_Pinball_8Bit_Blip_01 | Roblox | 0.69 s | yes | other blips: ..._02 16480580064, ..._05 16480579431 |
| ArcadeLose | 190705984 | Sad-Trombone | mexiizo | 3.92 s | yes | same id as library "Sad Trombone" |
| ArcadeWin | 16480577565 | Roblox_Pinball_8Bit_Riser_04 | Roblox | 2.92 s | yes | |
| Burp | 9113414717 | Belch Obnoxious 1 (SFX) | ProSoundEffects | 0.83 s | yes | short and silly; alt "Drink Burp 3" 9114171841 (slurp + belch) |
| Gulp | 133988388434763 | Swallow Gulping SFX | Baby_Starscream79 | 1.18 s | yes | one gulp; alt PSE "Comic Gulp" 9113859745 |
| FireLoop | 9112780462 | Fireplace Constant Burning Flame 4 (SFX) | ProSoundEffects | 42.75 s | yes | loop |
| FireIgnite | 4510176414 | Matchstick SFX | WaddelsG | 1.49 s | yes | NEW key (Hearth wish); strike at 0.1 s, flare at 0.7 s |
| FireOut | 9113702967 | Candles Blow Out Airy Breath Exhale 1 (SFX) | ProSoundEffects | 0.67 s | yes | NEW key (Hearth wish) |
| WaterLoop | 9120557306 | Water Fountain 1 (SFX) | ProSoundEffects | 36.0 s | yes | loop; 66 s take: 9120557315 |
| BubblesLoop | 9112752570 | Bubbles Dribble Small Bloops 1 (SFX) | ProSoundEffects | 13.81 s | yes | loop |
| Flush | 116759736098379 | toilet flush sound effect | RomatheHaxxer | 4.34 s | yes | rush from 0.1 s; fits the 3 s flush |
| Sizzle | 9114542867 | Fry Or Sizzle 1 (SFX) | ProSoundEffects | 39.78 s | yes | loop |
| HumLoop | 112948256817153 | Refrigerator (Sound) | DistrokidOfficial | 71.77 s | yes | loop |
| FridgeHum | 112948256817153 | Refrigerator (Sound) | DistrokidOfficial | 71.77 s | yes | NEW key (Fridge wish) |
| FridgeOpen | 9118125101 | Refrigerator Door Open 3 (SFX) | ProSoundEffects | 1.70 s | yes | NEW key; seal squeak at 0.65 s |
| FridgeClose | 9118127655 | Refrigerator Doors 1 (SFX) | ProSoundEffects | 1.48 s | yes | NEW key; thud at 0.35 s |
| MicrowaveHum | 4399963971 | Microwave hum / in operation | callmehbob | 10.64 s | yes | NEW key (Microwave wish), loop |
| MicrowaveBeep | 3690600068 | Microwave Beep SFX | sawguhh | 0.12 s | yes | NEW key (Microwave wish) |
| Ding | 9125485591 | Desk Bell Counter Service Single Ringing Ding (SFX) | ProSoundEffects | 4.53 s | yes | ding at 0.2 s, long ring |
| DoorOpen | 9118124760 | Refrigerator Door Open 2 (SFX) | ProSoundEffects | 1.94 s | yes | squeak at 0.6-0.9 s |
| DoorClose | 9120492567 | Washing Machine Door 1 (SFX) | ProSoundEffects | 2.61 s | yes | chunky clunk at 0.25 s (Laundry wish) |
| WasherLoop | 9118891774 | Sears Washing Machine 2 (SFX) | ProSoundEffects | 45.09 s | yes | normal cycle; starts with the dial switch |
| DryerLoop | 77493396468975 | the dryer-cycles | DistrokidOfficial | 44.21 s | yes | NEW key (Laundry wish), loop |
| ToasterPop | 365950085 | ToasterUp | Roblox | 0.65 s | yes | |
| ClockTick | 16480551554 | Roblox_Pinball_Small_Metal_Click_01 | Roblox | 0.36 s | yes | ONE tick at t = 0 (GrandfatherClock restarts it every swing) |
| ClockChime | 16480570385 | Roblox_Pinball_Bumper_Low_Bells_05 | Roblox | 1.52 s | yes | ONE bell strike at t = 0, ~611 Hz (the clock strikes it 1..12 times) |
| PianoNote | 78413131279275 | piano note c4 | I_AmKota | 6.00 s | yes | measured C4 (261 Hz); alt "280_Grand_Piano-C4" 79079707710718 (2 s, also 262 Hz) |
| CushionPoof | 9120204520 | Towel Drop 7 (SFX) | ProSoundEffects | 2.01 s | yes | NEW key (Sofa wish): cotton cloth flop |

`M.PianoRootHz = 261.63` (C4, measured).

## Music (M.Music) - all APMOfficial, full length

| # | Name | Id | Length | Style | Verified |
|---|---|---|---|---|---|
| 1 | Funky Disco Beats | 9038367768 | 200 s | funky, bouncy EDM | yes |
| 2 | Midnight Studio Juice | 9038366120 | 203 s | quirky bouncy EDM | yes |
| 3 | Feel That Move | 9044944264 | 189 s | 80s clavinet funk | yes |
| 4 | Stracciatella Galaxy | 9042927295 | 218 s | kitsch space-disco funk | yes |
| 5 | Normalize Today (Alt1, Lite) | 9046300489 | 123 s | syncopated funk, brass | yes |
| 6 | Floating Through Deeper Thoughts | 9038366820 | 178 s | uplifting bouncy EDM | yes |
| 7 | Jazz Joint (a) | 9045468115 | 153 s | lounge jazz organ + guitar | yes |
| 8 | Halves | 1837104550 | 132 s | positive synth groove | yes |

The old single track `1846271108` ("Background Beat") is actually APM "Waltzing Flutes", a waltz, so it was dropped.

## TV channels (M.TVChannels)

**Video channels** (Roblox-created, 1280x720; each has a slideshow fallback):

| Channel | Video id | Title | Creator | Length | Verified |
|---|---|---|---|---|---|
| Waterfall Cam | 5670869502 | Waterfall Landscape | Roblox | 30.0 s | yes (IsLoaded) |
| Space Walk | 5608398904 | Astronauts in Space | Roblox | 13.4 s | yes |
| Cartoon Sea | 5608250999 | Ocean Boat Cartoon | Roblox | 15.0 s | yes |
| Bird Watch | 5608392925 | Flying Cartoon Birds | Roblox | 14.8 s | yes |

Spare Roblox videos that also loaded:
* 5608410019 Lagoon Cliff Waterfall (14.8 s)
* 5608381934 Sun Cartoon Background (10 s)
* 5608390467 Bouncy Circle Background (8 s)
* 5608389672 Flying Colored Cubes Background (8 s)

Rejected: 5608360493 "Red Vs Blue Hammer Cartoon". Its creator is Bluay, not Roblox, it runs only 3 s, and the characters hit each
other.

**Slideshow channels** (6 images each, 4 s per slide). All were verified: image id resolved, preloaded, and the thumbnail viewed.

| Channel | Decal id -> IMAGE id | Title (uploader) |
|---|---|---|
| Nature | 5717309420 -> 5717309394 | Lake (MichaelIsGr8, CC0) |
| | 10719452903 -> 10719452874 | Unsplash Mountain / iceberg (polalagi, Unsplash) |
| | 1908897938 -> 1908897932 | Waterfall (Vell00) |
| | 5887500290 -> 5887500272 | Mountains & Fog (Ariziix) |
| | 3319553136 -> 3319553125 | Ocean Sunset (Starlsyy) |
| | 2546997596 -> 2546997593 | lake, snowy valley (almavvi) |
| Space | 6864892972 -> 6864892942 | Earth from Space (MichaelIsGr8, CC0 / NASA) |
| | 14833944877 -> 14833944867 | Saturn by Voyager (WinterOnDecember, NASA) |
| | 12787761237 -> 12787761154 | Pillars of Creation (Brun0401, NASA/Hubble) |
| | 10208854009 -> 10208853991 | Cosmic Cliffs, Carina Nebula (keira_rblx, NASA/JWST) |
| | 9728471672 -> 9728471648 | Butterfly Nebula (yhoniecute09, NASA/Hubble) |
| | 74067487424381 -> 117453845793004 | Tarantula Nebula (doge playz fan group, NASA/JWST) |
| Cute Animals | 5484695201 -> 5484695170 | Red Panda (MichaelIsGr8, CC0) |
| | 12590518064 -> 12590518027 | A Cute Dog / puppy (thepinkbeast12345) |
| | 404656672 -> 404656671 | Kitten (I3eII) |
| | 2414749350 -> 2414749340 | Sea Otter (fungirl3468, own photo) |
| | 14912788744 -> 14912788722 | Penguin (2333davi) |
| | 289280642 -> 289280641 | Very adorable kitten (disclvse) |
| Yummy Food | 4772865083 -> 4772865076 | pepperoni pizza (Zainnhy; transparent corners) |
| | 79619559 -> 79619558 | chocolate and vanilla cupcakes (forcehotel123) |
| | 84970289684109 -> 105472541332250 | Fruit salad (SuperT_man) |
| | 133134710334483 -> 90082450177424 | pancake stack, 3D render (thomas123cam) |
| | 3397603617 -> 3397603611 | Watermelon Slices illustration (abfbiggestfanreal) |
| | 3290518297 -> 3290518286 | watercolor strawberries (Ayzria) |

Spares that also loaded:
* Snowy Forest: 76642743069703 -> 125500895844311
* rabbit: 338829754 -> 338829752
* Fruit Salad!: 56859036 -> 56859035

The old "Cucumber TV" slide (15403007921) was not re-verified in this pass, so it was left out. Add it back as a
channel if the game's logo should show.

## Pictures (M.Pictures) - public-domain paintings, 12 IMAGE ids (all verified)

| Painting | Decal id -> IMAGE id | Uploader |
|---|---|---|
| The Starry Night, Van Gogh | 1305342234 -> 1305342230 | PandaPuff05 (Google Art Project scan) |
| The Great Wave off Kanagawa, Hokusai | 14044191933 -> 14044191899 | shigosen |
| Sunflowers (12 in a vase), Van Gogh | 12083554411 -> 12083554328 | disturbed_sphere |
| Cafe Terrace at Night, Van Gogh | 4623606226 -> 4623606213 | DavidLHuang |
| Woman with a Parasol, Monet | 3117938922 -> 3117938916 | chaquavius |
| A Sunday on La Grande Jatte, Seurat | 925192417 -> 925192416 | UmbraelIa |
| Almond Blossom, Van Gogh | 4623605776 -> 4623605764 | DavidLHuang |
| Irises, Van Gogh | 85361373197056 -> 91423198665435 | Gokuneedsourhelp (Getty Open Content) |
| Wheat Field with Cypresses, Van Gogh | 15816945744 -> 15816945717 | Anne1With1An1E1 |
| The Hay Wain, Constable | 70408119859717 -> 108467815321983 | AndyZeppeli |
| Poppies, Monet | 8178605934 -> 8178605912 | vvi59a |
| Sunset on the Seine, Monet | 11562220676 -> 11562220650 | leeloo75 |

Rejected: 4623606665 "Colorful Water Lily Pond by Monet". It is a modern painting in Monet's style, not a Monet, and is probably
copyrighted.

## Not done / for the integrator
* `FunAssets.Textures` (Fountain's optional Droplet / Ripple / Mist overrides) was not researched. Fountain.lua keeps
  its built-in textures.
* Still-unfilled wishes from the notes, none of them read by code today:
  * a snore loop (Bed)
  * a chips crunch, a spiral-motor whirr and a coin clink (VendingMachine)
  * a neon transformer hum (NeonSign)
  * an 8-bit "catch" and "hurt" (Arcade)
  * a water-fill gush (Laundry)
* Check by ear in a playtest:
  * CanDrop is quiet.
  * DoorOpen's squeak comes 0.6 s in.
  * TVOn is 6.7 s long, with only a faint tick after the pop.
