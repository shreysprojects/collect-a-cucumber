# Biome Guardians - modelling brief (2026-09-14)

Ten sitting guardians, one per biome, for the "steal a cucumber and it chases you" loop (design notes
in the session of 2026-09-14; nothing installed yet). This file is the source for the published
artifact page of the same name.

## Shared rules

- **Style**: the low-poly, flat-shaded look of the cucumber set and the plot props. One flat colour per
  piece, no textures. Chunky shapes that read at 100 studs.
- **Scale**: an R15 avatar is ~5 studs tall. Guardians escalate with the biome ladder: Spawn ~7 studs,
  Neon ~12. Sitting height is what the player sees first, so it is listed separately.
- **Pieces**: model every moving part as its OWN mesh with its pivot at the joint (the zombie rigs are
  built the same way: Motor6Ds from attachments). Minimum set: root/body, head, each limb segment, any
  jaw / claw / key / tail. Eyes are separate small parts so they can switch to Neon when the guardian wakes.
- **Facing**: the model faces -Z in Blender so its LookVector is forward in Roblox. The FBX pipeline
  yaws 180 deg and drops every colour, so name pieces `<Guardian>_<Part>_<ColourRole>` (for example
  `Yeti_Arm_L_FurWhite`) and the colours get stamped back by script from the role.
- **Budget**: 2,000 - 4,000 triangles per guardian. One invisible box for the hitbox, one for the seat.
- **Two states on every model**: ASLEEP (eyes dark, slumped) and AWAKE (eyes lit, upright). The tell
  must read from across the field.
- **Motion set to plan for** (animate later, but leave the pivots): sit idle, wake, run, grab/hit,
  return to seat, stunned.

## 1. Spawn - Hay Scarecrow "Strawman"

- **Concept**: a burlap scarecrow that climbs down off its pole. The tutorial guardian: slow, clumsy, loud.
- **Size**: 7 studs standing, 5 sitting. Footprint 3 x 3.
- **Silhouette**: stick-thin arms out wide, round sack head, straw bursting at wrists, ankles and neck.
- **Pieces**: sack head, torso (patched shirt), 2 upper arms, 2 forearms, 2 legs, straw tufts (6 cones),
  wooden cross pole (carried like a staff when awake), hat (dented straw hat).
- **Palette**: burlap 196,164,110 / straw 222,190,80 / shirt 140,60,50 / denim 70,90,140 / pole 110,80,50.
- **Face**: two button eyes, a stitched X mouth. Awake: the buttons glow orange 255,140,40.
- **Seat**: a hay bale; it sits on top with the pole across its lap.
- **Signature**: crows burst off it when it wakes; every few seconds it stops to shake crows out,
  which is the escape window.

## 2. Desert - Sand Worm "Dune"

- **Concept**: a segmented worm that swims under the sand and surfaces to bite.
- **Size**: 12 studs long, 3.5 wide. Asleep only the head shows as a "mound with eyes".
- **Silhouette**: a tapering chain of rings, a three-part jaw open like a flower when it strikes.
- **Pieces**: head, top jaw, 2 mandibles, 6 body rings (shrinking), tail tip, 12 tooth pegs, a separate
  flat sand mound mesh that slides along the ground while it travels underground.
- **Palette**: sandstone 210,170,110 / ring shadow 160,120,70 / mouth 200,90,90 / teeth 240,230,200.
- **Face**: two slitted eyes under heavy lids. Awake: amber 255,190,60.
- **Seat**: none, it rests half-buried in a dune with the mound.
- **Signature**: dives, travels as a moving mound with sand spray, and pops up AHEAD of the runner.

## 3. Samurai - Stone Oni "Kabuto"

- **Concept**: a temple statue that cracks to life. The first guardian that hits hard.
- **Size**: 9 studs standing, 6.5 sitting on its pedestal. Footprint 4 x 4.
- **Silhouette**: square shoulders, two forward horns, tusks, a club as long as its arm.
- **Pieces**: head, 2 horns, torso, 2 upper arms, 2 forearms, 2 legs, kanabo club (separate, swung),
  rope belt with 2 tassels, 3 moss patches (flat shells on the shoulders and knee).
