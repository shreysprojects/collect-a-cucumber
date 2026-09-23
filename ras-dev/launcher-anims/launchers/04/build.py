"""04 Leather Sling -- whirl the sling, let fly down the track.

The sling is one rigid mesh: grip ring (pivot, in the right hand) -> two cords -> leather pouch
3.9 studs out.  The launcher's forward axis (pivot -Y) points from the ring to the pouch, its top
(pivot -Z) is the pouch opening.  meta/04.json: Seat/Muzzle look = the opening (pivot -Z), so the
ball leaves the pouch along the direction the pouch travels (the opening leads the swing), which
is what a real sling does (tangential release).  All motion is baked EVERY FRAME from procedural
channels (the cords turn through full circles, so the Launcher bone takes big turns: the ring
spinning on the finger).

  Ready    the right forearm is cocked up (wrist ~1.7, elbow down), the sling hangs near plumb and
           swings through it like a pendulum (8 +/- 23 deg, front/back, hung clear of the thigh); breathing, eyes down-track.
  ChargeLo WHIRL: the pouch orbits the hand in a big circle on the character's right/front side,
           in a plane facing the pad camera (tilted 30 deg back, so the top of the circle passes
           over the right shoulder); 1 revolution per loop, even.  The wrist drives a 0.3-stud
           circle leading the pouch by 75 deg; the chest counter-sways, the hips bob as the pouch
           passes the bottom, and the body leans away (left) as it sweeps over the top.
  ChargeHi the SAME revolution (same phase, 1 revolution per loop: the runtime Lerps Lo and Hi at the
           same ChargeTime, so 2 revolutions would snap the sling at mid charge) but a BIGGER, EVEN
           whirl: the hand drives a 0.8-stud circle only 25 deg ahead of the pouch (its speed adds to the
           cords'), same 30 deg plane as Lo, centre raised so the circle is ~8 studs tall on screen and
           clears the floor, near-zero whip (4 deg) -> pouch 31-41 studs/s (Lo 29-31), faster than Lo
           at every frame; the body pumps, crouches and leans with it, hand tremor 8x per loop.
  Every baked frame of Lo, Hi and a 50 % Lo/Hi pose blend is tested: sling mesh vs the Head and
  arm blocks with a 0.05 margin (REPORTPENCHECK).
  Arms: arm_hinge() gives every IK solve an explicit, continuous elbow hinge (torso +X) and soft-
  clamps the wrist target inside reach, so the audit sees no elbow flips or upper-arm roll snaps;
  in Fire the shoulder-to-wrist distance is its own smooth channel (rd/rw) through the drive.
  Fire     (authored on an OLD_FA = 0.30 timeline, replayed through warp(): the pre-release path is
           re-timed by the pouch's own arc length so its speed RISES steadily from V0 = 44 studs/s,
           above the ChargeHi bottom, to the release peak at FIRE_AT 0.22; afterwards the authored
           timeline resumes at a rate relaxing to 1.  Through the release P is the sling's RING (pv),
           which travels down the track and rises, so the Seat climbs along T through FireAt.)
           From the bottom of the whirl the pouch carries forward, rises on the camera side while
           the body coils, then the whole body snaps toward the track and the arm drives overhand:
           the pouch comes over the top-front travelling DOWN THE TRACK at full speed -> the ball
           leaves the pouch opening (FireAt) -> the empty sling whips on over and down in front,
           swings back and dangles again (Ready).
  The final whirl lives on a sphere parameterised by psi (angle round the release circle, 0 = the
  release point) and beta (tilt of that circle toward the character's front).  The release
  circle contains the down-track travel direction T (16 deg up), so at psi = 0 the pouch moves
  exactly along T.
"""
import importlib
import math
import os
import sys

HERE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import launcherlib as L
importlib.reload(L)
from mathutils import Vector

LID = 4
OUT = os.path.dirname(os.path.abspath(__file__))
L.use_launcher(LID)

FIRE_AT = 0.22
OLD_FA = 0.30          # the Fire keys below are authored on this timeline; warp() retimes them
SPEC = {
    "Ready": 2.0, "ChargeLo": 0.8, "ChargeHi": 0.8, "Fire": 1.4,
    "FireAt": FIRE_AT,
    "Ball": {"show": "Charge", "start": "Seat", "grow": 1.0},
    "Fx": {"Style": "snow", "Color": [1.0, 1.0, 1.0], "Charge": "snow", "ChargeColor": [0.95, 0.97, 1.0]},
    "TwoHanded": False,
    "AllowFootLift": False,
    "Notes": "sling: dangles + sways, whirls a big circle beside the body while charging, "
             "the body snaps and the arm whips overhand; the pouch releases the ball tangentially "
             "down the track at the top-front of the arc",
}
EXTRA = [0.04, 0.08, 0.12, 0.16, 0.19, 0.20, 0.24, 0.27, 0.32, 0.40, 0.50, 0.66]
FEET = {"Left": (-0.9, -0.3), "Right": (0.65, 0.35)}
V = Vector

