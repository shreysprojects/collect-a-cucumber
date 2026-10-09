"""Pipeline smoke test: every helper once. The word must read 'SHOP' left-to-right in the FRONT render."""


def build(L):
    P = L.PALETTE
    m = L.Model("_Smoke", kept=["Sign"])
    m.box("Base", (-4, -2, 0), (4, 2, 1.5), P["wood"], "Wood", bevel=0.2, mesh="Base")
    m.cyl("PostL", (3.5, 1.5, 1.5), (3.5, 1.5, 6), 0.3, P["wood_light"], "Wood", mesh="Posts")
    m.cyl("PostR", (-3.5, 1.5, 1.5), (-3.5, 1.5, 6), 0.3, P["wood_light"], "Wood", mesh="Posts")
    m.box("Board", (-4, 1.2, 6), (4, 1.6, 8), P["slate"], bevel=0.1, mesh="Sign")
    m.text("Word", "SHOP", size=1.6, depth=0.3, loc=(0, 1.75, 7.0), hex=P["gold"], mesh="Sign")
    m.sphere("Ball", (-2, 0, 2.3), 0.8, P["snow"], mesh="Balls")
    m.lathe("Coin", [(0, 0), (0.9, 0), (0.9, 0.25), (0, 0.25)], P["gold"], matrix=L.xf((2, 0, 1.5)), mesh="Coins")
    m.torus("Halo", (0, 0, 9.5), 1.2, 0.18, P["gold_neon"], "Neon", collide=False, mesh="Halo")
    m.prism("Star", L.star_pts(5, 1.0, 0.45), -0.15, 0.15, P["gold_neon"], "Neon", matrix=L.xf((0, 1.8, 3.8), rx=90),
            bevel=0.04, collide=False, mesh="Halo")
    return m.finish()
