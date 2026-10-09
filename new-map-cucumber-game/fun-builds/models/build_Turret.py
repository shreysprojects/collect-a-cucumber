"""Turret (Defences, fun-builds 2026-09-24, package DefTurret): the twin-cannon sentry REBUILT.
A sturdy octagonal gunmetal plinth on a dark DiamondPlate foot (bolts, diagonal gussets, an orange lip, a
front status panel, a bearing ring) carries a rotating armoured head: two orange cheek plates with sloped
fronts, vented side panels and capped trunnion hubs, a roof with a hatch, a sensor pod with a big cyan EYE,
an ammo drum at the back and an antenna. Between the cheeks a round mantlet carries TWIN BARRELS (steel
tubes, dark cooling sleeves with orange ribs, a clamp, slotted square muzzle brakes) ending in glowing cyan
muzzle rings linked by the neon BarrelMuzzleGlow bar.

RIG CONTRACT (live/DefenceService.server.lua, key "Turret" = set-1 rig, read from the PLACED parts):
  BasePlinth        a Block centred at x = z = 0: its centre (x, z) is the yaw axis
  HeadTrunnion      a Cylinder (axis X) centred on the barrels' pitch pivot (0, TRUNNION_Y, 0)
  Head*             yaw about the vertical axis through BasePlinth
  Barrel*           pitch about the X axis through HeadTrunnion (MinPitch -25, MaxPitch +45 deg), then yaw
  everything else   "Base*", static
  BarrelMuzzleGlow  Neon 4dd2ff Block centred between the two muzzles, local X across the barrels, facing -Z:
                    shots leave from its CFrame * (+/-0.5, 0, -0.15) = just in front of each bore
Barrels point toward -Z at rest (zero yaw / zero pitch). Authored origin = floor centre (min y = 0).
Every yawing part stays within radius 4 of the axis at every pitch (report() checks it), so the gun spins
inside the 8 x 8 tile.

CLEARANCE (fix pass 2026-09-24): report() runs clash_sweep() on every build - Barrel* vs Head* over pitch
-25..+45 (every degree) and Head* + Barrel* vs Base* over every yaw (2 deg) x pitch - and fails the build if
any moving part cuts deeper than CLASH_LIMIT (0.03). MinPitch -25 is a COMMON pose (a Spawnling bashing the
turret stands ~4 studs out, root ~1.8 up), which is why the turntable is 4.0 across (was 4.7), the bearing
ring 3.7 (was 4.5), the barrel sleeves 0.70 (was 0.74) and the orange lip tops out at 1.72 (was 1.86).
"""
import math
import time
import numpy as np
from mathutils import Vector, Matrix

# ---------------------------------------------------------------- palette
ORANGE = "ff8a2a"     # head armour / accent
GUN = "3b4350"        # gunmetal
GUN_LT = "56627a"     # lighter gunmetal panels
DARK = "23262c"       # near-black
STEEL = "9aa7b8"      # steel tubes
STEEL_LT = "d5dbe4"   # bright bolt heads / hub caps
CYAN = "4dd2ff"       # neon glows
WHITE = "f2f0ea"
BRASS = "e0a93a"      # ammo

# ---------------------------------------------------------------- layout
TRUNNION_Y = 3.7
BARREL_X = 0.5        # barrel axes at x = +/-0.5 (the server fires from MuzzleGlow +/- 0.5 local X)
MUZZLE_Z = -3.76      # front face of the muzzle rings
FOOT_W, PLINTH_W, LIP_W = 7.2, 5.6, 6.0
LIP_TOP = 1.72         # was 1.86: the muzzle rings / brakes clear its corners at MinPitch (1.76 still cut 0.029)
TURNTABLE_D = 4.0      # was 4.7: the clamp / tubes / sleeves pass over its rim at MinPitch -25
RING_D = 3.7           # bearing ring, a step narrower than the turntable
EYE_Y = 5.4
TAN = math.tan(math.radians(22.5))


