# TV: working television (package TV, 2026-09-24)

Behaviour only. The existing "TV" build (props-dump/TV.txt, source `RobloxGames/props/build_tv.py`, x1.45 in game) is unchanged.

## Files
| file | goes to |
|---|---|
| `src/behaviours/server/TV.lua` | `ServerStorage.FunBehaviours.TV` (ModuleScript) |
| `src/behaviours/client/TV.lua` | `ReplicatedStorage.FunBehavioursClient.TV` (ModuleScript) |
| `tests/TV/run.ps1` + `prelude.luau` + `test.luau` | offline smoke test (not installed) |

## What it does
**Server**
* A **"Turn on" / "Turn off"** prompt on `Panel` (E / ButtonX). The ActionText flips.
* A **"Next channel"** prompt on `Panel` (R / ButtonY, so both badges show at once). It only exists while the TV is on: the server parents it to `Panel` when on and to `nil` when off. It does not use `Enabled = false`, because FunBuildClient's build-mode hide/unhide sets `Enabled = true` locally and would bring a disabled prompt back. `UIOffset = (0, 72)` puts it one prompt-height under the power prompt (CucumberPromptClient turns UIOffset into SizeOffset). Its ObjectText names the current channel ("CH 2  Pics").
* State: `Fun_On` (bool), `Fun_Channel` (1-based index into `FunAssets.TVChannels`, wraps round), `Fun_Since` (`Kit.Now()` at power-on and at every channel change).
* Anyone can use it. Power has a 0.6 s cooldown and channel changes have a 0.4 s cooldown, so nobody can strobe it faster than the animations.

**Client** (all local, driven by the state + `Kit.Now()`)
* **Screen:** an invisible Part (`TVScreen`) plus a SurfaceGui with Face Front, LightInfluence 0, Brightness 1.2, PixelsPerStud 50 (339 x 171 px at x1.45).
  * Geometry comes from the real `ScreenSky` part. The ScreenSky axis nearest the build's front is the normal, the axis nearest up gives the height, and the third gives the width. This holds up against the FBX 180-degree yaw and a future swivel.
  * The face sits 0.014 authored studs in front of the front-most Neon layer (`ScreenSun`). The harness measured it at authored z -0.134 against the bezel front at -0.13, covering the 4.68 x 2.36 aperture exactly.
  * If ScreenSky is missing, the authored numbers are the fallback.
* **Off:** a dark glossy gradient panel with a faint diagonal reflection streak that moves **with** the viewer on both axes, as a reflection on glass does (UIGradient.Offset parallax; GUI +x on a Front-face SurfaceGui runs along the part's -X = the viewer's right, and `ScreenGeometry` returns that `viewerRight`). The **stand-by dot** blinks red: 0.95 s lit every 1.6 s, in step on every client.
  * The dot is a local Neon/SmoothPlastic disc (`TVStandby`, authored (-1.75, 2.23, -0.1725), dia 0.18) laid over the RedLights bezel dot. RedLights itself is never touched, because that mesh also holds the remote's power key.
  * While the TV is on, the disc sits dim (standby LED out).
* **On, slides:** two ImageLabels (Crop) cross-fade (0.6 s) every `Seconds` (default 4), with a slow zoom.
  * The slide index is `floor((Kit.Now() - Since) / Seconds) % #Slides`, so every client and every late joiner shows the same slide.
  * A new slide list draws its current slide **at once** (`SetSlides` calls `UpdateSlides`), not on the next Step, so a channel change never leaves the previous channel's picture frozen.
  * The channel's pictures are preloaded (ContentProvider, pcall).