# default plane (Ready hint, Fire settle): faces the pad camera (+X), tilted 45 deg back; the
# charge whirl uses plane(LO_TILT..HI_TILT) below
TILT = math.radians(45.0)
N_PLANE = V((math.cos(TILT), math.sin(TILT), 0.0))       # plane normal = pouch opening
U_UP = V((-math.sin(TILT), math.cos(TILT), 0.0))         # in-plane "up"
E_FRONT = V((0.0, 0.0, -1.0))                            # in-plane "front" (screen-right)

# release circle (Fire): travel direction at release T, cords at release e1(beta)
ELEV = math.radians(16.0)
T_REL = V((-math.cos(ELEV), math.sin(ELEV), 0.0))        # down-track, 16 deg up
N0 = V((math.sin(ELEV), math.cos(ELEV), 0.0))            # "up" in the vertical track plane

SEAT_POS = V(L.load_meta(LID)["Seat"]["pos"])

stats = {"overreach": 0.0, "anchor_err": 0.0, "left_over": 0.0, "worst": ""}
CUR = {"label": "", "d": None}
DD = {}


def plane(tilt_deg):
    """whirl plane tilted tilt_deg back from vertical: (normal toward the camera, in-plane up)"""
    tl = math.radians(tilt_deg)
    return V((math.cos(tl), math.sin(tl), 0.0)), V((-math.sin(tl), math.cos(tl), 0.0))


def whirl_dir(theta_deg, up=U_UP):
    a = math.radians(theta_deg)
    return (math.cos(a) * E_FRONT + math.sin(a) * up).normalized()


def e1_of(beta_deg):
    b = math.radians(beta_deg)
    return math.cos(b) * N0 + math.sin(b) * E_FRONT


def fire_dir(psi_deg, beta_deg):
    p = math.radians(psi_deg)
    return (math.cos(p) * e1_of(beta_deg) + math.sin(p) * T_REL).normalized()


def fire_travel(psi_deg, beta_deg):
    p = math.radians(psi_deg)
    return (-math.sin(p) * e1_of(beta_deg) + math.cos(p) * T_REL).normalized()


def psi_beta_of(d, cos_negative):
    """inverse of fire_dir: pick the branch with cos(psi) < 0 or > 0"""
    d = V(d).normalized()
    s = d.dot(T_REL)
    c = math.sqrt(max(0.0, 1.0 - s * s)) * (-1.0 if cos_negative else 1.0)
    psi = math.degrees(math.atan2(s, c))
    beta = math.degrees(math.atan2(d.dot(E_FRONT) / c, d.dot(N0) / c))
    return psi, beta


# ------------------------------------------------------------------ channel poses
def ready_ch(t):
    s = t / SPEC["Ready"]
    w = 2.0 * math.pi * s
    b = 0.5 - 0.5 * math.cos(w)                  # breathing 0..1
    phi = math.radians(RD_PHI0 + RD_PHIA * math.sin(w))  # pendulum through plumb (+ = toward the front)
    base = V((0.2, -1.0, 0.0)).normalized()
    d = (math.cos(phi) * base + math.sin(phi) * E_FRONT).normalized()
    sway = -0.05 * math.sin(w)                   # the hand reacts against the swing
    return {
        "P": V((1.4, RD_Y + 0.05 * b, -0.8 - sway)), "d": d, "hint": N_PLANE.copy(),
        "yaw": 10.0 + 1.5 * math.sin(w), "lean": -3.0 - 1.5 * b, "drop": 0.12 + 0.04 * b, "back": 0.06,
        "wyaw": -3.0 + 1.0 * math.sin(w), "wbend": -2.0 - 2.0 * b,
        "lw": V((-1.55, -0.62 + 0.03 * b, -0.05 + 0.04 * math.sin(w))), "lelb": V((-0.3, -0.4, 1.0)),
        "look": V((-9.0, -0.5 + 0.3 * b, -2.0)), "relb": V((0.6, -1.0, 0.5)),
        "roll": 0.0, "wroll": 0.0, "rhinge": V(RD_RH), "lhinge": V(RD_LH), "rd": 1.3, "rw": 0.0,
    }


RD_Y, RD_PHI0, RD_PHIA = 1.68, 8.0, 23.0
RD_RH, RD_LH = (1.0, 0.0, 0.0), (1.0, 0.0, 0.0)      # elbow hinges (UpperTorso-local)