- **Palette**: stone 150,150,155 / cracks 90,90,95 / rope 200,50,40 / moss 110,150,70 / tusks 235,225,200.
- **Face**: heavy brow, grimace, deep-set eyes. Awake: eyes AND crack lines glow amber 255,170,50.
- **Seat**: a square stone pedestal with a torii-style lintel behind it.
- **Signature**: a ground slam with the club (knockback), then a slow wind-up so the slam is dodgeable.

## 4. Farm - Bull "Brisket"

- **Concept**: a big square bull that lies chewing until you touch its patch.
- **Size**: 8 studs at the shoulder, 12 long. Lying: 5 tall.
- **Silhouette**: massive front, tiny back, horns wider than the body, a brass nose ring.
- **Pieces**: head, 2 horns, 2 ears, nose ring, body, 4 legs (upper + lower), tail with tuft.
- **Palette**: chestnut 120,70,40 / muzzle and horns 235,220,190 / nose 215,140,140 / hooves 40,35,35 /
  ring 200,160,60.
- **Face**: small angry eyes, wide flat nose. Awake: eyes red 235,50,50, steam puffs from the nose.
- **Seat**: a mud patch inside a broken fence corner; it lies there.
- **Signature**: the line charge. Head down, straight line, misses if you sidestep, skids and has to turn.

## 5. Snow - Yeti "Frostbite"

- **Concept**: a hunched shaggy giant breathing frost.
- **Size**: 10 studs standing, 6 sitting. Footprint 5 x 4, huge flat feet.
- **Silhouette**: a pear body, no neck, arms to the ground, fur tufts on shoulders and forearms.
- **Pieces**: body, head (brow ridge as a separate slab), 2 upper arms, 2 forearms, 2 hands, 2 feet,
  8 fur tuft cones, 2 fangs.
- **Palette**: fur 240,244,250 / fur shadow 170,195,225 / face and palms 110,130,160 / fangs 250,250,245.
- **Face**: face is a dark oval in the fur, tiny eyes, underbite. Awake: eyes ice blue 120,200,255.
- **Seat**: a cracked ice block.
- **Signature**: slow to start (sinks knee-deep), fast once moving, and throws a snowball that slows you.

## 6. Underwater - King Crab "Pinch"

- **Concept**: a wide low crab crusted with coral that scuttles sideways at speed.
- **Size**: 6 studs tall, 14 wide with claws out, 8 deep.
- **Silhouette**: a flat dome, eight legs splayed, one claw far bigger than the other.
- **Pieces**: carapace, 8 legs (2 segments each), big claw (fixed pincer + moving pincer), small claw
  (same), 2 eye stalks with eye balls, 5 coral nubs and 3 barnacle discs glued to the shell.
- **Palette**: shell 220,90,60 / underside 245,215,180 / coral 60,170,160 / barnacles 235,235,225.
- **Face**: eyes on stalks. Awake: eyes green 120,255,150 and a burst of bubbles.
- **Seat**: a rock nook with a giant shell behind it.
- **Signature**: very fast sideways, slow forwards; the big claw snaps for the grab.

## 7. Volcano - Magma Golem "Ember"

- **Concept**: a pile of basalt boulders that stands up, held together by lava seams.
- **Size**: 11 studs standing, 5 as a rock pile. Footprint 5 x 5.
- **Silhouette**: boulders with visible GAPS between them; the glow lives in the gaps.
- **Pieces**: core, head, 2 shoulder boulders, 2 upper arms, 2 forearm boulders, 2 leg boulders, 2 feet,
  a loose throwing rock held in one hand. Every piece floats a little apart from its neighbour.
- **Palette**: basalt 45,40,42 / seams 255,120,20 (Neon) / ember 255,200,60 / ash 120,115,110.
- **Face**: a crack for a mouth and two pits for eyes. Asleep: no glow at all, it reads as rocks.
  Awake: seams and eyes light up.
- **Seat**: none, it IS the rock pile beside a lava pool.
- **Signature**: relentless and slow, brighter with heat, throws a lava rock and leaves ember footprints.

