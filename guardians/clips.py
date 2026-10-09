"""Animation clips for the ten guardians, emitted as `clips.json` for Studio.

    py clips.py

Every guardian's build script already exports the key POSES the concept sheet asks for -
`Sit` (asleep on its seat), `Awake` (the hero pose), usually `Run` and a signature pose -
and `buildall.manifest_json()` copies them into `manifest.json`.  This file turns those
key poses into the seven CLIPS the chase system needs, converts every rotation out of
Blender space into a Roblox quaternion, and writes one JSON the Studio side can build
KeyframeSequences from without doing any maths of its own.

THE CLIPS
  SitIdle       loop  the asleep pose, breathing
  Wake          once  Sit -> Awake, with an overshoot so it lands hard
  Run           loop  the Run pose and its MIRROR, which is a whole stride cycle
  Grab          once  Awake -> lunge -> Awake
  ReturnToSeat  once  Awake -> Sit
  Stunned       loop  bat-knocked: folded over, wobbling
  <signature>   once  bespoke per guardian (see SIGNATURE below)

THE SPACE CONVERSION is the part worth reading.  A pose is authored as (rx, ry, rz)
degrees about the BLENDER world axes, applied XYZ.  Blender maps onto Roblox by
M = Rx(-90 deg): (bx, by, bz) -> (bx, bz, -by).  A rotation R_b about Blender axes is
therefore the rotation `M . R_b . M^-1` about Roblox axes - conjugation, not a
component swap.  We build the full matrix and hand Roblox a QUATERNION, so no Euler
ordering convention has to agree across the two engines.

The Motor6D joints are built world-aligned (install.lua puts each attachment at the
joint with identity world rotation), so a Pose CFrame here is exactly the rotation the
joint applies - no per-part frame correction is needed.
"""
import json, math, os

HERE = os.path.dirname(os.path.abspath(__file__))
MANIFEST = os.path.join(HERE, "manifest.json")
OUT = os.path.join(HERE, "clips.json")


# ----------------------------------------------------------------- tiny matrix maths
def mat_mul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]


def rot_x(t):
    c, s = math.cos(t), math.sin(t)
    return [[1, 0, 0], [0, c, -s], [0, s, c]]


def rot_y(t):
    c, s = math.cos(t), math.sin(t)
    return [[c, 0, s], [0, 1, 0], [-s, 0, c]]


def rot_z(t):
    c, s = math.cos(t), math.sin(t)
    return [[c, -s, 0], [s, c, 0], [0, 0, 1]]


def transpose(m):
    return [[m[j][i] for j in range(3)] for i in range(3)]


M = rot_x(math.radians(-90.0))        # Blender -> Roblox
M_INV = transpose(M)


def euler_to_roblox_quat(rx, ry, rz):
    """Blender XYZ euler degrees -> Roblox quaternion (qx, qy, qz, qw)."""
    rb = mat_mul(rot_z(math.radians(rz)), mat_mul(rot_y(math.radians(ry)),
                                                  rot_x(math.radians(rx))))
    r = mat_mul(M, mat_mul(rb, M_INV))
    t = r[0][0] + r[1][1] + r[2][2]
    if t > 0:
        s = math.sqrt(t + 1.0) * 2.0
        qw, qx, qy, qz = 0.25 * s, (r[2][1] - r[1][2]) / s, (r[0][2] - r[2][0]) / s, (r[1][0] - r[0][1]) / s
    elif r[0][0] > r[1][1] and r[0][0] > r[2][2]:
        s = math.sqrt(1.0 + r[0][0] - r[1][1] - r[2][2]) * 2.0
        qw, qx, qy, qz = (r[2][1] - r[1][2]) / s, 0.25 * s, (r[0][1] + r[1][0]) / s, (r[0][2] + r[2][0]) / s
    elif r[1][1] > r[2][2]:
        s = math.sqrt(1.0 + r[1][1] - r[0][0] - r[2][2]) * 2.0
        qw, qx, qy, qz = (r[0][2] - r[2][0]) / s, (r[0][1] + r[1][0]) / s, 0.25 * s, (r[1][2] + r[2][1]) / s
    else:
        s = math.sqrt(1.0 + r[2][2] - r[0][0] - r[1][1]) * 2.0
        qw, qx, qy, qz = (r[1][0] - r[0][1]) / s, (r[0][2] + r[2][0]) / s, (r[1][2] + r[2][1]) / s, 0.25 * s
    n = math.sqrt(qx * qx + qy * qy + qz * qz + qw * qw) or 1.0
    return [round(qx / n, 6), round(qy / n, 6), round(qz / n, 6), round(qw / n, 6)]


