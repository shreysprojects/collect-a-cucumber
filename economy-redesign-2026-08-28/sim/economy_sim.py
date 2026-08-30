"""
Collect a Cucumber — economy redesign simulator (2026-08-28), v2
================================================================
Feedback-calibrated: door prices are iteratively scaled until the AVERAGE
profile's simulated unlock times land on the targets; pickaxe/egg/rebirth
prices are re-derived from the resulting income curve each iteration.

Model mirrors the audited live formulas (see audit/*.json):
  income/kill = typeValue * matMutEV * (1 + sumPetMulti1) * 2^R [* pass/boost/group]
  coins == cukes (sell 1:1; redesign REMOVES the rebirth coin-side dip)
  clickDPS = pickDamage * CPS * critEV(1.4) * comboEV ; petDPS = (2+sumDmg)/0.6*1.4
  kills/min = 60/(avgHP/DPS + travel), capped ~26 by spawn supply
"""
import math

ZONES = ["Spawn", "Desert", "Samurai", "Farm", "Snow", "Underwater", "Volcano", "Narmek"]
NZ = 8

ZONE_V  = [1, 8, 64, 512, 4_100, 33_000, 262_000, 2_100_000]
ZONE_HP = [1, 13, 165, 2_050, 24_500, 285_000, 3_250_000, 36_500_000]
TYPE_LADDER = [
    ("Common",    1.0,  1.0, 0.58),
    ("Uncommon",  2.5,  1.9, 0.25),
    ("Rare",      7.0,  3.5, 0.10),
    ("Epic",     18.0,  6.0, 0.055),
    ("Tree",     45.0, 10.0, 0.015),
]
BASE_COMMON_VALUE, BASE_COMMON_HP = 8, 30

GOLDEN   = {"chance": 0.04,   "val": 12,  "hp": 3}
DIAMOND  = {"chance": 0.006,  "val": 50,  "hp": 5}
MUT_DAILY= {"chance": 0.0305, "val": 18.5}  # always-on weighted mix (was daily-rotation 2.5% x avg25)
MUT_VOID = {"chance": 1/1200, "val": 150}
MUT_PRIS = {"chance": 1/20000,"val": 750}

def value_ev():
    return (1.0 + GOLDEN["chance"]*(GOLDEN["val"]-1) + DIAMOND["chance"]*(DIAMOND["val"]-1)
            + MUT_DAILY["chance"]*(MUT_DAILY["val"]-1) + MUT_VOID["chance"]*(MUT_VOID["val"]-1)
            + MUT_PRIS["chance"]*(MUT_PRIS["val"]-1))
def hp_ev():
    return 1.0 + GOLDEN["chance"]*(GOLDEN["hp"]-1) + DIAMOND["chance"]*(DIAMOND["hp"]-1)

TYPE_VAL_EV = sum(v*w for _, v, _, w in TYPE_LADDER)
TYPE_HP_EV  = sum(h*w for _, _, h, w in TYPE_LADDER)
def zone_avg_value(zi): return BASE_COMMON_VALUE * ZONE_V[zi] * TYPE_VAL_EV * value_ev()
def zone_avg_hp(zi):    return BASE_COMMON_HP * ZONE_HP[zi] * TYPE_HP_EV * hp_ev()

PICK_DAMAGE = [round(5 * 2.75**i) for i in range(19)]
PICK_PRICE  = [400 * 3.45**i for i in range(19)]

EGG_EV_M1 = [1.55 * 3**i for i in range(NZ)]
EGG_EV_DMG= [3.0 * 11.5**i for i in range(NZ)]
EGG_PRICE = [500.0] * NZ
EGGS_PER_AREA_TARGET = 10
EQUIP_SLOTS_BASE, EQUIP_SLOTS_MAX = 4, 7
SLOT_UPGRADE_PRICES = [25_000, 100_000, 400_000]

def qf(n):
    return 1.0 if n <= 0 else min(1.05 + 0.32 * math.log10(max(n, 1) + 1), 1.6)

