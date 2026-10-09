"""Pipeline smoke test (not shipped): every primitive once."""


def build(D, P):
    m = P.Model(D, "_Smoke", category="Test")
    m.block("Seat", (0, 2, 0), (3, 0.5, 3), "a0522d", "Wood")
    m.block("Back", (0, 4, 1.3), (3, 3.5, 0.4), "a0522d", "Wood")
    for i, (x, z) in enumerate([(1.3, -1.3), (-1.3, -1.3), (1.3, 1.3), (-1.3, 1.3)]):
        m.cyl("Leg%d" % i, (x, 0, z), (x, 1.75, z), 0.4, "5a3a22", "Wood")
    m.wedge("Ramp", (3.5, 0.5, 0), (1, 1, 2), "44aa55")
    m.corner("Corner", (-3.5, 0.5, 0), (1, 1, 1), "4455aa")
    m.ball("Knob", (0, 6.1, 1.3), 0.6, "ffcc00", "Metal")
    m.ellipsoid("Cushion", (0, 2.45, 0), (2.6, 0.5, 2.6), "d04040", "Fabric")
    m.pivot("SeatTop", (0, 2.7, 0))
    m.attr("Cost", 1)
    return m.finish()