def charge_ch(t, k):
    """k 0 = ChargeLo, 1 = ChargeHi; one revolution per loop, same phase in both"""
    T = SPEC["ChargeLo"]
    s = (t / T) % 1.0
    w = 2.0 * math.pi * s
    A = HI_WHIP * k                              # whip: fast through the bottom, hangs over the top
    theta = -90.0 + 360.0 * s + A * math.sin(w)
    C = V(LO_C) + k * (V(HI_C) - V(LO_C))
    nrm, up = plane(LO_TILT + k * (HI_TILT - LO_TILT))   # Lo: steeper circle, its top over the shoulder
    rh = LO_RH + (HI_RH - LO_RH) * k             # the hand drives the orbit at every charge
    th = math.radians(theta + LO_LEAD + (HI_LEAD - LO_LEAD) * k)   # the hand leads the pouch
    P = C + rh * (math.cos(th) * E_FRONT + math.sin(th) * up)
    shake = HI_SHAKE * k * math.sin(8.0 * w)
    P = P + V((0.0, shake, 0.4 * shake))
    wp = w + 0.35                                # body drive peaks as the pouch passes the bottom
    duck = (0.5 + 0.5 * math.cos(math.radians(theta - 110.0))) ** 2
    return {
        "P": P, "d": whirl_dir(theta, up), "hint": nrm,
        "yaw": 8.0 - 3.0 * k + (3.0 + 9.0 * k) * math.sin(wp),
        "lean": -4.0 - 9.0 * k - (1.5 + 1.5 * k) * math.cos(wp),
        "drop": 0.18 + 0.12 * k + (0.035 + 0.085 * k) * math.cos(wp),
        "back": 0.08 + 0.08 * k,
        "wyaw": -4.0 + (3.5 + 2.5 * k) * math.cos(th),
        "wbend": -2.0 - 4.0 * k - (3.0 + 2.0 * k) * math.cos(wp),
        "lw": V((-1.65 - 0.5 * k, -0.35 + 0.9 * k + 0.05 * math.sin(w), -0.55)),
        "lelb": V((-0.2, -1.0, 0.5)),
        "look": V((-10.0, 0.5 + 0.5 * k, -1.5)), "relb": V((0.7, -0.9, 0.2)),
        # the body leans away (left) from the sling as the pouch sweeps over the top: the head ducks
        # out from under the cords
        "roll": ROLL[0] * duck, "wroll": ROLL[1] * duck,
        "rhinge": V(CH_RH), "lhinge": V(CH_LH), "rd": 1.3, "rw": 0.0,
    }


LO_C, HI_C, HI_WHIP, LO_TILT = (1.72, 1.0, -1.2), (1.6, 1.5, -0.8), 4.0, 30.0
HI_TILT = 30.0
LO_RH, HI_RH, LO_LEAD, HI_LEAD, HI_SHAKE = 0.30, 0.80, 75.0, 25.0, 0.06
ROLL = (6.0, 10.0)                                # root / waist side lean (deg) at the top of the whirl
CH_RH, CH_LH = (1.0, 0.0, 0.0), (1.0, 0.0, 0.0)


REACH = math.sqrt(L.ARM_SIDE_OFFSET ** 2 + (L.UPPER_ARM + L.LOWER_ARM) ** 2)
R_SOFT, R_MAX = REACH - 0.32, REACH - 0.16      # targets soft-clamped inside full reach (no flips)


def arm_hinge(side, target, hinge=(1.0, 0.0, 0.0), rd=0.0, rw=0.0):
    """two-bone IK with an explicit, continuous elbow HINGE (UpperTorso-local; +X = the torso's
    right: the upper arm's side offset lies along it, the forearm flexes about it).  The hinge is
    projected perpendicular to shoulder->wrist, so it never jumps (no guard mirroring, no roll
    snaps); the wrist target is soft-clamped inside reach so the elbow never pops straight."""
    sh = L.joint(side + "UpperArm")
    Mt = L.frame_of("UpperTorso")
    Mi = Mt.inverted()
    dv = V(target) - sh
    DD.setdefault(CUR["label"], {})[side] = round(dv.length, 2)
    D = dv.length
    if rw > 0.0:                                 # Fire: the shoulder distance is its own smooth channel
        dv = dv * (((1.0 - rw) * D + rw * rd) / D)
        D = dv.length
    if D > R_SOFT:
        span = R_MAX - R_SOFT
        D2 = R_SOFT + span * math.tanh((D - R_SOFT) / span)
        stats["clamped"] = max(stats.get("clamped", 0.0), round(D - D2, 3))
        dv = dv * (D2 / D)
    t = (Mi @ dv).normalized()
    h = V(hinge).normalized()
    h = h - h.dot(t) * t
    if h.length < 0.2:
        stats.setdefault("hinge_weak", []).append((CUR["label"], side, round(h.length, 2)))
    h.normalize()
    pole = Mt @ h.cross(t)
    return L.arm_to(side, sh + dv, pole)


