"""laundrylib.py -- the shared front-loader for WashingMachine + Dryer (fun-builds HomeLaundry, 2026-09-24).

One chunky toy front-loader, ~3.4 wide x 4.0 high x 3.3 deep (feet to top), built from Roblox primitives:
a hollow front (an octagonal opening = a square hole with four corner wedges) so the drum really sits INSIDE
the cabinet and is seen through a domed glass porthole; a control console with a detergent drawer (washer) /
lint-trap pull (dryer), a little dark screen (the client draws the countdown on its Front face), a start
button + LED and a timer dial; a toe-kick plinth on rubber feet; service bits round the back; props on top.

Everything a behaviour needs is named by group prefix and recorded as a pivot (authored frame, scale 1):
  Drum*        the rigid drum (DrumBack, DrumSlat01..09, DrumBaffle1..3, DrumSpoke1..3) spins about Pivot_Drum's
               axis (authored Z); DrumCloth1..4 are the clothes inside (the client tumbles them separately)
  Door*        the porthole door (DoorRing01..N, DoorGlass, DoorShine, DoorHandle, DoorArm) swings about the
               vertical axis through Pivot_DoorHinge (open = about -105 degrees, toward the front / +X side)
  Dial*        DialKnob, DialCap, DialPointer turn about Pivot_Dial's authored-Z axis (DialRing / DialTick* stay)
  Screen       the countdown display (Front face = -Z)
  Led          the Neon status light; ButtonStart the start button (pressed in along +Z)
  Water        (washer) translucent blue block filling the bottom of the drum; authored INVISIBLE (Transparency 1)
  VentSlat1..3 (dryer) louvres of the side vent, tilt about their own authored-Z axis; Pivot_Vent / Pivot_VentOut
Pivots: Drum, DoorHinge, DoorCentre, Dial, StartPrompt, DoorPrompt (+ WaterTop washer, Vent / VentOut dryer).

`pose` (previews only - never shipped): {"door": degrees about the hinge (negative = open), "drum": degrees,
"water": True (show the water)} renders the machine mid-cycle / door open.
"""
import math
from mathutils import Vector, Matrix

# ---------------------------------------------------------------- palette (the game's prop palette)
WHITE = "f2f0ea"
CONSOLE = "e3e7ec"
CHROME = "c9d1da"
STEEL = "a9b4c0"
STEEL_BACK = "bcc5cf"
SPOKE = "6e7a88"
DARK = "3b4350"
BLACK = "23262c"
SCREEN = "1b2229"
GREEN = "5aa845"
GREEN_DARK = "3f8f3a"
GLASS = "d4eeff"
WATER = "4aa8ff"

# ---------------------------------------------------------------- dimensions (authored frame, studs)
W = 3.4                  # cabinet width (x -1.7 .. 1.7)
BODY_BOTTOM = 0.38       # cabinet bottom (on the plinth)
BODY_TOP = 3.88          # cabinet top (under the lid slab)
TOP_Y = 4.0              # top of the lid slab
HCX, HCY = 0.0, 1.78     # porthole / drum centre
APOTHEM = 0.9            # the octagonal opening's inner radius
FRONT_Z0, FRONT_Z1 = -1.62, -1.50   # front (door) panel: front face, back face
CAVITY_Z = -0.34         # front face of the solid rear body = back of the drum cavity
PANEL_Y0, PANEL_Y1 = 3.10, 3.86     # control console
PANEL_Z = -1.64          # console front face
DRUM_Z0, DRUM_Z1 = -1.49, -0.43     # drum slats: front, back
DRUM_IN = 0.84           # inner radius of the drum wall
DOOR_Z = -1.79           # door ring tube centre (tube diameter 0.3: z -1.94 .. -1.64)
RING_R = 1.04            # door ring major radius
HINGE = (1.36, HCY, -1.72)  # hinge axis (vertical) - on the viewer's LEFT (+X) as in most front loaders
DIAL = (-1.02, 3.49)     # dial centre (x, y)


