"""kitchenlib.py -- shared helper for the HomeKitchenA builds (Fridge, Microwave), fun-builds 2026-09-24.

Swing(m, P, pivot, deg) forwards primlib calls (block / ellipsoid / cyl / disc / ball) with every point turned
`deg` degrees about the vertical axis through `pivot` - the same CFrame.Angles(0, deg, 0) turn the behaviours
apply to a door group or a turntable. At deg = 0 it is a plain pass-through, so the shipped model is authored
through it too and the review renders (build__FridgeOpen.py, build__MicrowaveOpen.py) show exactly what the
behaviour will show.

    K = _kitchenlib()                # each build_<Key>.py loads this file by path (builds are not on sys.path)
    g = K.Swing(m, P, (x, y, z), open_deg)
    g.block("DoorPanel", ...)
"""
import math
from mathutils import Vector, Matrix


class Swing:
    def __init__(self, m, P, pivot, deg):
        self.m = m
        self.P = P
        self.p = Vector(pivot)
        self.R = Matrix.Rotation(math.radians(deg), 3, 'Y')

    def _pt(self, pos):
        return tuple(self.p + self.R @ (Vector(pos) - self.p))

    def _rot(self, kw):
        rot = kw.pop("rot", None)
        base = self.P.angles(*rot) if rot is not None else Matrix.Identity(3)
        kw["rot"] = self.R @ base
        return kw

    def block(self, name, pos, size, color, material="SmoothPlastic", **kw):
        return self.m.block(name, self._pt(pos), size, color, material, **self._rot(kw))

    def ellipsoid(self, name, pos, size, color, material="SmoothPlastic", **kw):
        return self.m.ellipsoid(name, self._pt(pos), size, color, material, **self._rot(kw))

    def ball(self, name, pos, diameter, color, material="SmoothPlastic", **kw):
        return self.m.ball(name, self._pt(pos), diameter, color, material, **kw)

    def cyl(self, name, a, b, diameter, color, material="SmoothPlastic", **kw):
        return self.m.cyl(name, self._pt(a), self._pt(b), diameter, color, material, **kw)

    def disc(self, name, pos, axis, diameter, thickness, color, material="SmoothPlastic", **kw):
        return self.m.disc(name, self._pt(pos), tuple(self.R @ Vector(axis)), diameter, thickness, color,
                           material, **kw)