def apply(ch):
    L.reset_pose()
    yaw = ch["yaw"]
    L.stance(hip_drop=ch["drop"], hip_back=ch["back"],
             root=L.ry(yaw) @ L.rx(ch["lean"]) @ L.rz(ch.get("roll", 0.0)), feet=FEET,
             foot_yaw={"Left": 18.0, "Right": max(8.0, 0.8 * yaw)})
    L.waist(L.ry(ch["wyaw"]) @ L.rx(ch["wbend"]) @ L.rz(ch.get("wroll", 0.0)))
    if "psi" in ch:                              # Fire: cords + opening from the release sphere
        d = fire_dir(ch["psi"], ch["beta"])
        tr = fire_travel(ch["psi"], ch["beta"])
        m = max(0.0, min(1.0, ch["hmix"]))
        h = (tr * (1.0 - m) + N_PLANE * m)
    else:
        d = V(ch["d"]).normalized()
        h = V(ch["hint"])
    CUR["d"] = d.copy()
    u = (h - h.dot(d) * d).normalized()
    # P = the right WRIST.  Straight wrist; the sling turns on its ring (Launcher bone) so the
    # cords point along d with the pouch opening toward u.
    pv = max(0.0, min(1.0, ch.get("pv", 0.0)))
    tgt = V(ch["P"])
    for _ in range(4 if pv > 0.0 else 1):      # pv: P is where the RING goes (fixed point on the grip offset)
        over, werr = arm_hinge("Right", tgt, ch.get("rhinge", (1.0, 0.0, 0.0)),
                               ch.get("rd", 0.0), max(0.0, min(1.0, ch.get("rw", 0.0))))
        if pv <= 0.0:
            break
        L.update()
        off = L.pivot_cf().to_translation() - L.joint("RightHand")
        tgt = V(ch["P"]) - pv * off
    P0 = L.hand_cf("Right") @ L.G_GRIP()
    A = L.look_frame((0.0, -1.0, 0.0), (0.0, 0.0, -1.0))
    want = L.look_frame(d, u) @ A.inverted()
    L.set_rot("Launcher", (P0.to_3x3().inverted() @ want).to_quaternion())
    L.update()
    got = L.pivot_cf().to_3x3() @ A @ Vector((0.0, 0.0, -1.0))
    info = {"arm_overreach": over, "anchor_err": round(werr + L.angle_between(got, d) / 100.0, 3)}
    lo, _ = arm_hinge("Left", V(ch["lw"]), ch.get("lhinge", (1.0, 0.0, 0.0)),
                      ch.get("lrd", 0.0), max(0.0, min(1.0, ch.get("lrw", 0.0))))
    L.head_look(target=V(ch["look"]))
    if info["arm_overreach"] > stats["overreach"]:
        stats["overreach"] = info["arm_overreach"]
        stats["over_at"] = CUR["label"]
    if info["anchor_err"] > stats["anchor_err"]:
        stats["anchor_err"] = info["anchor_err"]
        stats["worst"] = CUR["label"]
    if info["anchor_err"] > 0.15:
        stats.setdefault("bad", []).append((CUR["label"], info["anchor_err"]))
    stats["left_over"] = max(stats["left_over"], lo)
    return info


# ------------------------------------------------------------------ keyed tracks (Fire)
def track(keys, name, t):
    """non-uniform Catmull-Rom (Hermite) through (time, channels) keys; zero tangent at the end"""
    ts = [k[0] for k in keys]
    vals = [k[1][name] for k in keys]
    if t <= ts[0]:
        return vals[0]
    if t >= ts[-1]:
        return vals[-1]
    i = max(j for j in range(len(ts) - 1) if ts[j] <= t)

    def tan(j):
        if j == 0:
            return (vals[1] - vals[0]) / (ts[1] - ts[0])
        if j == len(ts) - 1:
            return vals[j] * 0.0
        return (vals[j + 1] - vals[j - 1]) / (ts[j + 1] - ts[j - 1])

    t0, t1 = ts[i], ts[i + 1]
    hh = t1 - t0
    s = (t - t0) / hh
    h00 = 2 * s ** 3 - 3 * s ** 2 + 1
    h10 = s ** 3 - 2 * s ** 2 + s
    h01 = -2 * s ** 3 + 3 * s ** 2
    h11 = s ** 3 - s ** 2
    return vals[i] * h00 + tan(i) * (h10 * hh) + vals[i + 1] * h01 + tan(i + 1) * (h11 * hh)


