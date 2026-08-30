--.. UserIds kept OFF the global leaderboards (the four boards in workspace.Leaderboards).
--..
--.. Each board writes DSS:SetAsync(plr.UserId, value) every refresh while you're in the
--.. server, so simply deleting a leaderboard entry is not enough — it reposts within ~90
--.. seconds of that account playing again. Anyone listed here is skipped on WRITE and also
--.. filtered on READ, so a stale entry can never render even if one is left behind.
--..
--.. Deliberately its own module: Leaderboards (the parent) requires Coins/Orbs/Breaks/Time, so
--.. those children cannot require the parent back without a cycle. Kept separate from
--.. ProductController.Bypass on purpose — that list also hands out every gamepass for free.

local Excluded = {
    [140977250] = true; --.. awesomeotheraccount (alt/test account)
}

return Excluded