DOOR_PRICE = [0, 60_000, 6e6, 4e8, 4e10, 3e12, 2.5e14, 1.5e16]  # seed, feedback-tuned
DOOR_GATES = [0, 0, 0, 1, 2, 3, 4, 5]
REBIRTH_COST = [0.0] * 51
def REBIRTH_MULT(R): return 2.0 ** R
POST_TAIL_RATIO = 2.9         # R>=5: cost x2.9 vs income x2 -> loop grows x1.45
VALUE_REBIRTH_MIN_INCOME_MIN = 45   # rebirth when cost <= 45 min of income
REBIRTH_FRICTION_MIN = 10           # min minutes between value rebirths

TARGET_CUM_MIN = [0, 7, 27, 72, 180, 360, 620, 1000]

PROFILES = {
    "casual":    dict(cps=2.0, combo=1.10, active=0.70, luck=0.90, extra=1.04, mult=1.0),
    "average":   dict(cps=3.0, combo=1.25, active=0.85, luck=1.00, extra=1.08, mult=1.0),
    "lucky":     dict(cps=3.0, combo=1.25, active=0.85, luck=1.35, extra=1.12, mult=1.0),
    "optimized": dict(cps=4.0, combo=1.60, active=0.97, luck=1.45, extra=1.15, mult=6.0),
}
CRIT_EV = 1.4
TRAVEL_S = {"casual": 2.6, "average": 2.0, "lucky": 2.0, "optimized": 1.3}
KILLS_MIN_CAP = 26.0

def pretty(x):
    if x <= 0: return 0
    steps = [1, 1.5, 2, 2.5, 3, 4, 5, 6, 7.5, 8, 9, 10]
    e = math.floor(math.log10(x)); m = x / 10**e
    return min(steps, key=lambda s0: abs(s0 - m)) * 10**e

def fmt(x):
    if x is None: return "-"
    x = float(x)
    for s, e in [("Sx",21),("Qi", 18), ("Qa", 15), ("T", 12), ("B", 9), ("M", 6), ("K", 3)]:
        if abs(x) >= 10**e: return f"{x/10**e:.2f}{s}"
    return f"{x:.0f}"

class State:
    def __init__(self, prof):
        self.p = PROFILES[prof]; self.prof = prof
        self.t = 0.0; self.coins = 0.0; self.earned = 0.0
        self.R = 0; self.unlocked = 1; self.best_area_ever = 1
        self.own_pick = 0            # 0 = Wood only; N = owns pickaxes 1..N of the 19-ladder
        self.eggs_bought = [0]*NZ
        self.slots = EQUIP_SLOTS_BASE; self.slot_upg = 0
        self.first_unlock_time = {1: 0.0}
        self.last_rebirth_t = -999.0
        self.income_at_unlock = {}
        self.log = []

    def pick_damage(self):
        return PICK_DAMAGE[self.own_pick - 1] if self.own_pick > 0 else 3  # Wood = 3

    def team(self):
        best_m1 = 0.0; best_dmg = 0.0
        for i in range(NZ):
            n = self.eggs_bought[i]
            if n <= 0: continue
            q = qf(n) * self.p["luck"]
            best_m1  = max(best_m1,  self.slots * q * EGG_EV_M1[i])
            best_dmg = max(best_dmg, self.slots * q * EGG_EV_DMG[i])
        return best_m1, best_dmg

    def income_per_min(self, zi):
        m1, pdmg = self.team()
        click = self.pick_damage() * self.p["cps"] * CRIT_EV * self.p["combo"]
        pet   = (2 + pdmg) / 0.6 * CRIT_EV
        dps   = click * self.p["active"] + pet
        kill_s = zone_avg_hp(zi) / dps
        kpm = min(60.0 / (kill_s + TRAVEL_S[self.prof]), KILLS_MIN_CAP)
        inc = kpm * zone_avg_value(zi) * (1 + m1) * REBIRTH_MULT(self.R) * self.p["mult"] * self.p["extra"]
        return inc, kpm