def K(base, **kw):
    ch = {k: (v.copy() if isinstance(v, Vector) else v) for k, v in base.items()}
    for k, v in kw.items():
        ch[k] = V(v) if isinstance(v, tuple) else v
    return ch


hi0 = charge_ch(0.0, 1.0)
rd0 = ready_ch(0.0)
PSI0, BETA0 = psi_beta_of(hi0["d"], True)       # ~ -120, 0
PSI_R, BETA_R = psi_beta_of(rd0["d"], True)     # the Ready dangle (~ +209 after one more half turn)
PSI_R += 360.0 if PSI_R < 0 else 0.0
hi0 = K(hi0, psi=PSI0, beta=BETA0, hmix=0.0, pv=0.0, lrd=1.3, lrw=0.0)
rd0 = K(rd0, psi=PSI_R, beta=BETA_R, hmix=1.0, pv=0.0, lrd=0.95, lrw=0.0)


def psi_pre(t, a=0.8, p=2.3):
    """(authored timeline) whip into the release: psi -> 0 at OLD_FA"""
    x = max(0.0, min(1.0, t / OLD_FA))
    return PSI0 * (1.0 - a * x - (1.0 - a) * x ** p)


PSI_RATE_END = (0.8 + 0.2 * 2.3) * abs(PSI0) / OLD_FA   # psi_pre's rate at the release


# ring path through the release (0.25 / release / 0.34): along T, slightly rising; psi after it
PV_KEYS = [(1.3, 1.45, -0.5), (0.92, 1.78, -0.58), (0.55, 1.96, -0.66)]
PSI_POST = (23.0, 60.0)
REL_BETA = 63.0