## 8. Narmek - Meteor Colossus "Orbit"

- **Concept**: a cosmic being of dark stone hovering cross-legged on a crescent moon (the biome's
  cucumbers are Moon Slices, Meteor Cucumbers and Planet Slices).
- **Size**: 12 studs, hovers 2 studs up. No legs when awake, the lower body is a tapering swirl.
- **Silhouette**: a hooded head shaped like a crescent, two floating hands, a ring of six orbiting rocks.
- **Pieces**: head crescent, torso, swirl tail, 2 floating hands (no arms), 6 orbit rocks on a ring,
  the crescent moon seat.
- **Palette**: space navy 25,20,60 / glow purple 170,80,255 (Neon) / starlight cyan 120,220,255 /
  moon grey 200,200,215.
- **Face**: a single wide crack across the crescent. Awake: the crack and hands glow purple, the
  rocks spin fast.
- **Seat**: the crescent moon, with its horns pointing up.
- **Signature**: short blink teleports, and a gravity pull that slows you within ten studs.

## 9. Toyland - Wind-up Soldier "Tick"

- **Concept**: a tin toy robot with a wind-up key that literally winds down mid-chase.
- **Size**: 9 studs standing, 6 slumped. Footprint 4 x 3.
- **Silhouette**: a box body, a dome head with a visor slot, a huge key on its back, stubby legs.
- **Pieces**: box body, dome head, visor slot (Neon strip), 2 hinged arms (upper + lower, mitten
  hands), 2 stubby legs, 2 flat feet, wind-up key (rotates on its own axis), antenna with a bulb,
  a painted star on the chest.
- **Palette**: red 220,40,40 / cream 240,230,200 / blue 40,80,200 / brass 200,160,60 / bulb 255,240,120.
- **Face**: the visor slot is the eye. Asleep: slot dark, head slumped, key still. Awake: slot lit
  cyan 80,230,255, bulb blinking, key turning.
- **Seat**: a toy block stack; it sits slumped like a toy with no wind left.
- **Signature**: it sprints for six seconds, stops, its arms drop and the key turns as it rewinds,
  then it sprints again.

## 10. Neon - Laser Sentinel "Scan"

- **Concept**: a hovering angular drone that hunts by line of sight instead of running.
- **Size**: 8 studs tall, hovers at 4. Footprint 6 x 6 with fins.
- **Silhouette**: a wedge head with one wide visor, two floating shoulder pods, four fins, a bright core.
- **Pieces**: head wedge, visor (Neon), core sphere, 2 shoulder pods, 4 fins, an under-lens for the
  scan cone, a trail attachment point at the back.
- **Palette**: gloss black 20,20,25 / magenta 255,50,200 (Neon) / cyan 50,230,255 (Neon) / core white
  255,255,255.
- **Face**: the visor. Asleep: visor off, pods folded in, resting on a charging pad. Awake: visor
  magenta, a sweeping cyan search cone.
- **Seat**: a glowing charging pad with cable trim.
- **Signature**: it does not run. It scans, blinks to where it saw you and tags you with a beam;
  breaking line of sight behind the neon signs resets it.

## Speed and size at a glance

| # | Biome | Guardian | Standing | Sitting | Pace |
|---|---|---|---|---|---|
| 1 | Spawn | Strawman | 7 | 5 | slow, stops for crows |
| 2 | Desert | Dune | 12 long | mound | fast under sand, surfaces ahead |
| 3 | Samurai | Kabuto | 9 | 6.5 | medium, slam wind-up |
| 4 | Farm | Brisket | 8 (12 long) | 5 | line charge, slow turns |
| 5 | Snow | Frostbite | 10 | 6 | slow start, fast after |
| 6 | Underwater | Pinch | 6 (14 wide) | 5 | fast sideways, slow forward |
| 7 | Volcano | Ember | 11 | 5 | slow, relentless, throws |
| 8 | Narmek | Orbit | 12 (hovers) | 8 | blinks, gravity pull |
| 9 | Toyland | Tick | 9 | 6 | sprint 6 s, rewind |
| 10 | Neon | Scan | 8 (hovers) | 4 | scan and blink |