* **Far (180-260 studs):** `ctx:Step` sleeps beyond `StepRange` (180) but the SurfaceGui draws out to 260. There the 4 Hz `ctx:Every` keeps the slides turning and the stand-by dot blinking, and channel-change static is rolled once when it starts, so it is noise even with no Step.
* **On, video:** a looped VideoFrame. It is assigned only when the camera is within 150 studs, plays only within 70, and pauses beyond that (checked every 0.25 s by `ctx:Every`, so it still pauses when `ctx:Step` sleeps).
  * Layer order in the picture: Video 1, Bars 2, SlideBack 3, SlideFront 4, Message 5, Static 6, OSD 7. The video sits **under** its stand-in pictures (the channel's own `Slides`, else the first slideshow channel's, else colour bars), which come off when `IsLoaded` turns true. So an unloaded VideoFrame, black or not, can never hide the fallback, and it stays `Visible` so loading is never gated on visibility.
  * Near (camera within 150 when the channel starts): "Tuning..." on black while it loads. If it has not loaded 6 s after assignment: the stand-ins + **"NO SIGNAL"**.
  * Far (camera beyond 150 when the channel starts, or while it is still unassigned): the stand-in slides show quietly with no message and no download. They stay up when the camera comes closer and the video is assigned (no drop back to "Tuning..."), until it loads. "NO SIGNAL" then follows the same 6 s rule.
  * On (re)start it seeks to `(Kit.Now() - Since) % TimeLength` and re-seeks if it drifts more than 1.5 s.
  * Volume is 0.5 within 28 studs, fading to 0 at 70, and **only for channels with `Sound = true`** (as FunAssets documents: "muted unless Sound = true"; none of the current channels sets it, so every video plays muted).
  * If the video loads later, the stand-ins go away. Every VideoFrame call is wrapped in pcall.
* **No channels / no content:** colour bars ("NO CHANNELS" when the list is empty).
* **Power on:** a CRT "expand from a line" (dot, then a 3 px line, then full height) under a white flash, then the OSD. Plays `Sfx.TVOn`.
* **Power off:** squash to a line, then to a dot, then a fading afterglow dot. Plays `Sfx.TVOff`.
* **Channel change:** 0.35 s of procedural static (a 28 x 16 grid of grey cells rolled when it starts and re-rolled every other frame, 2 rolling bands, a 2 px horizontal jitter). The cells are built once, on the first change. Plays `Sfx.TVStatic`, stopped at 0.4 s.
  * A new channel number always gets static + OSD, even when pressed during the power-on animation (before, the power-on OSD kept naming the old channel for ~2 s). The 0.6 s window after a power-on now only ignores a bare `Since` change on the same channel.
* **OSD:** "CH 02" in green (69,255,0) plus the channel name, top-left, for 2 s after power-on and after every change. It uses the Arcade font for a TV look; the FredokaOne rule is for panels.
* **SurfaceLight** on the screen part: Face Front, Range 12, Brightness 1.4, colour (205,225,255), Angle 120, no shadows. It is enabled only while on and fades in and out with the CRT. That makes 1 light per build.
* The client uses 1 `ctx:Step` and 1 `ctx:Every`. No build part is modified, so nothing needs restoring. The cleanup cancels tweens and stops the video.

## Parts / attributes relied on
`Panel` (prompts; ScreenSky or the Hitbox if it is missing), `ScreenSky` (screen frame), `ScreenLand` / `ScreenSun` (how far the picture stands out), `RedLights` (only checked for existence; the dot position is the authored `build_tv.py` constant). Also `Scale` and `AuthoredCentre` via Kit. `Pivot_ScreenSwivel` / `State_*` are not used.

## For the integrator
* **Local parts go in `workspace.FunBuildLocal`** (a client-only Folder the module creates, Archivable false), not the Camera. This keeps the SurfaceLight reliably lighting the room. If you would rather keep everything in the Camera, change `LOCAL_FOLDER` handling in `LocalFolder()` (one function).
* **FunAssets.TVChannels** now holds 8 channels: 4 video (Waterfall Cam, Space Walk, Cartoon Sea, Bird Watch, each with its own fallback `Slides`) and 4 slideshows. The offline test tunes all 8. Channel 1 (the power-on default) is a video, so the near "Tuning..." and the far quiet-slides paths are the common case. The code handles any count, including 0.
* **Sounds:** FunAssets now has real ids for `TVOn` (power-on pop), `TVOff` (old TV switching off) and `TVStatic` (white noise, cut at 0.4 s). No wishes left.