# body key values
FIRE_KEYS = [
    (0.00, hi0),
    # the pouch carries on forward through the bottom while the hand pulls it round the camera side
    # the pouch carries on forward through the bottom (charge momentum) ...
    (0.05, K(hi0, psi=psi_pre(0.05), beta=-22.0, P=(1.88, 0.88, -1.62), yaw=5.0, lean=-10.0, drop=0.45,
             wyaw=-6.0, wbend=-5.0, lw=(-2.2, 0.8, -0.65), look=(-10.0, 1.0, -1.5))),
    # ... while the hand pulls it round the camera side
    (0.10, K(hi0, psi=psi_pre(0.10), beta=-30.0, P=(1.8, 0.9, -1.15), yaw=0.0, lean=-6.0, drop=0.44,
             wyaw=-10.0, wbend=-2.0, lw=(-2.3, 0.85, -0.75), look=(-9.0, 2.0, -2.0))),
    # coil: pouch rising out on the camera side, hand cocked back, body turned away from the track,
    # a glance up at the pouch
    (0.15, K(hi0, psi=psi_pre(0.15), beta=0.0, P=(1.8, 1.0, -0.65), yaw=-4.0, lean=-2.0, drop=0.42,
             wyaw=-14.0, wbend=2.0, lw=(-2.35, 0.95, -0.8), look=(-8.0, 3.0, -2.5), rd=1.4, rw=0.5)),
    (0.20, K(hi0, psi=psi_pre(0.20), beta=36.0, P=(1.6, 1.15, -0.4), yaw=-6.0, lean=0.0, drop=0.4,
             wyaw=-16.0, wbend=4.0, lw=(-2.35, 0.95, -0.8), look=(-7.0, 4.0, -3.0), rd=1.42, rw=1.0,
             lrd=1.3, lrw=1.0)),
    # SNAP: hips + chest whip toward the track, the arm drives overhand
    # from here P = the sling's RING (pv 1): the ring itself travels down the track, rising along T,
    # so the pouch keeps climbing through the release (psi at 0.25 only sets the release tangent)
    (0.25, K(hi0, psi=PSI_POST[0] - 0.09 * PSI_RATE_END, beta=58.0, P=PV_KEYS[0], yaw=12.0, lean=-5.0,
             drop=0.36, wyaw=-4.0, wbend=-3.0, lw=(-2.2, 0.7, -0.5), look=(-9.0, 3.0, -2.0), rd=1.40, rw=1.0,
             pv=1.0, lrd=1.2, lrw=1.0)),
    # RELEASE: pouch at the top-front, travelling straight down the track
    (OLD_FA, K(hi0, psi=0.0, beta=REL_BETA, P=PV_KEYS[1], yaw=36.0, lean=-7.0, drop=0.26,
                wyaw=12.0, wbend=-5.0, lw=(-1.8, 0.3, 0.1), look=(-10.0, 1.6, -1.3), rd=1.40, rw=1.0, pv=1.0,
                lrd=1.08, lrw=1.0)),
    # follow-through: the empty sling whips on over and down across the front
    (0.34, K(hi0, psi=PSI_POST[0], beta=REL_BETA - 4.0, P=PV_KEYS[2], yaw=42.0, lean=-8.0, drop=0.26,
             wyaw=14.0, wbend=-7.0, lw=(-1.4, -0.1, 0.6), look=(-10.0, 1.7, -1.3), rd=1.40, rw=1.0, pv=1.0,
             lrd=1.0, lrw=1.0)),
    (0.40, K(hi0, psi=PSI_POST[1], beta=42.0, P=(0.1, 1.3, -1.55), yaw=46.0, lean=-12.0, drop=0.32,
             wyaw=15.0, wbend=-11.0, lw=(-1.2, -0.4, 0.8), look=(-10.0, 1.4, -1.3), rd=1.1, rw=1.0, pv=0.4,
             lrd=0.95, lrw=0.5)),
    # the arm finishes down and ACROSS the body, the empty pouch sweeping low in front
    (0.48, K(hi0, psi=98.0, beta=-20.0, P=(-0.2, 0.45, -2.1), yaw=46.0, lean=-11.0, drop=0.34,
             wyaw=14.0, wbend=-14.0, lw=(-1.25, -0.5, 0.75), look=(-10.0, 1.1, -1.3), rd=1.1, rw=0.3)),
    (0.58, K(hi0, psi=150.0, beta=-35.0, P=(-0.3, 0.55, -1.8), yaw=42.0, lean=-12.0, drop=0.33,
             wyaw=11.0, wbend=-15.0, lw=(-1.3, -0.55, 0.6), look=(-10.0, 1.0, -1.4), relb=(1.1, 0.2, 0.0))),
    (0.72, K(hi0, psi=182.0, beta=-40.0, P=(0.1, 0.95, -1.55), yaw=34.0, lean=-12.0, drop=0.28,
             wyaw=9.0, wbend=-11.0, lw=(-1.35, -0.6, 0.45), look=(-10.0, 0.8, -1.5), hmix=0.0,
             relb=(0.9, -0.9, 0.0))),
    # recover: the pouch swings on forward under the hand, back, settles into the Ready dangle
    (0.90, K(rd0, psi=PSI_R + 12.0, beta=BETA_R - 4.0, P=(1.0, 1.3, -1.2), yaw=24.0, lean=-7.0, drop=0.2,
             wyaw=3.0, wbend=-5.0, lw=(-1.4, -0.62, 0.2), look=(-9.5, 0.0, -1.8), hmix=0.5)),
    (1.12, K(rd0, psi=PSI_R - 6.0, beta=BETA_R + 2.0, P=(1.45, 1.62, -0.9), yaw=14.0, lean=-4.0, drop=0.14,
             wbend=-3.0, hmix=0.9)),
    (1.40, rd0),
]


def sample_old(to):
    """the authored Fire at authored time `to` (release at OLD_FA)"""
    ch = {name: track(FIRE_KEYS, name, to) for name in FIRE_KEYS[0][1]}
    if to < OLD_FA:
        ch["psi"] = psi_pre(to)          # the whip path itself, not its spline
    return ch


# ---- retiming: the authored pre-release path is replayed at a pouch speed that RISES steadily
# from V0 (above the ChargeHi bottom speed: the final whirl keeps its momentum) to the release
# peak at FIRE_AT; after the release the authored timeline resumes (rate r0 relaxing to 1)
V0, P_EXP, TAU = 44.0, 0.8, 0.15
WARP = {}


def build_warp(n=150):
    tos = [OLD_FA * i / n for i in range(n + 1)]
    Q, PV, SH, WR = [], [], [], []
    for to in tos:
        CUR["label"] = "Warp %.3f" % to
        apply(sample_old(to))
        Q.append(L.launcher_point(SEAT_POS))
        PV.append(L.pivot_cf().to_translation())
        SH.append(L.joint("RightUpperArm"))
        WR.append((L.joint("RightHand") - SH[-1]).length)
    S = [0.0]
    for i in range(n):
        S.append(S[-1] + (Q[i + 1] - Q[i]).length)
    h = 1.0 / 300.0
    apply(sample_old(OLD_FA + h))
    v_old = (L.launcher_point(SEAT_POS) - Q[-1]).length / h
    stot = S[-1]
    v1 = V0 + (stot - V0 * FIRE_AT) * (P_EXP + 1.0) / FIRE_AT
    WARP.update(tos=tos, S=S, stot=stot, v1=v1, r0=v1 / v_old)
    print("REPORTWARP path %.2f studs, v0 %.1f -> v1 %.1f studs/s, old release speed %.1f, r0 %.2f" % (
        stot, V0, v1, v_old, v1 / v_old))
    for i in range(0, n + 1, 5):
        print("REPORTOLD to=%.3f seat (%.2f %.2f %.2f) S=%.2f piv (%.2f %.2f %.2f) sh (%.2f %.2f %.2f) wr %.2f" % (
            tos[i], Q[i].x, Q[i].y, Q[i].z, S[i], PV[i].x, PV[i].y, PV[i].z, SH[i].x, SH[i].y, SH[i].z, WR[i]))