def try_buy(s: State):
    # next NEW door (may need rebirth first)
    if s.unlocked < NZ and s.unlocked == s.best_area_ever:
        nd = s.unlocked
        need_R = DOOR_GATES[nd]
        if s.R < need_R:
            if s.coins >= REBIRTH_COST[s.R]:
                s.log.append((s.t, f"REBIRTH -> R{s.R+1} (cost {fmt(REBIRTH_COST[s.R])})"))
                s.R += 1; s.coins = 0.0; s.unlocked = 1
                s.last_rebirth_t = s.t
                return True
        elif s.coins >= DOOR_PRICE[nd]:
            s.coins -= DOOR_PRICE[nd]; s.unlocked += 1
            s.best_area_ever = s.unlocked
            s.first_unlock_time[s.unlocked] = s.t
            s.income_at_unlock[s.unlocked] = s.income_per_min(s.unlocked-1)[0]
            s.log.append((s.t, f"DOOR {ZONES[nd]} ({fmt(DOOR_PRICE[nd])})"))
            return True
    # rebuild doors after a rebirth (backfill pricing = full door price of highest jump)
    if s.unlocked < s.best_area_ever:
        nd = s.unlocked
        if s.R >= DOOR_GATES[nd] and s.coins >= DOOR_PRICE[nd]:
            s.coins -= DOOR_PRICE[nd]; s.unlocked += 1
            return True
    # next pickaxe
    if s.own_pick < 19 and s.coins >= PICK_PRICE[s.own_pick]:
        s.coins -= PICK_PRICE[s.own_pick]; s.own_pick += 1
        s.log.append((s.t, f"PICK {s.own_pick} ({fmt(PICK_PRICE[s.own_pick-1])}) dmg {fmt(PICK_DAMAGE[s.own_pick-1])}"))
        return True
    # equip-slot board upgrades
    if s.slot_upg < 3 and s.best_area_ever >= 2 and s.coins >= SLOT_UPGRADE_PRICES[s.slot_upg]:
        s.coins -= SLOT_UPGRADE_PRICES[s.slot_upg]; s.slot_upg += 1
        s.slots = min(s.slots + 1, EQUIP_SLOTS_MAX)
        return True
    # eggs of best unlocked area
    zi = s.unlocked - 1
    cap = EGGS_PER_AREA_TARGET * (1.5 if s.prof == "optimized" else 1.0)
    if s.eggs_bought[zi] < cap and s.coins * 0.35 >= EGG_PRICE[zi]:
        n = min(int(s.coins * 0.35 // EGG_PRICE[zi]), 3)
        if n > 0:
            s.coins -= n * EGG_PRICE[zi]; s.eggs_bought[zi] += n
            return True
    # post-gate value rebirths
    if s.best_area_ever >= NZ and s.R < 50 and (s.t - s.last_rebirth_t) >= REBIRTH_FRICTION_MIN:
        inc, _ = s.income_per_min(s.unlocked - 1)
        if s.coins >= REBIRTH_COST[s.R] and REBIRTH_COST[s.R] <= inc * VALUE_REBIRTH_MIN_INCOME_MIN:
            s.log.append((s.t, f"REBIRTH(value) -> R{s.R+1}"))
            s.R += 1; s.coins = 0.0; s.unlocked = 1
            s.last_rebirth_t = s.t
            return True
    return False

def run(prof, minutes=1300, checkpoints=(1,5,10,30,60,180,360,600,900,1200)):
    s = State(prof); marks = {}
    dt = 0.5
    while s.t < minutes:
        for _ in range(16):
            if not try_buy(s): break
        zi = s.unlocked - 1
        inc, _ = s.income_per_min(zi)
        s.coins += inc * dt; s.earned += inc * dt; s.t += dt
        for c in checkpoints:
            if c not in marks and s.t >= c:
                marks[c] = (s.earned, s.best_area_ever, s.R)
    return s, marks

def derive_secondary_prices():
    """pickaxe/egg/rebirth prices from the average player's income curve under current doors"""
    global PICK_PRICE, EGG_PRICE, REBIRTH_COST
    s, _ = run("average", minutes=TARGET_CUM_MIN[-1] + 200)
    # income at each area unlock (fallback: extrapolate)
    inc_at = {}
    for a in range(2, NZ + 1):
        inc_at[a] = s.income_at_unlock.get(a)
    inc_at[1] = 60.0  # fresh spawn income/min approx
    for a in range(2, NZ + 1):
        if inc_at[a] is None:
            inc_at[a] = inc_at[a - 1] * 20
    # egg prices: ~1.8 min of entry income (min 250 for the first egg)
    ep = []
    for a in range(1, NZ + 1):
        ep.append(pretty(max(inc_at[a] * 1.8, 250 if a == 1 else 0)))
    EGG_PRICE = ep
    # pickaxes: 2.4/area cadence; price = ~4.5 min of income at scheduled buy moment
    newp = []
    for j in range(19):
        area_f = min(j / 2.4, NZ - 1.001)          # fractional area position
        a0 = int(area_f) + 1
        frac = area_f - (a0 - 1)
        inc0 = inc_at[a0]
        inc1 = inc_at[min(a0 + 1, NZ)]
        inc = inc0 * (inc1 / inc0) ** frac if inc0 > 0 else 400
        newp.append(max(pretty(inc * 4.5), 400))
    for i in range(1, 19):
        newp[i] = pretty(max(newp[i], newp[i-1] * 2.6))
    newp[0] = 400
    PICK_PRICE = newp
    # rebirths: R0..R4 = 30% of the door each gates; R5+ geometric tail
    RC = [0.0] * 51
    for R in range(0, 5):
        try:
            gate_door_idx = DOOR_GATES.index(R + 1)
            RC[R] = pretty(DOOR_PRICE[gate_door_idx] * 0.30)
        except ValueError:
            RC[R] = pretty(RC[R-1] * 3)
    for R in range(5, 50):
        RC[R] = pretty(RC[R-1] * POST_TAIL_RATIO)
    REBIRTH_COST = RC

def calibrate(feedback_iters=10):
    global DOOR_PRICE
    derive_secondary_prices()
    for it in range(feedback_iters):
        s, _ = run("average", minutes=2200)
        adjusted = False
        for a in range(2, NZ + 1):
            actual = s.first_unlock_time.get(a)
            target = TARGET_CUM_MIN[a - 1]
            if actual is None:
                DOOR_PRICE[a - 1] = pretty(DOOR_PRICE[a - 1] / 3.0); adjusted = True; continue
            ratio = actual / target if target > 0 else 1.0
            if abs(math.log(ratio)) > math.log(1.12):
                # too fast (ratio<1) -> raise price ; too slow -> lower. Damped.
                corr = (1.0 / ratio) ** 0.8
                DOOR_PRICE[a - 1] = pretty(DOOR_PRICE[a - 1] * corr)
                adjusted = True
        derive_secondary_prices()
        if not adjusted:
            break

if __name__ == "__main__":
    calibrate()
    print("=== CALIBRATED TABLES ===")
    print("DOORS:   ", [fmt(x) for x in DOOR_PRICE])
    print("REBIRTH: ", [fmt(REBIRTH_COST[r]) for r in range(0, 16)])
    print("PICK $:  ", [fmt(x) for x in PICK_PRICE])
    print("PICK dmg:", [fmt(x) for x in PICK_DAMAGE])
    print("EGG $:   ", [fmt(x) for x in EGG_PRICE])
    print("zoneAvgValue:", [fmt(zone_avg_value(i)) for i in range(NZ)])
    print("zoneAvgHP:   ", [fmt(zone_avg_hp(i)) for i in range(NZ)])
    print("valueEV mult:", round(value_ev(), 3), " typeEV:", round(TYPE_VAL_EV, 3))
    print()
    for prof in PROFILES:
        s, marks = run(prof)
        print(f"=== {prof.upper()} ===")
        unlocks = ", ".join(f"A{a}@{t/60:.1f}h" if t >= 60 else f"A{a}@{t:.0f}m"
                            for a, t in sorted(s.first_unlock_time.items()) if a > 1)
        print("  unlocks:", unlocks)
        print("  final: R", s.R, " earned", fmt(s.earned))
        for c, (earned, area, R) in sorted(marks.items()):
            lab = f"{c}m" if c < 60 else f"{c//60}h"
            print(f"   @{lab:>4}: earned {fmt(earned):>10}  area {area}  R{R}")
        print()