def _angles(P, rx=0.0, ry=0.0, rz=0.0):
    return P.angles(rx, ry, rz)


class Xf:
    """A rigid group of parts authored in the REST pose and turned by R about `pivot` (preview poses only;
    the shipped model always uses the identity)."""

    def __init__(self, m, P, pivot=(0.0, 0.0, 0.0), R=None):
        self.m, self.P = m, P
        self.pivot = Vector(pivot)
        self.R = R if R is not None else Matrix.Identity(3)

    def pt(self, p):
        return tuple(self.R @ (Vector(p) - self.pivot) + self.pivot)

    def rot(self, rot):
        return self.R @ self.P._rot(rot)

    def block(self, name, pos, size, color, material="SmoothPlastic", rot=None, **kw):
        return self.m.block(name, self.pt(pos), size, color, material, rot=self.rot(rot), **kw)

    def wedge(self, name, pos, size, color, material="SmoothPlastic", rot=None, **kw):
        return self.m.wedge(name, self.pt(pos), size, color, material, rot=self.rot(rot), **kw)

    def ellipsoid(self, name, pos, size, color, material="SmoothPlastic", rot=None, **kw):
        return self.m.ellipsoid(name, self.pt(pos), size, color, material, rot=self.rot(rot), **kw)

    def cyl(self, name, a, b, diameter, color, material="SmoothPlastic", **kw):
        return self.m.cyl(name, self.pt(a), self.pt(b), diameter, color, material, **kw)

    def disc(self, name, pos, axis, diameter, thickness, color, material="SmoothPlastic", **kw):
        return self.m.disc(name, self.pt(pos), tuple(self.R @ Vector(axis)), diameter, thickness, color, material, **kw)