def loc_to_roblox(v):
    """A Blender offset (dx, dy, dz) -> Roblox (dx, dz, -dy)."""
    return [round(v[0], 4), round(v[2], 4), round(-v[1], 4)]


# ----------------------------------------------------------------- pose algebra
def scale(pose, k):
    return {p: tuple(v * k for v in r) for p, r in pose.items()}


def add(a, b, k=1.0):
    out = dict(a)
    for p, r in b.items():
        o = out.get(p, (0.0, 0.0, 0.0))
        out[p] = tuple(o[i] + r[i] * k for i in range(3))
    return out


def blend(a, b, t):
    out = {}
    for p in set(a) | set(b):
        va, vb = a.get(p, (0, 0, 0)), b.get(p, (0, 0, 0))
        out[p] = tuple(va[i] + (vb[i] - va[i]) * t for i in range(3))
    return out


def mirror(pose):
    """Reflect a pose through the x = 0 plane: swap _R and _L, and flip the two
    rotation components that change sign under that reflection.  One key pose plus its
    mirror IS a stride cycle, which is where Run comes from."""
    out = {}
    for p, (rx, ry, rz) in pose.items():
        q = p
        if p.endswith("_R"):
            q = p[:-2] + "_L"
        elif p.endswith("_L"):
            q = p[:-2] + "_R"
        out[q] = (rx, -ry, -rz)
    return out


def only(pose, parts):
    return {p: r for p, r in pose.items() if p in parts}


# ----------------------------------------------------------------- the generic clips
def generic_clips(g, poses, parts, depth):
    """The six clips every guardian gets, derived from its own key poses."""
    sit = poses.get("Sit", {})
    awake = poses.get("Awake", {})
    run = poses.get("Run", awake)
    has = lambda n: n in parts

    # a part near the top of the rig to breathe with, whatever this guardian is built of
    torso = next((n for n in ("Torso", "Body", "Core", "Carapace", "Head", "Hips", "Neck")
                  if has(n)), None)
    breathe = {torso: (-1.6, 0.0, 0.0)} if torso else {}

    clips = {}

    clips["SitIdle"] = {"loop": True, "priority": "Idle", "keys": [
        {"t": 0.0, "pose": sit},
        {"t": 1.6, "pose": add(sit, breathe)},
        {"t": 3.2, "pose": sit},
    ]}

    # Wake: a shudder back, then up fast, overshooting past Awake before settling
    clips["Wake"] = {"loop": False, "priority": "Action", "keys": [
        {"t": 0.00, "pose": sit},
        {"t": 0.18, "pose": blend(sit, awake, -0.12)},
        {"t": 0.62, "pose": blend(sit, awake, 1.12)},
        {"t": 0.86, "pose": blend(sit, awake, 0.94)},
        {"t": 1.10, "pose": awake},
    ]}

    clips["Run"] = {"loop": True, "priority": "Movement", "keys": [
        {"t": 0.00, "pose": run},
        {"t": 0.22, "pose": blend(run, mirror(run), 0.5)},
        {"t": 0.44, "pose": mirror(run)},
        {"t": 0.66, "pose": blend(mirror(run), run, 0.5)},
        {"t": 0.88, "pose": run},
    ]}

    # Grab: wind back, then everything that can reach throws forward
    reach = {}
    for n in parts:
        if n.startswith(("ArmUpper", "ArmLower", "Claw", "Pincer", "Fist", "Hand",
                         "JawTop", "Mandible", "Head", "Neck")):
            reach[n] = (-26.0, 0.0, 0.0) if n.startswith(("Head", "Neck")) else (-34.0, 0.0, 0.0)
    clips["Grab"] = {"loop": False, "priority": "Action", "keys": [
        {"t": 0.00, "pose": awake},
        {"t": 0.20, "pose": add(awake, scale(reach, -0.45))},
        {"t": 0.42, "pose": add(awake, reach)},
        {"t": 0.78, "pose": awake},
    ]}

    clips["ReturnToSeat"] = {"loop": False, "priority": "Action", "keys": [
        {"t": 0.00, "pose": awake},
        {"t": 0.45, "pose": blend(awake, sit, 0.55)},
        {"t": 1.00, "pose": sit},
    ]}

    # Stunned: the WHOLE rig goes slack and sways.  This one is driven by the rig's
    # TOPOLOGY, not by part names - a worm, a crab and a hovering drone have no part
    # called ArmUpper, and a name-matched fold left them moving one joint out of fifty.
    # Every joint droops by an amount that decays with its depth, so whatever the
    # guardian is built of, it visibly sags.
    fold = {}
    for n in parts:
        d = depth.get(n, 0)
        if d == 0 or n in ("Hitbox",):
            continue
        droop = {1: -26.0, 2: -15.0, 3: -9.0}.get(d, -5.0)
        side = 1.0 if n.endswith("_R") else (-1.0 if n.endswith("_L") else 0.0)
        fold[n] = (droop, side * 22.0 / d, 0.0)
    sway = lambda k: add(fold, {n: (0.0, 0.0, k * (9.0 if depth.get(n, 9) == 1 else 4.0))
                                for n in parts if 0 < depth.get(n, 0) <= 2})
    clips["Stunned"] = {"loop": True, "priority": "Action", "keys": [
        {"t": 0.0, "pose": sway(1.0)},
        {"t": 0.9, "pose": sway(-1.0)},
        {"t": 1.8, "pose": sway(1.0)},
    ]}
    return clips