def probe_post():
    prev = None
    PQ = [None]
    for i in range(0, 31):
        to = OLD_FA + 0.01 * i
        ch = sample_old(to)
        apply(ch)
        q = L.launcher_point(SEAT_POS)
        pv_ = L.pivot_cf().to_translation()
        v = 0.0 if prev is None else (q - prev).length / 0.01
        prev = q
        qa = L.get_rot("RightUpperArm").copy()
        ua = 0.0 if i == 0 else math.degrees(qa.rotation_difference(PQ[0]).angle)
        PQ[0] = qa
        print("REPORTPOST to=%.2f psi %.0f beta %.0f seat (%.2f %.2f %.2f) piv (%.2f %.2f %.2f) v %.0f wr %.2f ua %.0f" % (
            to, ch["psi"], ch["beta"], q.x, q.y, q.z, pv_.x, pv_.y, pv_.z, v,
            (L.joint("RightHand") - L.joint("RightUpperArm")).length, ua))


def warp(t):
    if t >= FIRE_AT:
        dt = t - FIRE_AT
        return OLD_FA + dt + (WARP["r0"] - 1.0) * TAU * (1.0 - math.exp(-dt / TAU))
    x = t / FIRE_AT
    s = V0 * t + (WARP["v1"] - V0) * FIRE_AT * x ** (P_EXP + 1.0) / (P_EXP + 1.0)
    S, tos = WARP["S"], WARP["tos"]
    if s >= S[-1]:
        return OLD_FA
    i = max(0, min(len(S) - 2, next(j for j in range(len(S) - 1) if S[j + 1] >= s)))
    f = (s - S[i]) / max(1e-9, S[i + 1] - S[i])
    return tos[i] + f * (tos[i + 1] - tos[i])


def sample_fire(t):
    return sample_old(warp(t))


# ------------------------------------------------------------------ baking
MEAS = {}
LVERTS = [v.co.copy() for v in L.launcher_object().data.vertices]
MARGIN = 0.05                                    # cords/pouch must stay this far out of these parts
STRICT = ("Head", "RightUpperArm", "RightLowerArm", "LeftUpperArm", "LeftLowerArm", "LeftHand")
PEN = {}                                         # label -> {part: worst depth (+ = inside, margin incl.)}
DBG, PIV = {}, {}


def pen_now(label):
    """launcher mesh vs body blocks (right hand + the ring next to it skipped).  depth > 0 = within
    MARGIN of (or inside) the block, measured as the box-axis excess (a lower bound on distance)."""
    L.update()
    mw = L.launcher_object().matrix_world
    boxes = [b for b in L.body_boxes() if b[0] != "RightHand"]
    inv = [(name, box.inverted(), half) for name, box, half in boxes]
    piv = L.pivot_cf().to_translation()
    PIV[label] = tuple(round(c, 2) for c in piv) + tuple(
        (n, tuple(round(c, 2) for c in b.to_translation()), tuple(round(c, 2) for c in h))
        for n, b, h in boxes if n in ("Head", "RightUpperArm"))
    worst = {}
    for co in LVERTS:
        p = L.b2r(mw @ co)
        if (p - piv).length < 0.6:
            continue
        for name, bi, half in inv:
            q = bi @ p
            pen = min(half.x - abs(q.x), half.y - abs(q.y), half.z - abs(q.z)) + MARGIN
            if pen > 0.0:
                if pen > worst.get(name, 0.0):
                    DBG[(label, name)] = (round((p - piv).length, 2), tuple(round(c, 2) for c in p))
                worst[name] = max(worst.get(name, 0.0), pen)
    for name, v in worst.items():
        key = (label.split()[0], name)
        if v > PEN.get(key, (0.0, ""))[0]:
            PEN[key] = (v, label)
    return worst


def blend_check(t):
    """the runtime mixes Lo and Hi by the live charge: test the 50 % mix at the same phase"""
    CUR["label"] = "Blend50 %.2f" % t
    apply(charge_ch(t, 0.0))
    a = L.snapshot()
    apply(charge_ch(t, 1.0))
    b = L.snapshot()
    L.restore(L.blend_snapshots(a, b, 0.5))
    pen_now(CUR["label"])