# ---------------------------------------------------------------- shape helpers
def octagon(m, names, y0, y1, W, color, material, step=0.03, **kw):
    """Regular octagon (flat-to-flat W) = the union of 4 W x s blocks at 0/45/90/135 degrees. The two
    diagonal blocks reach y1, the axis pair stops `step` lower (no coplanar textured tops; step 0 is fine for
    same-colour SmoothPlastic). names[0] = the 0-degree block (centred on x = z = 0)."""
    s = W * TAN
    h = y1 - y0
    ha = h - step
    m.block(names[0], (0, y0 + ha / 2, 0), (W, ha, s), color, material, **kw)
    m.block(names[1], (0, y0 + ha / 2, 0), (s, ha, W), color, material, **kw)
    m.block(names[2], (0, y0 + h / 2, 0), (W, h, s), color, material, rot=(0, 45, 0), **kw)
    m.block(names[3], (0, y0 + h / 2, 0), (W, h, s), color, material, rot=(0, -45, 0), **kw)


def face_frame(W, face, y, out=0.0, along=0.0):
    """(point, yaw) on octagon face `face` (0 = front -Z, 1 = front-right (-X) ... every 45 deg): `out` studs
    beyond the face plane, `along` studs along the face; yaw turns a part's local +Z onto the outward normal."""
    yaw = 180 + 45 * face
    az = math.radians(yaw)
    n = Vector((math.sin(az), 0, math.cos(az)))
    t = Vector((math.cos(az), 0, -math.sin(az)))
    return tuple(n * (W / 2 + out) + t * along + Vector((0, y, 0))), yaw