# ----------------------------------------------------------------- the signature clips
# One bespoke clip each - the move the sheet names.  Written against the part names each
# build script actually creates; anything missing is dropped with a warning rather than
# silently doing nothing.
def signature_clips(g, poses, parts):
    awake = poses.get("Awake", {})
    p = lambda *names: [n for n in names if n in parts]

    def clip(name, keys, loop=False, prio="Action"):
        return name, {"loop": loop, "priority": prio, "keys": keys}

    if g == "Strawman":
        # crow shake: the whole body convulses side to side and the crows leave
        shake = lambda k: add(awake, {n: (0.0, 0.0, 9.0 * k) for n in p("Torso", "Head", "Hat")})
        return dict([clip("CrowShake", [
            {"t": 0.0, "pose": awake}, {"t": 0.14, "pose": shake(1)},
            {"t": 0.28, "pose": shake(-1)}, {"t": 0.42, "pose": shake(1)},
            {"t": 0.56, "pose": shake(-0.6)}, {"t": 0.80, "pose": awake}])])

    if g == "Dune":
        # dive and surface: fold down into the sand, then burst back up, jaws open
        down = {n: (0.0, 0.0, 0.0) for n in []}
        for i, n in enumerate(p("Body1", "Body2", "Body3", "Body4", "Body5", "Body6")):
            down[n] = (34.0 - i * 3.0, 0.0, 0.0)
        for n in p("Neck", "Head"):
            down[n] = (26.0, 0.0, 0.0)
        return dict([clip("DiveSurface", [
            {"t": 0.0, "pose": awake}, {"t": 0.45, "pose": down},
            {"t": 0.95, "pose": down}, {"t": 1.35, "pose": blend(down, awake, 1.15)},
            {"t": 1.60, "pose": awake}])])

    if g == "Kabuto":
        # ground slam: a long wind-up over the head, then down hard, then the recovery
        up, down = {}, {}
        for n in p("ArmUpper_R", "ArmLower_R"):
            up[n] = (0.0, -92.0, 0.0)
            down[n] = (0.0, 46.0, 0.0)
        for n in p("Torso"):
            up[n] = (16.0, 0.0, 0.0)
            down[n] = (-30.0, 0.0, 0.0)
        for n in p("Head"):
            up[n] = (10.0, 0.0, 0.0)
            down[n] = (-22.0, 0.0, 0.0)
        return dict([clip("Slam", [
            {"t": 0.0, "pose": awake}, {"t": 0.70, "pose": add(awake, up)},
            {"t": 0.92, "pose": add(awake, up)}, {"t": 1.06, "pose": add(awake, down)},
            {"t": 1.60, "pose": awake}])])

    if g == "Brisket":
        # charge and skid: head down, pound forward, then plant and slide sideways
        charge, skid = {}, {}
        for n in p("Neck", "Head"):
            charge[n] = (22.0, 0.0, 0.0)
            skid[n] = (-16.0, 0.0, 0.0)
        for n in p("Body"):
            charge[n] = (-8.0, 0.0, 0.0)
            skid[n] = (6.0, 0.0, 14.0)
        for i, n in enumerate(p("LegUpperF_R", "LegUpperF_L", "LegUpperB_R", "LegUpperB_L")):
            charge[n] = (38.0 if i % 2 == 0 else -30.0, 0.0, 0.0)
            skid[n] = (-24.0, 0.0, 0.0)
        return dict([clip("Charge", [
            {"t": 0.0, "pose": awake}, {"t": 0.30, "pose": add(awake, charge)},
            {"t": 0.60, "pose": add(awake, mirror(charge))},
            {"t": 0.90, "pose": add(awake, charge)},
            {"t": 1.25, "pose": add(awake, skid)}, {"t": 1.75, "pose": awake}], loop=False)])

    if g == "Frostbite":
        # throw a snowball: reach back over the shoulder, then hurl it forward
        back, fwd = {}, {}
        for n in p("ArmUpper_R"):
            back[n] = (0.0, -78.0, 0.0)
            fwd[n] = (0.0, 52.0, 0.0)
        for n in p("ArmLower_R"):
            back[n] = (0.0, -40.0, 0.0)
            fwd[n] = (0.0, 24.0, 0.0)
        for n in p("Body", "Head"):
            back[n] = (12.0, 0.0, 0.0)
            fwd[n] = (-18.0, 0.0, 0.0)
        return dict([clip("Throw", [
            {"t": 0.0, "pose": awake}, {"t": 0.55, "pose": add(awake, back)},
            {"t": 0.74, "pose": add(awake, fwd)}, {"t": 1.20, "pose": awake}])])

    if g == "Pinch":
        # claw snap: the big claw opens wide and slams shut, twice
        openc, shut = {}, {}
        for n in p("PincerTop_R", "PincerTop_L"):
            openc[n] = (0.0, -34.0, 0.0)
            shut[n] = (0.0, 6.0, 0.0)
        for n in p("ClawArm_R", "ClawPalm_R"):
            openc[n] = (0.0, -14.0, 0.0)
            shut[n] = (0.0, 8.0, 0.0)
        return dict([clip("Snap", [
            {"t": 0.0, "pose": awake}, {"t": 0.22, "pose": add(awake, openc)},
            {"t": 0.34, "pose": add(awake, shut)}, {"t": 0.58, "pose": add(awake, openc)},
            {"t": 0.70, "pose": add(awake, shut)}, {"t": 1.00, "pose": awake}])])

    if g == "Ember":
        # hurl the lava rock: wind the whole body back, then throw through
        back, fwd = {}, {}
        for n in p("ArmUpper_R", "ArmLower_R"):
            back[n] = (0.0, -68.0, 0.0)
            fwd[n] = (0.0, 48.0, 0.0)
        for n in p("Core", "Head"):
            back[n] = (14.0, 0.0, 0.0)
            fwd[n] = (-20.0, 0.0, 0.0)
        return dict([clip("Throw", [
            {"t": 0.0, "pose": awake}, {"t": 0.62, "pose": add(awake, back)},
            {"t": 0.82, "pose": add(awake, fwd)}, {"t": 1.30, "pose": awake}])])

    if g == "Orbit":
        # blink: fold in around itself, vanish, snap open again - the rocks whip round
        tuck = {}
        for n in p("Hand_R", "Hand_L"):
            tuck[n] = (0.0, 0.0, 46.0 if n.endswith("_R") else -46.0)
        for n in p("Torso", "Head", "Swirl"):
            tuck[n] = (0.0, 0.0, 0.0)
        for i, n in enumerate(p("OrbitRock1", "OrbitRock2", "OrbitRock3", "OrbitRock4",
                                "OrbitRock5", "OrbitRock6")):
            tuck[n] = (0.0, 0.0, 180.0 + i * 12.0)
        return dict([clip("Blink", [
            {"t": 0.0, "pose": awake}, {"t": 0.22, "pose": add(awake, tuck)},
            {"t": 0.34, "pose": add(awake, scale(tuck, 2.0))},
            {"t": 0.60, "pose": awake}])])

    if g == "Tick":
        # rewind: the arms drop dead, the body sags, and the key spins hard
        sag = {}
        for n in p("ArmUpper_R", "ArmUpper_L"):
            sag[n] = (0.0, 66.0 if n.endswith("_R") else -66.0, 0.0)
        for n in p("Body", "Head"):
            sag[n] = (-16.0, 0.0, 0.0)
        keys = [{"t": 0.0, "pose": awake}, {"t": 0.35, "pose": add(awake, sag)}]
        key_part = "Key" if "Key" in parts else None
        for i in range(1, 5):                        # the key turns through the sag
            pose = add(awake, sag)
            if key_part:
                pose = add(pose, {key_part: (0.0, 0.0, -150.0 * i)})
            keys.append({"t": 0.35 + 0.24 * i, "pose": pose})
        keys.append({"t": 1.60, "pose": awake})
        return dict([clip("Rewind", keys)])

    if g == "Scan":
        # blink: the visor sweeps, the pods flare, then it snaps to a new facing
        sweep, flare = {}, {}
        for n in p("Head"):
            sweep[n] = (0.0, 0.0, 34.0)
        for n in p("Pod_R", "Pod_L"):
            flare[n] = (0.0, 0.0, 26.0 if n.endswith("_R") else -26.0)
        for n in p("Fin_FR", "Fin_FL", "Fin_BR", "Fin_BL"):
            flare[n] = (14.0, 0.0, 0.0)
        return dict([clip("Blink", [
            {"t": 0.0, "pose": awake}, {"t": 0.30, "pose": add(awake, sweep)},
            {"t": 0.46, "pose": add(add(awake, sweep), flare)},
            {"t": 0.56, "pose": add(awake, {n: (0.0, 0.0, -34.0) for n in p("Head")})},
            {"t": 0.90, "pose": awake}])])

    return {}