def bake(kind, length, pose_at, loop, extra=None):
    L.new_clip(kind)
    rig = L.rig()
    prev, first = {}, {}
    n = int(round(length * L.FPS))
    seats, dirs = [], []
    for f in range(n + 1):
        t = 0.0 if (loop and f == n) else f / L.FPS
        if extra is not None:
            extra(t)
        CUR["label"] = "%s %.2f" % (kind, t)
        pose_at(t)
        L.update()
        pen_now(CUR["label"])
        seats.append(L.launcher_point(SEAT_POS))
        dirs.append(CUR["d"].copy())
        for pb in rig.pose.bones:          # quaternion sign continuity (full turns!)
            q = pb.rotation_quaternion
            if loop and f == n:
                pb.rotation_quaternion = first[pb.name].copy()
            elif pb.name in prev and q.dot(prev[pb.name]) < 0.0:
                pb.rotation_quaternion = -q
            prev[pb.name] = pb.rotation_quaternion.copy()
            if f == 0:
                first[pb.name] = pb.rotation_quaternion.copy()
        L.key(f)
    if loop:
        L.make_cyclic(kind)
    L.set_interpolation(kind, 'LINEAR', 'VECTOR')
    sp = [(seats[i + 1] - seats[i]).length * L.FPS for i in range(n)]
    ang = [L.angle_between(dirs[i], dirs[i + 1]) * L.FPS for i in range(n)]
    MEAS[kind] = (seats, sp, ang)
    print("REPORTSP %s " % kind + " ".join("%.0f" % v for v in sp))
    print("REPORTSEATY %s " % kind + " ".join("%.2f" % q.y for q in seats))
    print("REPORTSPD %s max pouch %.0f studs/s (f%d), max cord turn %.0f deg/s, low seat y %.2f" % (
        kind, max(sp), sp.index(max(sp)), max(ang), min(s.y for s in seats)))


build_warp()
if os.environ.get("B04_WARPONLY"):
    probe_post()
    print("REPORTHINGE %s" % stats.get("hinge_weak", [])[:12])
    sys.exit(0)
bake("Ready", SPEC["Ready"], lambda t: apply(ready_ch(t)), True)
bake("ChargeLo", SPEC["ChargeLo"], lambda t: apply(charge_ch(t, 0.0)), True)
bake("ChargeHi", SPEC["ChargeHi"], lambda t: apply(charge_ch(t, 1.0)), True, extra=blend_check)
bake("Fire", SPEC["Fire"], lambda t: apply(sample_fire(t)), False)

bad = []
for (clip, part), (v, lab) in sorted(PEN.items()):
    print("REPORTPEN %-8s %-14s %.2f at %s  vert %s pivot %s" % (clip, part, v, lab, DBG.get((lab, part)),
                                                                   PIV.get(lab)))
    if clip in ("ChargeLo", "ChargeHi", "Blend50") and part in STRICT:
        bad.append("%s %s %.2f" % (lab, part, v))
print("REPORTPENCHECK " + ("OK" if not bad else "FAIL " + "; ".join(bad)))

seats, sp, ang = MEAS["Fire"]
for f in range(0, 20):
    s = seats[f]
    print("REPORTFIRE f%02d t=%.3f D %s seat (%.2f %.2f %.2f) v=%.0f turn=%.0f" % (
        f, f / L.FPS, DD.get("Fire %.2f" % (f / L.FPS)), s.x, s.y, s.z, sp[f], ang[f]))
print("REPORTPSI psi0 %.1f beta0 %.1f psiR %.1f betaR %.1f" % (PSI0, BETA0, PSI_R, BETA_R))
hw = stats.pop("hinge_weak", [])
print("REPORTIK " + str({k: (round(v, 3) if isinstance(v, float) else v) for k, v in stats.items()}))
print("REPORTHINGE weak %d %s" % (len(hw), hw[:8]))
for lab, chf in (("Lo0", lambda: charge_ch(0.0, 0.0)), ("Hi0", lambda: charge_ch(0.0, 1.0)), ("Rd0", lambda: ready_ch(0.0))):
    CUR["label"] = lab
    apply(chf())
    print("REPORTSH %s R %s L %s" % (lab, tuple(round(c, 2) for c in L.joint("RightUpperArm")),
                                     tuple(round(c, 2) for c in L.joint("LeftUpperArm"))))
if not os.environ.get("B04_NOFINISH"):
    L.finish(SPEC, OUT, extra_times=EXTRA)
