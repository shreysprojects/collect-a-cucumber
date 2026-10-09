"""Review render of the Scarecrow behaviour's runtime crow (GardenLife, not shipped - the crow is built in Luau).

Mirrors the CROW table + WingCF / Pose maths of src/behaviours/client/Scarecrow.lua exactly (same authored numbers,
same CFrame composition) at PREVIEW scale S so the render shows detail. Four poses along X, all perched on a red
sleeve bar except the flyer:  perched (profile)  |  wings up mid-flap  |  flying (downstroke, nose up)  |  perched
facing the camera, head turned (shows the eye glints).
"""
from mathutils import Matrix, Vector

S = 4.0  # preview scale (in game: the Scarecrow's x1.35)
BLACK, SHEEN, BEAK, EYE, SLEEVE = "23262c", "2c313d", "f2c13d", "f2f0ea", "c0392b"
NECK = Vector((0.0, 0.12, -0.2))
# name, kind, size, pos, angles (deg, CFrame.Angles order), colour, head?
CROW = [
    ("Body", "ellipsoid", (0.4, 0.38, 0.62), (0, 0, 0.02), (16, 0, 0), BLACK, False),
    ("Head", "ellipsoid", (0.3, 0.3, 0.3), (0, 0.2, -0.28), (0, 0, 0), BLACK, True),
    ("Beak", "wedge", (0.09, 0.08, 0.2), (0, 0.18, -0.5), (-6, 0, 0), BEAK, True),
    ("EyeL", "ellipsoid", (0.065, 0.065, 0.065), (-0.105, 0.245, -0.38), (0, 0, 0), EYE, True),
    ("EyeR", "ellipsoid", (0.065, 0.065, 0.065), (0.105, 0.245, -0.38), (0, 0, 0), EYE, True),
    ("Tail", "ellipsoid", (0.18, 0.05, 0.34), (0, -0.05, 0.4), (12, 0, 0), SHEEN, False),
]
WING = (0.06, 0.24, 0.5)
SPREAD = Matrix(((0, 0, 1), (1, 0, 0), (0, 1, 0)))  # CFrame.fromMatrix(0, yAxis, zAxis, xAxis)


def build(D, P):
    m = P.Model(D, "_CrowPreview", category="Test")

    def cf(pos=(0, 0, 0), ang=(0, 0, 0)):
        return (Vector(pos), P.angles(*ang))

    def mul(a, b):
        return (a[0] + a[1] @ b[0], a[1] @ b[1])

    def put(tag, name, kind, size, frame, color):
        pos, rot = tuple(frame[0]), frame[1]
        size = tuple(s * S for s in size)
        getattr(m, kind)(tag + name, pos, size, color, "SmoothPlastic", rot=rot)

    def crow(tag, root, alpha, flap, head_pitch=0.0, head_yaw=0.0):
        neck_in, neck_out = cf(tuple(NECK * S)), cf(tuple(-NECK * S))
        head = mul(mul(mul(mul(root, neck_in), cf(ang=(0, head_yaw, 0))), cf(ang=(head_pitch, 0, 0))), neck_out)
        for name, kind, size, pos, ang, color, is_head in CROW:
            local = cf(tuple(Vector(pos) * S), ang)
            put(tag, name, kind, size, mul(head if is_head else root, local), color)
        for side, wname in ((-1, "WingL"), (1, "WingR")):
            if alpha < 0.5:
                local = cf((side * 0.17 * S, 0.04 * S, 0.1 * S), (14, 0, side * 12))
            else:
                local = mul(mul(cf((side * 0.15 * S, 0.1 * S, -0.02 * S), (0, 0, side * flap)),
                                cf((side * 0.25 * S, 0, 0))), (Vector((0, 0, 0)), SPREAD))
            put(tag, wname, "ellipsoid", WING, mul(root, local), SHEEN)

    bar_y = 1.0
    perch_y = bar_y + 0.3 + 0.19 * S  # sleeve top + the body's half height
    m.cylx("Sleeve", (0, bar_y, 0), 17.0, 0.6, SLEEVE, "Fabric")
    # 1 perched, profile: faces -X (viewer's right) like the authored crow on the arm
    crow("P_", (Vector((5.4, perch_y, 0)), P.angles(0, 90, 0)), 0.0, 0.0)
    # 2 perched, mid-flap wings up
    crow("F_", (Vector((1.8, perch_y + 0.05 * S, 0)), P.angles(0, 90, 0)), 1.0, 42.0)
    # 3 flying: nose up 15 deg, downstroke
    crow("Y_", (Vector((-1.8, perch_y + 1.6, 0)), P.angles(0, 90, 0) @ P.angles(15, 0, 0)), 1.0, -28.0)
    # 4 perched facing the camera (-Z), head turned and lifted (a caw)
    crow("C_", (Vector((-5.4, perch_y, 0)), P.angles(0, 0, 0)), 0.0, 0.0, head_pitch=18.0, head_yaw=30.0)
    m.attr("Cost", 0)
    return m.finish()
