"""Look-check only (NOT shipped, not installed): the three hand-held snacks the VendingMachine server half
welds to a buyer's RightHand (src/behaviours/server/VendingMachine.lua SNACKS), shown at 2x so the renders
read and primlib's 0.05-stud minimum holds. Keep the rows in step with the Lua table if either changes.

    & "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" -b --factory-startup --python run_one.py -- _VendSnacks
"""
S = 2.0  # preview scale

WHITE, TIN, RED = "f2f0ea", "c4cbd4", "d9443c"
SNACKS = [  # (kind, x, rows) - rows: (name, shape, size, pos, rot degrees (CFrame.Angles order), color, material)
    ("Soda", -1.25, [
        ("Can", "Cylinder", (0.80, 0.44, 0.44), (0, 0, 0), (0, 0, 90), "56c440", "SmoothPlastic"),
        ("Band", "Cylinder", (0.30, 0.452, 0.452), (0, 0.02, 0), (0, 0, 90), WHITE, "SmoothPlastic"),
        ("Lid", "Cylinder", (0.04, 0.37, 0.37), (0, 0.41, 0), (0, 0, 90), TIN, "Metal"),
        ("Rim", "Cylinder", (0.04, 0.37, 0.37), (0, -0.41, 0), (0, 0, 90), TIN, "Metal"),
        ("Tab", "Block", (0.08, 0.03, 0.13), (0, 0.435, -0.05), (0, 0, 0), TIN, "Metal"),
        ("Logo", "Ellipsoid", (0.10, 0.24, 0.06), (0, 0.02, -0.228), (0, 0, -25), "2f6b2c", "SmoothPlastic"),
    ]),
    ("Cola", 0.0, [
        ("Can", "Cylinder", (0.80, 0.44, 0.44), (0, 0, 0), (0, 0, 90), "c82028", "SmoothPlastic"),
        ("Band", "Cylinder", (0.30, 0.452, 0.452), (0, 0.02, 0), (0, 0, 90), WHITE, "SmoothPlastic"),
        ("Stripe", "Cylinder", (0.07, 0.458, 0.458), (0, 0.02, 0), (0, 0, 90), "c82028", "SmoothPlastic"),
        ("Lid", "Cylinder", (0.04, 0.37, 0.37), (0, 0.41, 0), (0, 0, 90), TIN, "Metal"),
        ("Rim", "Cylinder", (0.04, 0.37, 0.37), (0, -0.41, 0), (0, 0, 90), TIN, "Metal"),
        ("Tab", "Block", (0.08, 0.03, 0.13), (0, 0.435, -0.05), (0, 0, 0), TIN, "Metal"),
    ]),
    ("Chips", 1.3, [
        ("Bag", "Block", (0.56, 0.70, 0.12), (0, 0, 0), (0, 0, 0), "f2c13d", "SmoothPlastic"),
        ("Puff", "Ellipsoid", (0.55, 0.66, 0.32), (0, 0, 0), (0, 0, 0), "f2c13d", "SmoothPlastic"),
        ("CrimpTop", "Block", (0.58, 0.07, 0.09), (0, 0.385, 0), (0, 0, 0), RED, "SmoothPlastic"),
        ("CrimpBottom", "Block", (0.58, 0.07, 0.09), (0, -0.385, 0), (0, 0, 0), RED, "SmoothPlastic"),
        ("Banner", "Ellipsoid", (0.40, 0.22, 0.06), (0, 0.08, -0.15), (0, 0, 0), WHITE, "SmoothPlastic"),
        ("BannerInk", "Ellipsoid", (0.30, 0.11, 0.06), (0, 0.08, -0.162), (0, 0, 0), RED, "SmoothPlastic"),
        ("ChipA", "Ellipsoid", (0.14, 0.10, 0.04), (-0.07, -0.19, -0.135), (0, 0, 20), "ffe27a", "SmoothPlastic"),
        ("ChipB", "Ellipsoid", (0.12, 0.09, 0.04), (0.09, -0.21, -0.13), (0, 0, -25), "e9c45a", "SmoothPlastic"),
    ]),
]


def build(D, P):
    m = P.Model(D, "_VendSnacks", category="Test")
    for kind, x, rows in SNACKS:
        base = (x * S, 0.8 * S + 0.05, 0.0)
        for name, shape, size, pos, rot, color, material in rows:
            p = (base[0] + pos[0] * S, base[1] + pos[1] * S, base[2] + pos[2] * S)
            sz = tuple(s * S for s in size)
            nm = kind + name
            if shape == "Cylinder":
                m.cylx(nm, p, sz[0], sz[1], color, material, rot=rot)
            elif shape == "Ellipsoid":
                m.ellipsoid(nm, p, sz, color, material, rot=rot)
            else:
                m.block(nm, p, sz, color, material, rot=rot)
    m.block("Floor", (0, 0.025, 0), (7.5, 0.05, 3), "5c6672", "SmoothPlastic")
    m.attr("Cost", 0)
    return m.finish()
