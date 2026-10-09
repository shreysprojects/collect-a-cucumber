"""Slide fix-pass geometry check (authored Roblox frame, origin = identity, scaled world = authored * S).
Emulates server/Slide.lua MakeTrusses exactly and plots the two trusses over the real ladder / deck / hoop /
chute geometry of props/build_slide.py (Blender (x, y, z) -> Roblox (x, z, -y)). Also prints the start-window
and sit-lift numbers per physique stage for the client fixes."""
import math, sys
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Polygon, Circle

S = float(sys.argv[1]) if len(sys.argv) > 1 else 1.5
OUT = sys.argv[2] if len(sys.argv) > 2 else "slide_trusses.png"

# ---- server constants (keep in step with server/Slide.lua)
DECK_Y = 4.40
DECK_Z0, DECK_Z1 = 2.45, 4.18
LADDER_FOOT = np.array([0, 0.12, 5.04])
LADDER_TOP = np.array([0, 4.70, 4.32])
LADDER_RAIL_X = 1.42
TRUSS_FACE_OUT, TRUSS_WIDTH, TRUSS_TOP_DROP = 0.25, 2.0, 0.05

def unit(v): return v / np.linalg.norm(v)

up = unit(LADDER_TOP - LADDER_FOOT)
back = np.array([0, -up[2], up[1]])
upW, backW = up, back                      # origin = identity rotation
rightW = np.cross(upW, backW)
topY = (DECK_Y * S - TRUSS_TOP_DROP - back[1] * TRUSS_FACE_OUT) / S
axisTop = LADDER_FOOT + up * ((topY - LADDER_FOOT[1]) / up[1])
faceTop = axisTop * S + backW * TRUSS_FACE_OUT
length = max(2, 2 * math.ceil((DECK_Y * S + 0.6) / up[1] / 2))
centre = faceTop - backW * (TRUSS_WIDTH * 0.5) - upW * (length * 0.5)
side = min(max(LADDER_RAIL_X * S - TRUSS_WIDTH * 0.5, 0), TRUSS_WIDTH * 0.5)

trusses = []
for dx in (-1, 1):
    c = centre + rightW * (dx * side)
    corners = []
    for a in (-1, 1):
        for b in (-1, 1):
            for d in (-1, 1):
                corners.append(c + rightW * a * TRUSS_WIDTH / 2 + upW * b * length / 2 + backW * d * TRUSS_WIDTH / 2)
    trusses.append((c, np.array(corners)))

print(f"scale {S}: truss length {length}, side offset {side:.3f}, rightW {rightW.round(3)}")
for i, (c, k) in enumerate(trusses, 1):
    print(f"  truss{i}: centre {c.round(3)}  X {k[:,0].min():+.3f}..{k[:,0].max():+.3f}  "
          f"Y {k[:,1].min():+.3f}..{k[:,1].max():+.3f}  Z {k[:,2].min():+.3f}..{k[:,2].max():+.3f}")
# the climbing face's top edge (the +back face, +up end)
faceTopEdge = centre + backW * TRUSS_WIDTH / 2 + upW * length / 2
print(f"  climbing-face top edge Y {faceTopEdge[1]:.3f} vs deck {DECK_Y*S:.3f} (drop {DECK_Y*S-faceTopEdge[1]:.3f})")
foot = centre - upW * length / 2
print(f"  lowest corner Y {min(k[:,1].min() for _, k in trusses):.3f} (buried below the ground at 0)")
rail_in = (LADDER_RAIL_X - 0.14) * S
print(f"  rails: centre +/-{LADDER_RAIL_X*S:.3f}, inner surface +/-{rail_in:.3f}; trusses span "
      f"{min(k[:,0].min() for _, k in trusses):+.3f}..{max(k[:,0].max() for _, k in trusses):+.3f}")
# face offset from the rung axis, measured square to the ladder
axis_pt = LADDER_FOOT * S
d = np.dot(faceTopEdge - axis_pt, backW)
print(f"  climbing face {d:.3f} studs proud of the rung axis (rung radius {0.11*S:.3f}, rail radius {0.14*S:.3f})")

# ---- geometry from build_slide.py (Blender -> Roblox: x, z, -y), scaled
def b2r(x, y, z): return np.array([x, z, -y]) * S
RUNG_Z = (0.80, 1.66, 2.52, 3.38, 4.24)
LAD_FOOT, LAD_TOP = (-5.04, 0.12), (-4.32, 4.70)
def rung_y(z):
    fy, fz = LAD_FOOT; ty, tz = LAD_TOP
    return fy + (ty - fy) * (z - fz) / (tz - fz)
hoop = [(1.40, -4.34, 4.12)]
for k in range(7):
    a = math.radians(8.0 + (172.0 - 8.0) * k / 6.0)
    hoop.append((math.cos(a) * 1.24, -4.34 + 0.16 * math.sin(a), 4.60 + math.sin(a) * 1.24))
hoop.append((-1.40, -4.34, 4.12))
hoopR = np.array([b2r(*p) for p in hoop])
ts = np.linspace(0, 1, 60)
curve = np.array([[0, (0.40 + 4.0 * (1 - t) ** 2) * S, (2.45 - 7.85 * t) * S] for t in ts])

fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(15, 7.5))
# side view: Z (horizontal, front -Z on the left) vs Y
ax1.set_title(f"Side view (x{S}): chute, deck, ladder, hoop + 2 trusses (overlap in side view)")
ax1.plot(curve[:, 2], curve[:, 1], color="#f2c13d", lw=3, label="chute riding surface")
ax1.plot([DECK_Z0 * S, DECK_Z1 * S], [DECK_Y * S] * 2, color="#d9443c", lw=4, label="deck surface")
ax1.plot([LADDER_FOOT[2] * S, LADDER_TOP[2] * S], [LADDER_FOOT[1] * S, LADDER_TOP[1] * S], color="#9aa7b8", lw=3, label="ladder rail axis")
for rz in RUNG_Z:
    p = b2r(0, rung_y(rz), rz)
    ax1.add_patch(Circle((p[2], p[1]), 0.11 * S, color="#d9443c"))
ax1.plot(hoopR[:, 2], hoopR[:, 1], "o-", color="#3f79d4", ms=3, label="grab hoop (all x)")
for i, (c, k) in enumerate(trusses):
    # side outline: project corners onto (Z, Y); the rectangle in the up/back plane
    pts = [c + upW * u * length / 2 + backW * b * TRUSS_WIDTH / 2 for u, b in ((-1, -1), (-1, 1), (1, 1), (1, -1))]
    ax1.add_patch(Polygon([(p[2], p[1]) for p in pts], closed=True, fill=False, ec="green", lw=2 - i, ls="--",
                          label="truss (side)" if i == 0 else None))
ax1.axhline(0, color="k", lw=1)
ax1.set_aspect("equal"); ax1.grid(alpha=0.3); ax1.legend(loc="upper left", fontsize=8)
ax1.set_xlabel("authored Z x scale (front = -Z, left)"); ax1.set_ylabel("Y")

# back view: looking from +Z toward the ladder, X vs Y
ax2.set_title("Back view (from behind the ladder): rails, rungs, hoop, 2 trusses")
for sx in (1, -1):
    x = sx * LADDER_RAIL_X * S
    ax2.add_patch(Polygon([(x - 0.14 * S, LADDER_FOOT[1] * S), (x + 0.14 * S, LADDER_FOOT[1] * S),
                           (x + 0.14 * S, LADDER_TOP[1] * S), (x - 0.14 * S, LADDER_TOP[1] * S)], color="#9aa7b8"))
for rz in RUNG_Z:
    ax2.plot([-LADDER_RAIL_X * S, LADDER_RAIL_X * S], [rz * S] * 2, color="#d9443c", lw=3)
ax2.plot(hoopR[:, 0], hoopR[:, 1], "o-", color="#3f79d4", ms=3)
ax2.plot([-1.70 * S, 1.70 * S], [DECK_Y * S] * 2, color="#d9443c", lw=2, ls=":")
colors = ("tab:green", "tab:purple")
for i, (c, k) in enumerate(trusses):
    ax2.add_patch(Polygon([(k[:, 0].min(), k[:, 1].min()), (k[:, 0].max(), k[:, 1].min()),
                           (k[:, 0].max(), k[:, 1].max()), (k[:, 0].min(), k[:, 1].max())],
                          closed=True, fill=True, alpha=0.25, color=colors[i], label=f"SlideLadderTruss{i+1}"))
ax2.axhline(0, color="k", lw=1)
ax2.set_aspect("equal"); ax2.grid(alpha=0.3); ax2.legend(loc="upper right", fontsize=8)
ax2.set_xlabel("X"); ax2.set_ylabel("Y")
plt.tight_layout()
plt.savefig(OUT, dpi=90)
print("wrote", OUT)

# ---- client numbers per physique stage (stage height scales HipHeight + root Y together from the Champion
# ---- README figure HipHeight 4.17 @ 8.0; root Y 3.0 @ 8.0 is the reviewer's estimate)
print("\nstage      h   hip   rootY  standH  old max  new max  deck-edge h  old SitLift  new SitLift")
for name, h in (("Beginner", 5.5), ("Fit", 5.8), ("Athletic", 6.1), ("Strong", 6.5), ("Muscular", 7.0),
                ("Powerhouse", 7.5), ("Champion", 8.0), ("default R15", None)):
    if h is None:
        hip, ry = 2.0, 2.0
        h = 5.2
    else:
        hip, ry = 4.17 * h / 8, 3.0 * h / 8
    standH = hip + ry / 2
    edge = DECK_Y * S + standH - (0.40 + 4 * 0.98 ** 2) * S  # standing at the deck edge, height over t=0.02
    old_lift = ry * 0.5 + hip * 0.55 + 0.1
    new_lift = ry * 0.85 + 0.1
    print(f"{name:11s}{h:4.1f} {hip:5.2f} {ry:5.2f}  {standH:5.2f}   {4.6:5.2f}   {standH+1.6:5.2f}    "
          f"{edge:5.2f} {'ok' if edge <= standH + 1.6 else 'NO'}/{'ok' if edge <= 4.6 else 'NO'}   "
          f"{old_lift:5.2f}       {new_lift:5.2f}")

# prompt gate: feet vs root (server)
print("\nprompt gate: standing on the ground (feet 0) vs on the top rungs, authored feet threshold", DECK_Y - 1.5)
for name, h in (("Beginner", 5.5), ("Champion", 8.0)):
    hip, ry = 4.17 * h / 8, 3.0 * h / 8
    standH = hip + ry / 2
    root_ground = standH / S
    print(f"  {name}: root on the ground = {root_ground:.2f} authored (old gate >= {DECK_Y-1.7:.2f}: "
          f"{'PASSES (bug)' if root_ground >= DECK_Y - 1.7 else 'blocked'}); feet 0 -> new gate blocked; "
          f"feet on rung 3.38 -> {'passes' if 3.38 >= DECK_Y - 1.5 else 'blocked'}")