def build_machine(m, P, kind, accent, accent_dark, cloth_colors, pose=None):
    """kind "washer" | "dryer". accent = the machine's colour (console trim, dial, handle, badge)."""
    pose = pose or {}
    washer = kind == "washer"
    fixed = Xf(m, P)

    # ------------------------------------------------------------ feet, plinth, cabinet
    for i, (fx, fz) in enumerate(((1.3, -1.22), (-1.3, -1.22), (1.3, 1.25), (-1.3, 1.25))):
        m.cyl("Foot%d" % (i + 1), (fx, 0.0, fz), (fx, 0.2, fz), 0.36, BLACK, "Rubber")
    m.block("Plinth", (0, 0.285, 0.0), (3.26, 0.23, 3.08), DARK, "SmoothPlastic")
    # the rear body is solid; its front face is the back wall of the drum cavity
    m.block("Body", (0, (BODY_BOTTOM + BODY_TOP) / 2, (CAVITY_Z + 1.6) / 2), (3.38, BODY_TOP - BODY_BOTTOM, 1.6 - CAVITY_Z),
            WHITE, "SmoothPlastic")
    for side, sx in (("L", 1), ("R", -1)):
        m.block("Side" + side, (sx * 1.65, (BODY_BOTTOM + BODY_TOP) / 2, (-1.6 + CAVITY_Z + 0.04) / 2),
                (0.1, BODY_TOP - BODY_BOTTOM, 1.6 + CAVITY_Z + 0.04), WHITE, "SmoothPlastic")
        # soft rounded front corners (a vertical roll down each front edge)
        m.cyl("Edge" + side, (sx * 1.66, BODY_BOTTOM, -1.585), (sx * 1.66, BODY_TOP, -1.585), 0.14, WHITE, "SmoothPlastic")
    m.block("Top", (0, (BODY_TOP - 0.02 + TOP_Y) / 2, -0.02), (3.46, TOP_Y - BODY_TOP + 0.02, 3.3), WHITE, "SmoothPlastic")
    m.cyl("TopEdge", (1.73, TOP_Y - 0.07, -1.67), (-1.73, TOP_Y - 0.07, -1.67), 0.14, WHITE, "SmoothPlastic")

    # ------------------------------------------------------------ front (door) panel with an octagonal opening
    fz = (FRONT_Z0 + FRONT_Z1) / 2
    ft = FRONT_Z1 - FRONT_Z0
    top_of_hole, bottom_of_hole = HCY + APOTHEM, HCY - APOTHEM
    m.block("FrontTop", (0, (top_of_hole + PANEL_Y0) / 2, fz), (3.26, PANEL_Y0 - top_of_hole + 0.02, ft), WHITE)
    m.block("FrontBot", (0, (BODY_BOTTOM + bottom_of_hole) / 2, fz), (3.26, bottom_of_hole - BODY_BOTTOM, ft), WHITE)
    for side, sx in (("L", 1), ("R", -1)):
        m.block("Front" + side, (sx * (APOTHEM + 1.63) / 2, HCY, fz), (1.63 - APOTHEM, 2 * APOTHEM + 0.02, ft), WHITE)
    c = 2 * APOTHEM / (2 + math.sqrt(2))       # corner cut of a regular octagon
    off = APOTHEM - c / 2
    # a wedge turned (0, 90, 0) shows its triangle to the front with the right angle at (+X, -Y); turn it
    # about the world Z axis for the other three corners
    for k, (cx, cy) in enumerate(((1, -1), (1, 1), (-1, 1), (-1, -1))):
        R = _angles(P, 0, 0, 90 * k) @ _angles(P, 0, 90, 0)
        m.wedge("FrontCorner%d" % (k + 1), (HCX + cx * off, HCY + cy * off, fz), (ft, c, c), WHITE, rot=R)

    # ------------------------------------------------------------ console
    m.block("Panel", (0, (PANEL_Y0 + PANEL_Y1) / 2, (PANEL_Z - 1.3) / 2), (3.26, PANEL_Y1 - PANEL_Y0, -1.3 - PANEL_Z),
            CONSOLE, "SmoothPlastic")
    m.block("PanelTrim", (0, PANEL_Y0 - 0.03, -1.585), (3.36, 0.09, 0.17), accent, "SmoothPlastic")
    py = (PANEL_Y0 + PANEL_Y1) / 2
    if washer:
        m.block("Drawer", (1.15, py, PANEL_Z - 0.03), (0.72, 0.56, 0.08), WHITE, "SmoothPlastic")
        m.block("DrawerGrip", (1.15, py - 0.19, PANEL_Z - 0.075), (0.46, 0.08, 0.05), DARK, collide=False)
    else:
        # lint trap pull: a slotted lid with a finger tab
        m.block("LintTrap", (1.15, py, PANEL_Z - 0.025), (0.72, 0.5, 0.06), WHITE, "SmoothPlastic")
        m.block("LintTab", (1.15, py + 0.14, PANEL_Z - 0.07), (0.3, 0.1, 0.05), accent, collide=False)
    m.block("ScreenBezel", (0.2, py, PANEL_Z - 0.02), (0.86, 0.52, 0.06), accent_dark, "SmoothPlastic")
    m.block("Screen", (0.2, py, PANEL_Z - 0.05), (0.72, 0.4, 0.06), SCREEN, "SmoothPlastic")
    m.disc("Led", (-0.42, py + 0.2, PANEL_Z - 0.02), (0, 0, 1), 0.11, 0.06, "2d5a2a", "Neon", collide=False, shadow=False)
    m.disc("ButtonStart", (-0.42, py - 0.1, PANEL_Z - 0.03), (0, 0, 1), 0.22, 0.07, GREEN, "SmoothPlastic", collide=False)
    dx, dy = DIAL
    m.disc("DialRing", (dx, dy, PANEL_Z - 0.015), (0, 0, 1), 0.62, 0.06, CHROME, "Metal", collide=False)
    m.block("DialTick", (dx, dy + 0.37, PANEL_Z - 0.01), (0.06, 0.11, 0.05), DARK, collide=False, shadow=False)
    dial = Xf(m, P, (dx, dy, 0), _angles(P, 0, 0, pose.get("dial", 0)))
    dial.disc("DialKnob", (dx, dy, PANEL_Z - 0.08), (0, 0, 1), 0.46, 0.14, accent, "SmoothPlastic", collide=False)
    dial.disc("DialCap", (dx, dy, PANEL_Z - 0.16), (0, 0, 1), 0.3, 0.06, WHITE, "SmoothPlastic", collide=False)
    dial.block("DialPointer", (dx, dy + 0.075, PANEL_Z - 0.185), (0.06, 0.15, 0.05), BLACK, collide=False, shadow=False)

    # ------------------------------------------------------------ badge (a tiny cucumber on an accent plate)
    m.block("BadgePlate", (-1.02, 0.63, FRONT_Z0 - 0.015), (0.7, 0.24, 0.05), accent, "SmoothPlastic", collide=False)
    m.ellipsoid("BadgeCuke", (-1.02, 0.63, FRONT_Z0 - 0.04), (0.44, 0.13, 0.05), GREEN, rot=(0, 0, 10), collide=False,
                shadow=False)

    # ------------------------------------------------------------ hinge (fixed) + the door
    hx, hy, hz = HINGE
    m.block("HingePlate", (hx + 0.02, hy, FRONT_Z0 - 0.02), (0.22, 0.86, 0.05), CHROME, "Metal", collide=False)
    m.cyl("HingePin", (hx, hy - 0.36, hz), (hx, hy + 0.36, hz), 0.13, CHROME, "Metal", collide=False)
    door = Xf(m, P, HINGE, _angles(P, 0, pose.get("door", 0), 0))
    n = 16
    for k in range(n):
        a0, a1 = 2 * math.pi * k / n, 2 * math.pi * (k + 1) / n
        p0 = Vector((HCX + RING_R * math.cos(a0), HCY + RING_R * math.sin(a0), DOOR_Z))
        p1 = Vector((HCX + RING_R * math.cos(a1), HCY + RING_R * math.sin(a1), DOOR_Z))
        d = (p1 - p0).normalized()
        door.cyl("DoorRing%02d" % (k + 1), tuple(p0 - d * 0.03), tuple(p1 + d * 0.03), 0.3, CHROME, "Metal", collide=False)
    # SmoothPlastic, NOT Glass: Roblox's Glass material hides every transparent part / particle behind it, and
    # the washer's Water (Transparency 0.42) + suds must show through the shut porthole (notes/GlassCase.md)
    door.ellipsoid("DoorGlass", (HCX, HCY, -1.76), (1.92, 1.92, 0.4), GLASS, "SmoothPlastic", transparency=0.55,
                   reflectance=0.15)
    door.ellipsoid("DoorShine", (HCX + 0.42, HCY + 0.42, -1.925), (0.11, 0.46, 0.05), "ffffff", transparency=0.25,
                   rot=(0, 0, 45), collide=False, shadow=False)
    door.block("DoorHandle", (HCX - RING_R - 0.22, HCY, -1.84), (0.18, 0.66, 0.16), accent, collide=False)
    door.block("DoorArm", ((HCX + RING_R + 0.06 + hx) / 2, HCY, hz), (hx - HCX - RING_R + 0.06 + 0.02, 0.44, 0.1), CHROME,
               "Metal", collide=False)

    # ------------------------------------------------------------ the drum (inside the cavity)
    drum = Xf(m, P, (HCX, HCY, 0), _angles(P, 0, 0, pose.get("drum", 0)))
    zc = (DRUM_Z0 + DRUM_Z1) / 2
    drum.disc("DrumBack", (HCX, HCY, DRUM_Z1 + 0.03), (0, 0, 1), 1.86, 0.06, STEEL_BACK, "Metal", collide=False)
    slats = 9  # 40 degrees apart from 90: the three baffles (90 / 210 / 330) sit on slat centres
    for i in range(slats):
        a = 2 * math.pi * i / slats + math.pi / 2
        r = DRUM_IN + 0.04
        drum.block("DrumSlat%02d" % (i + 1), (HCX + r * math.cos(a), HCY + r * math.sin(a), zc),
                   (2 * (DRUM_IN + 0.08) * math.tan(math.pi / slats), 0.08, DRUM_Z1 - DRUM_Z0), STEEL, "DiamondPlate",
                   rot=(0, 0, math.degrees(a) - 90), collide=False)
    for i, deg in enumerate((90, 210, 330)):
        a = math.radians(deg)
        r = DRUM_IN - 0.09
        drum.block("DrumBaffle%d" % (i + 1), (HCX + r * math.cos(a), HCY + r * math.sin(a), zc + 0.02), (0.16, 0.2, 0.98),
                   "e9edf2", rot=(0, 0, deg - 90), collide=False)
    for i, deg in enumerate((30, 150, 270)):
        a = math.radians(deg)
        drum.block("DrumSpoke%d" % (i + 1), (HCX + 0.45 * math.cos(a), HCY + 0.45 * math.sin(a), DRUM_Z1 - 0.015),
                   (0.12, 0.78, 0.05), SPOKE, "Metal", rot=(0, 0, deg - 90), collide=False, shadow=False)
    # clothes resting on the bottom of the drum: (angle from the bottom, radius, z, size, colour)
    for i, (deg, r, z, size, color) in enumerate(cloth_colors):
        a = math.radians(deg)
        drum.ellipsoid("DrumCloth%d" % (i + 1), (HCX + r * math.sin(a), HCY - r * math.cos(a), z), size, color, "Fabric",
                       rot=(0, 0, deg), collide=False)

    if washer:
        level = HCY - 0.16
        bottom = HCY - DRUM_IN - 0.06
        m.block("Water", (HCX, (level + bottom) / 2, (DRUM_Z0 + 0.02 + DRUM_Z1 - 0.01) / 2),
                (1.8, level - bottom, DRUM_Z1 - DRUM_Z0 - 0.01), WATER, "SmoothPlastic",
                transparency=0.45 if pose.get("water") else 1.0, collide=False, shadow=False)
        m.pivot("WaterTop", (HCX, level, zc))

    m.pivot("Drum", (HCX, HCY, zc))
    m.pivot("DoorHinge", HINGE)
    m.pivot("DoorCentre", (HCX, HCY, -1.97))
    m.pivot("Dial", (dx, dy, PANEL_Z - 0.08))
    m.pivot("StartPrompt", (0.2, py, -2.0))
    m.pivot("DoorPrompt", (HCX, HCY, -2.2))
    return fixed


def back_details(m, washer, accent, plate=True):
    """Service plate, cord, and (washer) water taps + drain hose."""
    if plate:
        m.block("BackPlate", (0, 2.2, 1.62), (2.2, 1.9, 0.05), CONSOLE, "SmoothPlastic", collide=False)
    # the cord runs down the back (overlapping the back face at z 1.60 by 0.02) from a strain-relief plug to the floor
    m.cyl("PowerCord", (1.25, 0.0, 1.625), (1.25, 2.9, 1.625), 0.09, BLACK, "Rubber", collide=False)
    m.block("PowerPlug", (1.25, 2.95, 1.63), (0.2, 0.26, 0.1), DARK, "SmoothPlastic", collide=False)
    if washer:
        m.cyl("TapCold", (0.75, 3.35, 1.58), (0.75, 3.35, 1.86), 0.18, "3f79d4", "SmoothPlastic", collide=False)
        m.cyl("TapHot", (0.35, 3.35, 1.58), (0.35, 3.35, 1.86), 0.18, "d9443c", "SmoothPlastic", collide=False)