## How to test in Studio
1. Place a TV, walk up to it, and press **E** ("Turn on"). You should see a line, then the full picture, a flash, the TVOn sound, the "CH 01 Waterfall Cam" OSD, a blue-white glow on the floor, and "Tuning..." until the video plays (or its nature slides + "NO SIGNAL" after 6 s).
2. Press **R** ("Next channel", shown under the power prompt). You should see 0.35 s of static, the hiss, and the OSD. Channels 5-8 are slideshows. Pressing R during the power-on animation still shows the new channel's OSD.
3. Far check: from about 200 studs away, a video channel shows its slides (no "Tuning...") and slideshows keep turning.
4. Press **E** again ("Turn off"). The picture squashes to a line, then a dot, then an afterglow, and the red dot on the bezel (the viewer's right, under the screen) starts blinking.
5. From a server eval, read the state with `model:GetAttribute("Fun_On" / "Fun_Channel" / "Fun_Since")`. You can also drive the client directly by setting those attributes on the server: `Fun_Since = workspace:GetServerTimeNow()` with `Fun_On = true` animates the power-on.
6. Video: on channels 1-4, check `TVScreen.TVScreenGui.Tube.Picture.Video.IsLoaded` / `Playing` on the client. It pauses when the camera is more than 70 studs away.
7. To check the geometry numerically: `Kit.Origin(model):ToObjectSpace(workspace.FunBuildLocal.TVScreen.CFrame)` / Scale should be about (0, 3.55, -0.114) with LookVector (0, 0, -1).
8. Glare: strafe right in front of the off TV; the diagonal streak should slide right with you.

## Offline test
`powershell -NoProfile -ExecutionPolicy Bypass -File tests\TV\run.ps1` runs the real FunBuildKit, FunAssets and both TV halves against a mocked Roblox runtime with a strict global environment. The TV mock is yawed 90 degrees and ScreenSky is yawed 180 degrees. The test pins its own channel list, then runs the real `FunAssets.TVChannels` at the end. The run covers:
* geometry
* the blink
* the glare direction (moves with the viewer on both axes)
* power on/off
* the cooldown
* prompt parking
* the static grid
* slide cycling + cross-fade + shared-clock index
* video timeout, then fallback, then loaded (seek, mute rules, far pause)
* the picture layer order
* a channel pressed during the power-on (static + new OSD) versus a trailing Since (nothing)
* the 180-260 stud band with no Step: slide drawn at once, 4 Hz turning, rolled static, a far video's quiet preview kept through approach until it loads
* a late joiner (no animation)
* all 8 real channels tune and name themselves; a real video's NO SIGNAL shows its own slides; a real far video shows its slides without downloading
* cleanup

Result: **79 checks, 0 failed**. Putting each review fix back (a scratch mutation run) fails its checks: 6, 2, 3 and 4 failures.

## Known limits
* The "NO SIGNAL" timeout counts from assignment, so a camera parked 70-150 studs away may show the fallback until someone comes closer and playback starts. After that the video takes over.
* The screen does not follow a swivel animation, since nothing swivels the Panel today. The geometry is computed once per run.
* Static noise is random per client, which is harmless. Everything else is synced.
* In the 180-260 stud band, cross-fades and the blink step at 4 Hz, not per frame. The screen is under ~7 studs wide at that range.
* Every current video plays muted, because no channel sets `Sound = true`. Set it per channel for 0.5 volume near (fading to 0 at 70 studs).
* Not verified in Studio: that a SurfaceGui on a Transparency-1 local part renders (it should; this is the common pattern), and VideoFrame load times.