# ---------------------------------------------------------------- the build
def build(D, P):
    m = P.Model(D, "Turret", category="Defences")
    TY = TRUNNION_Y

    # =============================================================== BASE (static)
    octagon(m, ["BaseFoot", "BaseFootB", "BaseFootC", "BaseFootD"], 0.0, 0.36, FOOT_W, DARK, "DiamondPlate")
    octagon(m, ["BasePlinth", "BasePlinthB", "BasePlinthC", "BasePlinthD"], 0.3, 1.68, PLINTH_W, GUN, "Metal")
    octagon(m, ["BaseLip", "BaseLipB", "BaseLipC", "BaseLipD"], LIP_TOP - 0.22, LIP_TOP, LIP_W, ORANGE, "SmoothPlastic",
            step=0.0)
    s_face = PLINTH_W * TAN
    for f in range(8):
        if f % 2 == 0:
            # raised panel on the four square-on faces
            pos, yaw = face_frame(PLINTH_W, f, 0.99, out=0.03)
            m.block("BasePanel%d" % (f // 2 + 1), pos, (s_face - 0.46, 0.96, 0.1), GUN_LT, "Metal", rot=(0, yaw, 0))
        else:
            # a sloped gusset braced against each diagonal face
            pos, yaw = face_frame(PLINTH_W, f, 0.36 + 0.5, out=0.3)
            m.wedge("BaseGusset%d" % (f // 2 + 1), pos, (0.95, 1.0, 0.6), GUN, "Metal", rot=(0, yaw + 180, 0))
    # front status panel: a dark display slot with three cyan lights
    pos, yaw = face_frame(PLINTH_W, 0, 0.99, out=0.09)
    m.block("BaseDisplay", pos, (1.25, 0.36, 0.06), DARK, "SmoothPlastic", rot=(0, yaw, 0), collide=False)
    for i, a in enumerate((-0.36, 0.0, 0.36)):
        pos, yaw = face_frame(PLINTH_W, 0, 0.99, out=0.12, along=a)
        m.block("BaseLight%d" % (i + 1), pos, (0.2, 0.18, 0.06), CYAN, "Neon", rot=(0, yaw, 0), collide=False)
    # bolts round the foot (one in front of each face)
    bolts = []
    for f in range(8):
        for a in ((0.0,) if f % 2 == 0 else (-0.78, 0.78)):
            bolts.append(face_frame(FOOT_W, f, 0.4, out=-0.5, along=a)[0])
    for i, pos in enumerate(bolts):
        m.cyl("BaseBolt%d" % (i + 1), (pos[0], 0.33, pos[2]), (pos[0], 0.47, pos[2]), 0.3, STEEL_LT, "Metal",
              collide=False)
    # bearing ring the head turns on
    m.cyl("BaseRing", (0, LIP_TOP - 0.04, 0), (0, 2.2, 0), RING_D, DARK, "Metal")

    # =============================================================== HEAD (yaws)
    m.cyl("HeadTurntable", (0, 2.18, 0), (0, 2.46, 0), TURNTABLE_D, STEEL, "DiamondPlate")
    CX0, CX1 = 1.08, 2.1                     # cheek inner / outer |x|
    CW = CX1 - CX0
    for s, t in ((1, "L"), (-1, "R")):       # L = +X (the viewer's left from the front)
        cx = s * (CX0 + CX1) / 2
        # lower cheek (front z -1.2) + upper cheek set back (front z -0.6) + the sloped armour between them
        m.block("HeadCheekLow" + t, (cx, 2.98, 0.35), (CW, 1.04, 3.1), ORANGE, "SmoothPlastic")
        m.block("HeadCheekHigh" + t, (cx, 4.1, 0.65), (CW, 1.2, 2.5), ORANGE, "SmoothPlastic")
        m.wedge("HeadCheekSlope" + t, (cx, 4.1, -0.9), (CW, 1.2, 0.6), ORANGE, "SmoothPlastic")
        m.wedge("HeadRoofBevel" + t, (cx, 4.83, -0.37), (CW, 0.26, 0.46), ORANGE, "SmoothPlastic")
        m.block("HeadCheekBumper" + t, (cx, 2.64, -1.23), (CW + 0.06, 0.3, 0.1), DARK, "Metal")
        # vented side panel behind the hub
        m.block("HeadSidePanel" + t, (s * (CX1 + 0.03), 3.62, 1.25), (0.1, 1.5, 1.1), GUN_LT, "Metal")
        for k, y in enumerate((3.22, 3.62, 4.02)):
            m.block("HeadVent%s%d" % (t, k + 1), (s * (CX1 + 0.09), y, 1.25), (0.06, 0.14, 0.8), DARK, "Metal",
                    collide=False)
    m.block("HeadChin", (0, 2.66, 0.5), (2.2, 0.4, 1.8), GUN, "Metal")
    m.block("HeadRear", (0, 3.79, 1.41), (2.2, 1.9, 0.94), GUN, "Metal")
    m.block("HeadRoof", (0, 4.83, 0.905), (4.32, 0.26, 2.11), ORANGE, "SmoothPlastic")
    m.cyl("HeadHatch", (1.27, 4.94, 1.35), (1.27, 5.02, 1.35), 0.95, GUN_LT, "Metal", collide=False)
    m.block("HeadHatchHandle", (1.27, 5.06, 1.35), (0.5, 0.08, 0.12), DARK, "Metal", collide=False)
    # sensor pod + eye
    m.block("HeadSensor", (0, EYE_Y, 0.4), (1.5, 0.9, 1.1), GUN, "Metal")
    m.block("HeadSensorHood", (0, EYE_Y + 0.5, -0.02), (1.3, 0.12, 0.5), DARK, "Metal", collide=False)
    m.cyl("HeadEyeBezel", (0, EYE_Y, -0.12), (0, EYE_Y, -0.28), 0.84, DARK, "Metal")
    m.cyl("HeadEye", (0, EYE_Y, -0.24), (0, EYE_Y, -0.33), 0.62, CYAN, "Neon")
    m.ball("HeadEyeGlint", (0.13, EYE_Y + 0.13, -0.33), 0.14, WHITE, "Neon", collide=False)
    for s, t in ((1, "L"), (-1, "R")):
        m.block("HeadSensorLed" + t, (s * 0.77, EYE_Y, 0.15), (0.06, 0.14, 0.34), CYAN, "Neon", collide=False)
    # trunnion axle + hub caps
    m.cylx("HeadTrunnion", (0, TY, 0), 4.44, 0.8, STEEL, "Metal")
    for s, t in ((1, "L"), (-1, "R")):
        m.cylx("HeadHub" + t, (s * 2.2, TY, 0), 0.2, 1.2, DARK, "Metal")
        m.cylx("HeadHubBolt" + t, (s * 2.33, TY, 0), 0.12, 0.46, STEEL_LT, "Metal", collide=False)
    # ammo drum at the back, on a mount
    m.block("HeadDrumMount", (0, 2.62, 2.1), (1.0, 0.36, 0.9), DARK, "Metal")
    m.cylx("HeadDrum", (0, 3.55, 2.6), 2.3, 1.7, GUN, "Metal")
    m.cylx("HeadDrumBand", (0, 3.55, 2.6), 0.46, 1.78, ORANGE, "SmoothPlastic")
    for s, t in ((1, "L"), (-1, "R")):
        m.cylx("HeadDrumCap" + t, (s * 1.2, 3.55, 2.6), 0.14, 1.1, STEEL, "Metal")
        for k in range(2):                   # a cross of spokes on each cap
            m.block("HeadDrumSpoke%s%d" % (t, k + 1), (s * 1.28, 3.55, 2.6), (0.06, 0.9, 0.16), DARK, "Metal",
                    rot=(45 + 90 * k, 0, 0), collide=False)
        # tail light on the back face of each cheek
        m.block("HeadTailLight" + t, (s * 1.6, 4.3, 1.92), (0.5, 0.16, 0.06), CYAN, "Neon", collide=False)
    # ammo belt: a dark feed chute from the drum up into the back of the head, brass rounds on it
    a, b = Vector((0.62, 4.28, 2.9)), Vector((0.62, 4.62, 1.86))
    m.beam("HeadFeedChute", tuple(a), tuple(b), 0.5, 0.14, DARK, "Metal", collide=False)
    up = (b - a).normalized().cross(Vector((1, 0, 0))).normalized()
    if up.y < 0:
        up = -up
    for k in range(4):
        p = a + (b - a) * (0.15 + 0.22 * k) + up * 0.1
        m.cylx("HeadRound%d" % (k + 1), tuple(p), 0.42, 0.14, BRASS, "Metal", collide=False)
    # antenna
    m.block("HeadAntennaBase", (-1.6, 5.0, 1.55), (0.3, 0.14, 0.3), DARK, "Metal", collide=False)
    m.cyl("HeadAntenna", (-1.6, 5.0, 1.55), (-1.6, 6.05, 1.55), 0.1, DARK, "Metal", collide=False)
    m.ball("HeadAntennaTip", (-1.6, 6.1, 1.55), 0.24, CYAN, "Neon", collide=False)

    # =============================================================== BARRELS (pitch)
    m.cylx("BarrelMantlet", (0, TY, 0), 2.12, 1.9, GUN, "Metal")
    m.block("BarrelMantletPlate", (0, TY, -0.96), (1.9, 1.1, 0.26), GUN_LT, "Metal")
    for i, (bx, by) in enumerate(((0.78, 0.4), (-0.78, 0.4), (0.78, -0.4), (-0.78, -0.4))):
        m.cyl("BarrelPlateBolt%d" % (i + 1), (bx, TY + by, -1.07), (bx, TY + by, -1.15), 0.16, STEEL_LT, "Metal",
              collide=False)
    for s, t in ((1, "L"), (-1, "R")):
        x = s * BARREL_X
        m.cyl("BarrelTube" + t, (x, TY, -1.0), (x, TY, -3.3), 0.54, STEEL, "Metal")
        m.cyl("BarrelSleeve" + t, (x, TY, -1.05), (x, TY, -2.2), 0.70, DARK, "Metal")
        m.cyl("BarrelRibA" + t, (x, TY, -1.26), (x, TY, -1.38), 0.82, ORANGE, "SmoothPlastic")
        m.cyl("BarrelRibB" + t, (x, TY, -1.9), (x, TY, -2.02), 0.82, ORANGE, "SmoothPlastic")
        m.block("BarrelBrake" + t, (x, TY, -3.41), (0.8, 0.8, 0.42), GUN_LT, "Metal")
        for k, z in enumerate((-3.3, -3.5)):
            m.block("BarrelSlot%s%d" % (t, k + 1), (s * (BARREL_X + 0.405), TY, z), (0.05, 0.5, 0.08), DARK,
                    "Metal", collide=False)
        m.cyl("BarrelRing" + t, (x, TY, MUZZLE_Z + 0.16), (x, TY, MUZZLE_Z), 0.86, CYAN, "Neon")
        m.cyl("BarrelBore" + t, (x, TY, MUZZLE_Z + 0.03), (x, TY, MUZZLE_Z - 0.04), 0.4, DARK, "SmoothPlastic",
              collide=False)
    m.block("BarrelClamp", (0, TY, -2.62), (1.8, 0.7, 0.3), GUN, "Metal")
    m.block("BarrelMuzzleGlow", (0, TY, MUZZLE_Z + 0.06), (1.0, 0.18, 0.1), CYAN, "Neon")

    # =============================================================== data
    m.pivot("YawPivot", (0, 2.2, 0))
    m.pivot("PitchPivot", (0, TY, 0))
    m.pivot("MuzzleTipL", (BARREL_X, TY, MUZZLE_Z - 0.09))
    m.pivot("MuzzleTipR", (-BARREL_X, TY, MUZZLE_Z - 0.09))
    m.pivot("EyeLens", (0, EYE_Y, -0.33))
    m.pivot("DrumCentre", (0, 3.55, 2.6))
    m.attr("Cost", 25000)
    m.attr("PropSet", "defence")
    m.attr("Notes", "Turret rebuilt 2026-09-24 (fun-builds/models/build_Turret.py, primlib parts). Rig by name prefix "
                    "(DefenceService set 1): Base* static; Head* yaw about the vertical axis through BasePlinth "
                    "(x = z = 0); Barrel* pitch about the X axis through HeadTrunnion (0, %.2f, 0). Barrels point -Z at "
                    "rest; BarrelMuzzleGlow is centred between the muzzles (x = +/-%.1f), shots leave its CFrame * "
                    "(+/-0.5, 0, -0.15). Every yawing part stays within radius 4 at pitch -25..+45, and no moving "
                    "part cuts another deeper than 0.03 at any yaw / pitch (build_Turret.py clash_sweep)."
                    % (TY, BARREL_X))
    info = m.finish()
    report(info)
    return info


# ---------------------------------------------------------------- rig self-check
def _corners(p):
    sx, sy, sz = p["size"]
    c = p["cf"]
    R = Matrix(((c[3], c[4], c[5]), (c[6], c[7], c[8]), (c[9], c[10], c[11])))
    t = Vector(c[:3])
    out = []
    for dx in (-0.5, 0.5):
        for dy in (-0.5, 0.5):
            for dz in (-0.5, 0.5):
                out.append(R @ Vector((dx * sx, dy * sy, dz * sz)) + t)
    return out


def report(info):
    """Rig asserts, the radius / footprint numbers (box corners = conservative) and the CLASH SWEEP: every
    moving part against everything it can pass, posed exactly like DefenceService.PoseTurret over its whole
    range (see clash_sweep). Fails the build when anything cuts deeper than CLASH_LIMIT."""
    parts = info["parts"]
    by = {p["name"]: p for p in parts}
    plinth = by["BasePlinth"]["cf"]
    trun = by["HeadTrunnion"]
    glow = by["BarrelMuzzleGlow"]
    assert abs(plinth[0]) < 1e-4 and abs(plinth[2]) < 1e-4, "BasePlinth must be centred on x = z = 0"
    assert trun["shape"] == "Cylinder" and abs(trun["cf"][0]) < 1e-4, "HeadTrunnion: an X-axis cylinder on x = 0"
    assert glow["material"] == "Neon" and glow["color"] == CYAN and abs(glow["cf"][0]) < 1e-4
    assert abs(glow["cf"][1] - trun["cf"][1]) < 1e-4, "MuzzleGlow must sit on the barrel axis height"
    ty, tz = trun["cf"][1], trun["cf"][2]
    head_r, barrel_r = 0.0, 0.0
    static_x = static_z = 0.0
    for p in parts:
        n = p["name"]
        cs = _corners(p)
        if n.startswith("Head"):
            head_r = max(head_r, max(math.hypot(v.x, v.z) for v in cs))
        elif n.startswith("Barrel"):
            for deg in PITCHES:
                a = math.radians(deg)
                for v in cs:
                    y, z = v.y - ty, v.z - tz
                    z2 = y * math.sin(a) + z * math.cos(a) + tz
                    barrel_r = max(barrel_r, math.hypot(v.x, z2))
        else:
            assert n.startswith("Base"), "static part not named Base*: " + n
            static_x = max(static_x, max(abs(v.x) for v in cs))
            static_z = max(static_z, max(abs(v.z) for v in cs))
    print("RIGCHECK head r %.2f, barrel r (pitch %d..%d) %.2f, static |x| %.2f |z| %.2f, parts %d, trunnion y %.2f"
          % (head_r, PITCHES[0], PITCHES[-1], barrel_r, static_x, static_z, len(parts), ty))
    assert head_r <= 4.0 and barrel_r <= 4.0, "yawing parts leave radius 4"
    assert static_x <= 4.0 and static_z <= 4.0, "static base leaves the 8 x 8 tile"
    assert len(parts) <= 140, "part budget"

    t0 = time.time()
    worst, skipped = clash_sweep(parts, ty, tz)
    rows = sorted(worst.items(), key=lambda kv: -kv[1][0])
    print("CLASHSWEEP %.1f s: pitch %d..%d every 1 deg, yaw every %g deg, samples %.2f studs; pitch-invariant "
          "(skipped vs Head): %s" % (time.time() - t0, PITCHES[0], PITCHES[-1], YAW_STEP, SAMPLE, ", ".join(skipped)))
    for (a, b), (d, yaw, pitch) in rows[:12]:
        print("CLASHSWEEP   %.3f  %s -> %s  (yaw %s, pitch %s)" % (d, a, b, "-" if yaw is None else "%g" % yaw,
                                                                  "-" if pitch is None else pitch))
    bad = [(k, v) for k, v in rows if v[0] > CLASH_LIMIT]
    assert not bad, "moving parts cut deeper than %.2f: %s" % (CLASH_LIMIT, bad)


# ---------------------------------------------------------------- clash sweep (numpy ships with Blender)
PITCHES = list(range(-25, 46))   # DefenceService TURRET.MinPitch .. MaxPitch (degrees), every degree
YAW_STEP = 2.0                   # degrees, the full circle
SAMPLE = 0.05                    # surface sample spacing (studs)
CLASH_LIMIT = 0.03               # deepest allowed cut of a moving part into anything it passes
_MARGIN = 0.05


def _np_frame(p):
    c = p["cf"]
    return np.array(c[3:12], dtype=float).reshape(3, 3), np.array(c[:3], dtype=float)


def _lin(size, h):
    return np.linspace(-size / 2, size / 2, max(2, int(math.ceil(size / h)) + 1))


def _grid(a, b):
    A, B = np.meshgrid(a, b, indexing="ij")
    return A.ravel(), B.ravel()


def _surface(p, h=SAMPLE):
    """World points on the part's surface about h apart (edges and rims included; an Ellipsoid uses its box)."""
    sx, sy, sz = p["size"]
    shape = p["shape"]
    if shape == "Cylinder":
        r = sy / 2
        a = np.linspace(0, 2 * math.pi, max(24, int(math.ceil(2 * math.pi * r / h))), endpoint=False)
        X, A = _grid(_lin(sx, h), a)
        pts = [np.stack([X, r * np.cos(A), r * np.sin(A)], -1)]
        for rr in np.linspace(0, r, max(2, int(math.ceil(r / h)) + 1))[:-1]:
            b = np.linspace(0, 2 * math.pi, max(1, int(math.ceil(2 * math.pi * rr / h))), endpoint=False)
            for x in (-sx / 2, sx / 2):
                pts.append(np.stack([np.full(len(b), x), rr * np.cos(b), rr * np.sin(b)], -1))
        L = np.concatenate(pts)
    elif shape == "Ball":
        r = sx / 2
        pts = []
        for th in np.linspace(0, math.pi, max(8, int(math.ceil(math.pi * r / h))) + 1):
            rr = r * math.sin(th)
            b = np.linspace(0, 2 * math.pi, max(1, int(math.ceil(2 * math.pi * rr / h))), endpoint=False)
            pts.append(np.stack([rr * np.cos(b), np.full(len(b), r * math.cos(th)), rr * np.sin(b)], -1))
        L = np.concatenate(pts)
    else:
        X, Y, Z = _lin(sx, h), _lin(sy, h), _lin(sz, h)
        pts = []
        for s in (-0.5, 0.5):
            a, b = _grid(Y, Z)
            pts.append(np.stack([np.full(len(a), s * sx), a, b], -1))
            a, b = _grid(X, Z)
            pts.append(np.stack([a, np.full(len(a), s * sy), b], -1))
            a, b = _grid(X, Y)
            pts.append(np.stack([a, b, np.full(len(a), s * sz)], -1))
        L = np.concatenate(pts)
        if shape == "Wedge":             # keep the solid's faces (slope rises toward +Z) and add the slope
            L = L[sz * (L[:, 1] + sy / 2) - sy * (L[:, 2] + sz / 2) <= 1e-9]
            a, t = _grid(X, np.linspace(0, 1, max(2, int(math.ceil(math.hypot(sy, sz) / h)) + 1)))
            L = np.concatenate([L, np.stack([a, -sy / 2 + t * sy, -sz / 2 + t * sz], -1)])
    R, t = _np_frame(p)
    return L @ R.T + t


def _depth(p, W):
    """How deep world points W (N x 3) lie inside part p: distance to its nearest face, > 0 inside."""
    R, t = _np_frame(p)
    L = (W - t) @ R
    sx, sy, sz = p["size"]
    if p["shape"] == "Cylinder":
        return np.minimum(sy / 2 - np.hypot(L[:, 1], L[:, 2]), sx / 2 - np.abs(L[:, 0]))
    if p["shape"] == "Ball":
        return sx / 2 - np.linalg.norm(L, axis=1)
    d = np.minimum(np.minimum(sx / 2 - np.abs(L[:, 0]), sy / 2 - np.abs(L[:, 1])), sz / 2 - np.abs(L[:, 2]))
    if p["shape"] == "Wedge":
        d = np.minimum(d, (sy * (L[:, 2] + sz / 2) - sz * (L[:, 1] + sy / 2)) / math.hypot(sy, sz))
    return d


def _pitch(W, deg, piv):
    """CFrame.Angles(pitch, 0, 0) about the X axis through piv (positive = barrels up)."""
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    return (W - piv) @ np.array(((1.0, 0.0, 0.0), (0.0, c, -s), (0.0, s, c))).T + piv


def _yaws(W, degs):
    """CFrame.Angles(0, yaw, 0) about the vertical axis x = z = 0 for every yaw: (N, 3) -> (len(degs), N, 3)."""
    a = np.radians(np.asarray(degs, dtype=float))[:, None]
    c, s = np.cos(a), np.sin(a)
    x, z = W[None, :, 0], W[None, :, 2]
    return np.stack([x * c + z * s, np.broadcast_to(W[None, :, 1], c.shape[:1] + W.shape[:1]), -x * s + z * c], -1)


def clash_sweep(parts, ty, tz):
    """Pose the rig exactly like DefenceService.PoseTurret (Head* yaw about x = z = 0, Barrel* pitch about the
    X axis through the trunnion (0, ty, tz), then yaw) and measure how deep every moving part cuts into what it
    can pass: Barrel vs Head over every pitch (they yaw together), Head and Barrel vs Base over every yaw x
    pitch. Depth = the deepest surface sample of either part inside the other (both directions, so a corner
    poking into a face counts). Pitch-invariant barrel parts (an X-axis cylinder on the pitch axis: the
    mantlet) look the same at every pitch, so their overlaps with the head are construction, not clashes.
    Returns ({(moving, other): (depth, yaw or None, pitch or None)} for depth > 0.005, [skipped names])."""
    t_start = time.time()
    M = _MARGIN
    piv = np.array((0.0, ty, tz))
    yaws = np.arange(0.0, 360.0, YAW_STEP)
    head = [p for p in parts if p["name"].startswith("Head")]
    barrel = [p for p in parts if p["name"].startswith("Barrel")]
    base = [p for p in parts if not p["name"].startswith(("Head", "Barrel"))]
    S = {p["name"]: _surface(p) for p in parts}
    worst = {}

    def note(a, b, d, yaw, pitch):
        d = float(d)
        if d > 0.005 and d > worst.get((a, b), (0.0,))[0]:
            worst[(a, b)] = (round(d, 3), None if yaw is None else float(yaw), pitch)

    def invariant(p):
        R, t = _np_frame(p)
        return p["shape"] == "Cylinder" and abs(abs(R[0, 0]) - 1) < 1e-6 and abs(t[1] - ty) < 1e-4 \
            and abs(t[2] - tz) < 1e-4

    # every moving part's samples posed at each pitch (yaw 0): name -> (pitches, K x N x 3)
    posed = {p["name"]: ([None], S[p["name"]][None]) for p in head}
    for p in barrel:
        posed[p["name"]] = (PITCHES, np.stack([_pitch(S[p["name"]], d, piv) for d in PITCHES]))

    def pitch_env(name):
        # what a pitch keeps: the x range and the distance from the pitch axis (0 when the box holds the axis)
        P = S[name]
        a = np.hypot(P[:, 1] - ty, P[:, 2] - tz)
        holds = P[:, 1].min() <= ty <= P[:, 1].max() and P[:, 2].min() <= tz <= P[:, 2].max()
        return P[:, 0].min(), P[:, 0].max(), 0.0 if holds else a.min(), a.max()

    env = {p["name"]: pitch_env(p["name"]) for p in head + barrel}
    timing = [time.time()]

    # ---- 1) Barrel vs Head: only the pitch matters
    skipped = [b["name"] for b in barrel if invariant(b)]
    for b in barrel:
        if b["name"] in skipped:
            continue
        ks, Wb = posed[b["name"]]
        flat = Wb.reshape(-1, 3)
        kid = np.repeat(np.arange(len(ks)), Wb.shape[1])
        blo, bhi = flat.min(0) - M, flat.max(0) + M
        bx0, bx1, ba0, ba1 = env[b["name"]]
        for hd in head:
            Sh = S[hd["name"]]
            lo, hi = Sh.min(0) - M, Sh.max(0) + M
            if np.any(lo > bhi) or np.any(hi < blo):
                continue
            hx0, hx1, ha0, ha1 = env[hd["name"]]
            if hx0 > bx1 + M or hx1 < bx0 - M or ha0 > ba1 + M or ha1 < ba0 - M:
                continue
            m = np.all((flat >= lo) & (flat <= hi), axis=1)
            if m.any():                                  # barrel samples inside the head part
                d = _depth(hd, flat[m])
                i = int(d.argmax())
                note(b["name"], hd["name"], d[i], None, ks[kid[m][i]])
            q = Sh[np.all((Sh >= blo) & (Sh <= bhi), axis=1)]
            if len(q):                                   # head samples inside the pitched barrel part
                d = _depth(b, np.concatenate([_pitch(q, -k, piv) for k in ks]))
                i = int(d.argmax())
                note(b["name"], hd["name"], d[i], None, ks[i // len(q)])

    # ---- 2) Head + Barrel vs Base: every yaw x pitch
    timing.append(time.time())
    for s in base:
        Ss = S[s["name"]]
        sy0, sy1 = Ss[:, 1].min() - M, Ss[:, 1].max() + M
        rs = np.hypot(Ss[:, 0], Ss[:, 2])
        axis_in = Ss[:, 0].min() <= 0 <= Ss[:, 0].max() and Ss[:, 2].min() <= 0 <= Ss[:, 2].max()
        rs0, rs1 = (0.0 if axis_in else rs.min() - M), rs.max() + M
        for mp in head + barrel:
            ks, Wm = posed[mp["name"]]
            flat = Wm.reshape(-1, 3)
            if flat[:, 1].max() < sy0 or flat[:, 1].min() > sy1:
                continue
            rf = np.hypot(flat[:, 0], flat[:, 2])        # yaw keeps y and the distance from the yaw axis
            m = (flat[:, 1] >= sy0) & (flat[:, 1] <= sy1) & (rf >= rs0) & (rf <= rs1)
            if m.any():                                  # moving samples inside the base part
                c = flat[m]
                kk = np.repeat(np.arange(len(ks)), Wm.shape[1])[m]
                d = _depth(s, _yaws(c, yaws).reshape(-1, 3))
                j = int(d.argmax())
                note(mp["name"], s["name"], d[j], yaws[j // len(c)], ks[kk[j % len(c)]])
            q = Ss[(Ss[:, 1] >= flat[:, 1].min() - M) & (Ss[:, 1] <= flat[:, 1].max() + M) & (rs <= rf.max() + M)]
            if not len(q):
                continue
            V = _yaws(q, -yaws).reshape(-1, 3)           # base samples seen from the yawed head frame
            yid = np.repeat(np.arange(len(yaws)), len(q))
            if ks[0] is not None:                        # pitch keeps x and the distance from the pitch axis
                mx0, mx1, _a0, ma1 = env[mp["name"]]
                av = np.hypot(V[:, 1] - ty, V[:, 2] - tz)
                keep = (V[:, 0] >= mx0 - M) & (V[:, 0] <= mx1 + M) & (av <= ma1 + M)
                V, yid = V[keep], yid[keep]
                if not len(V):
                    continue
            order = np.argsort(V[:, 1])                  # slice by height per pitch (yaw keeps y)
            V, yid = V[order], yid[order]
            vr = np.hypot(V[:, 0], V[:, 2])
            ylo, yhi = Wm[:, :, 1].min(1) - M, Wm[:, :, 1].max(1) + M
            rhi = np.hypot(Wm[:, :, 0], Wm[:, :, 2]).max(1) + M
            for ki, k in enumerate(ks):                  # base samples inside the posed moving part
                i0, i1 = np.searchsorted(V[:, 1], (ylo[ki], yhi[ki]))
                sel = np.arange(i0, i1)[vr[i0:i1] <= rhi[ki]]
                if not len(sel):
                    continue
                d = _depth(mp, V[sel] if k is None else _pitch(V[sel], -k, piv))
                j = int(d.argmax())
                note(mp["name"], s["name"], d[j], yaws[yid[sel[j]]], k)
    timing.append(time.time())
    print("CLASHSWEEP stages: samples+pose %.1f s, barrel vs head %.1f s, moving vs base %.1f s"
          % (timing[0] - t_start, timing[1] - timing[0], timing[2] - timing[1]))
    return worst, skipped