# ----------------------------------------------------------------- emit
def main():
    man = json.load(open(MANIFEST, encoding="utf-8"))
    out, warnings = {}, []
    for g, m in man["models"].items():
        parts = set(m["rig"].keys())
        # joint depth: 0 for the root, 1 for its children, and so on
        depth = {}

        def _depth(n, guard=0):
            if n in depth:
                return depth[n]
            par = m["rig"][n]["parent"]
            depth[n] = 0 if (not par or guard > 30) else _depth(par, guard + 1) + 1
            return depth[n]

        for _n in parts:
            _depth(_n)
        poses = {k: {p: tuple(v) for p, v in pose.items()}
                 for k, pose in (m.get("poses") or {}).items()}
        pose_loc = m.get("pose_loc") or {}
        clips = generic_clips(g, poses, parts, depth)
        sig = signature_clips(g, poses, parts)
        if not sig:
            warnings.append("%s: no signature clip" % g)
        clips.update(sig)

        baked = {}
        for cname, c in clips.items():
            keys = []
            for k in c["keys"]:
                poses_out, unknown = {}, []
                for part, r in k["pose"].items():
                    if part not in parts:
                        unknown.append(part)
                        continue
                    poses_out[part] = euler_to_roblox_quat(r[0], r[1], r[2])
                if unknown:
                    warnings.append("%s/%s: pose names no such part: %s"
                                    % (g, cname, ", ".join(sorted(set(unknown)))))
                entry = {"t": round(k["t"], 3), "rot": poses_out}
                # the Sit poses carry a root offset that drops the rig onto its seat
                loc = pose_loc.get("Sit") if cname in ("SitIdle", "ReturnToSeat") else None
                if loc:
                    entry["loc"] = {p: loc_to_roblox(v) for p, v in loc.items()}
                keys.append(entry)
            baked[cname] = {"loop": c["loop"], "priority": c["priority"], "keys": keys,
                            "length": max(k["t"] for k in c["keys"])}
        out[g] = baked

    data = {"models": out,
            "space": "rotations are Roblox quaternions (qx, qy, qz, qw) for the Motor6D "
                     "Transform; joints are world-aligned, so no per-part correction",
            "warnings": warnings}
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=1)
    total = sum(len(c) for c in out.values())
    print("wrote %s (%d guardians, %d clips, %d bytes)"
          % (OUT, len(out), total, os.path.getsize(OUT)))
    for g in sorted(out):
        print("  %-10s %s" % (g, ", ".join("%s(%.2fs%s)" % (n, c["length"], " loop" if c["loop"] else "")
                                           for n, c in sorted(out[g].items()))))
    for w in warnings:
        print("  WARN", w)


if __name__ == "__main__":
    main()
