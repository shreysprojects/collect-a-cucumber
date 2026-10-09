--[[
	BaseHUDController  (ModuleScript, StarterGui.CucumberHUDDesign)
	Swaps the left menu between the lobby pair (Shop / Index) and the base pair (Build / Manage)
	as the player walks in and out of their own plot, plus the BenchStrength offer while lying on
	the bench. Mirrors the result into the HUD attributes BaseMode / BenchMode (MenuController
	closes the panels, HUDClient enlarges the strength row).

	2026-09-10 (user: "tween the shop and index out and tween the build and manage in with a really
	nice transition, noticeable but not disruptive"): the swap is animated instead of flipping
	Visible. The leaving button slides toward the screen edge while shrinking and fading (0.16 s,
	Quad In); the arriving one follows it back in from the edge with a small overshoot (0.30 s,
	Back Out), setting off while the old one is still on its way; the bottom row trails the top
	row by 0.06 s. Motion is stepped on Heartbeat (ButtonFX.Animate) like the rest of the HUD, so
	it also plays in an unfocused Studio. Size and Position are driven directly (no UIScale:
	MenuController's HoverScale already owns each button's UIScale slot, and two do not stack) and
	each button fades through a snapshot of its authored transparencies, so no CanvasGroup is needed.
	Rapid boundary crossings are safe: a newer swap cancels the running one and carries on from the
	button's current pose.
	2026-09-10 (later, build mode): the HUD attribute BuildMode = true (BuildMenuClient) tucks the
	whole menu away with the same motion while the player is in their base; false brings the base
	pair back.
	2026-09-10 (later, user: "make build and manage buttons tween scale on hover"): Build and Manage
	get the hover / press pop MenuController gives Shop and Index - a HoverScale UIScale eased to
	1.035 on MouseEnter and 0.97 while pressed (0.12 s, Heartbeat-stepped so it also plays in an
	unfocused Studio); it is reset to 1 whenever the button tucks away.
	2026-09-22 (pet system): the paw-shaped Pets opener (LeftMenu.Pets, built by
	pets-system/builders/build_petspanel.lua, to the right of the top row) is a state of its own in
	slot 3, so it never waits on another occupant: shown in and out of the base, tucked away with the
	same motion in build mode and while lying on the bench (Slow Mode's rule). It is optional and
	never blocks Start: it is looked up after the original five (which still WaitForChild), and when
	it has not replicated yet a spawned WaitForChild (10 s, MenuController's wait) adds it late and
	re-applies the current mode to it. MenuController owns its click and hover
	pop, so it is not in HOVERED. Hatch reveals need nothing here: EggHatchClient's HideUi disables
	every PlayerGui layer during a reveal, and PetController ignores its P / ButtonL3 key while
	CucumberMenus is disabled or the HUD attributes BuildMode / BenchMode are set.
	2026-09-22 (review #12): the paw draws smaller than its Size box (a Square FitWithinMaxSize
	constraint), so the tuck slides and centres it by its DRAWN width (DrawnShare): it travels 42 % of
	its own width like the others instead of a whole menu width onto the Shop / Build button.
	Dev hooks: HUD attribute BaseDev = "inside" | "bench" | "outside" forces a mode (nil releases it);
	HoverDev = "hover:Build" | "leave:Manage" | "press:Build" drives the pop.
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ButtonFX = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ButtonFX"))

local Controller = {}

local HIDE_SECONDS = 0.16
local SHOW_SECONDS = 0.30
local SHOW_DELAY = 0.08   -- the arriving button sets off while the leaving one is still going
local ROW_STAGGER = 0.06  -- the bottom row follows the top row
local SLIDE = 0.42        -- travel toward the screen edge, as a fraction of the button's width
local SHRINK = 0.82       -- size at the far end of the travel
local FADE_END = 0.85     -- presence at which a button is fully opaque again
local HOVER_SCALE = 1.035 -- MenuController's numbers for Shop / Index
local PRESS_SCALE = 0.97
local HOVER_SECONDS = 0.12
local SLOTS = {Shop = 1, Build = 1, Index = 2, Manage = 2, BenchStrength = 2, Pets = 3} -- 2026-09-22: Pets has its own slot
local OPTIONAL_SLOTS = {Pets = true} -- 2026-09-22: skipped when the pets builder has not run
local OPTIONAL_WAIT = 10 -- 2026-09-22: seconds a late-replicating optional button is waited for (off the Start thread)
local HOVERED = {Build = "BuildButton", Manage = "ManageButton"} -- button -> its full-size TextButton

-- Match PlacementClient / CucumberPlacementClient's owned-plot boundary.
function Controller.Contains(plot, position)
    local point = plot.CFrame:PointToObjectSpace(position)
    return math.abs(point.X) <= plot.Size.X * 0.5 + 6
        and math.abs(point.Z) <= plot.Size.Z * 0.5 + 6
        and point.Y > -10 and point.Y < 60
end

--.. every transparency that makes up a button's look, so the whole thing fades as one
local function Snapshot(button)
    local rest = {}
    local function record(inst, prop)
        local value = inst[prop]
        if value < 1 then
            rest[inst] = rest[inst] or {}
            rest[inst][prop] = value
        end
    end
    local function visit(inst)
        if inst:IsA("GuiObject") then record(inst, "BackgroundTransparency") end
        if inst:IsA("ImageLabel") or inst:IsA("ImageButton") then record(inst, "ImageTransparency") end
        if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then record(inst, "TextTransparency") end
        if inst:IsA("UIStroke") then record(inst, "Transparency") end
    end
    visit(button)
    for _, inst in button:GetDescendants() do visit(inst) end
    return rest
end

--.. 2026-09-22 (review #12): the share of its Size box a button really draws, per axis. A FitWithinMaxSize
--.. UIAspectRatioConstraint draws the largest box of its ratio inside that box (the Square paw: Size (1, 0.455) of
--.. the LeftMenu, drawn 0.455H = 0.389W wide), so the slide and the centring must use the drawn size, or the paw
--.. travels a whole menu width onto the slot-1 button and shrinks toward its right edge. Size and constraint both
--.. scale with k, so the share holds all through a move. Any other aspect type keeps the box (none is tracked).
function Controller.DrawnShare(size, parentSize, aspect)
    if not aspect or aspect.AspectType ~= Enum.AspectType.FitWithinMaxSize then return 1, 1 end
    local ratio = aspect.AspectRatio
    local w = size.X.Scale * parentSize.X + size.X.Offset
    local h = size.Y.Scale * parentSize.Y + size.Y.Offset
    if not (ratio > 0 and w > 0 and h > 0) then return 1, 1 end -- not laid out yet (or NaN): the box
    if w / h > ratio then return h * ratio / w, 1 end
    return 1, w / ratio / h
end

--.. presence 0 = tucked toward the screen edge, small and clear; 1 = the authored pose
--.. (Back easing pushes it a little past 1, which is the overshoot); sx / sy = DrawnShare
function Controller.Pose(pos, size, p, sx, sy)
    local k = SHRINK + (1 - SHRINK) * p
    return UDim2.new(size.X.Scale * k, size.X.Offset * k, size.Y.Scale * k, size.Y.Offset * k),
        UDim2.new(
            pos.X.Scale + size.X.Scale * sx * ((1 - k) * 0.5 - SLIDE * (1 - p)), pos.X.Offset + size.X.Offset * sx * (1 - k) * 0.5,
            pos.Y.Scale + size.Y.Scale * sy * (1 - k) * 0.5, pos.Y.Offset + size.Y.Offset * sy * (1 - k) * 0.5)
end

local function Apply(state)
    local p = state.Presence
    local button = state.Button
    local sx, sy = Controller.DrawnShare(state.RestSize, state.Menu.AbsoluteSize, state.Aspect)
    button.Size, button.Position = Controller.Pose(state.RestPosition, state.RestSize, p, sx, sy)
    local fade = 1 - math.clamp(p / FADE_END, 0, 1)
    for inst, props in state.Rest do
        for prop, value in props do inst[prop] = value + (1 - value) * fade end
    end
    button.Visible = p > 0.001
end

--.. ease the button's presence to target after delay; a newer Move on the same button cancels it
local function Move(state, target, seconds, style, direction, delay)
    state.Token += 1
    local token = state.Token
    task.spawn(function()
        if delay > 0 then task.wait(delay) end
        if state.Token ~= token then return end
        -- leaving from the settled pose: re-read the look in case something restyled the button
        if target < state.Presence and state.Presence >= 1 then state.Rest = Snapshot(state.Button) end
        local from = state.Presence
        local distance = math.abs(target - from)
        if distance > 0.001 then
            ButtonFX.Animate(math.max(0.03, seconds * math.min(1, distance)), style, direction, function(a)
                state.Presence = from + (target - from) * a
                Apply(state)
            end, function() return state.Token == token end)
        end
        if state.Token == token then
            state.Presence = target
            Apply(state)
            -- tucked away: forget any hover / press pop so it comes back at rest
            if target <= 0 then
                local hover = state.Button:FindFirstChild("HoverScale")
                if hover then hover.Scale = 1 end
            end
        end
    end)
end

function Controller.Start(hud)
    local player = Players.LocalPlayer
    local plots = workspace:WaitForChild("Map"):WaitForChild("Lobby"):WaitForChild("Plots")
    local menu = hud:WaitForChild("LeftMenu")
    local states = {}
    local function track(name, button)
        states[name] = {
            Button = button,
            Target = button.Visible,
            Presence = button.Visible and 1 or 0,
            RestPosition = button.Position,
            RestSize = button.Size,
            Menu = menu, -- 2026-09-22 (review #12): the paw's drawn share is measured against the menu
            Aspect = button:FindFirstChildOfClass("UIAspectRatioConstraint"),
            Rest = Snapshot(button),
            Token = 0,
        }
    end
    -- 2026-09-22: the required five first, so an optional button is only looked up after them
    for name in SLOTS do
        if not OPTIONAL_SLOTS[name] then track(name, menu:WaitForChild(name)) end
    end
    local late = {} -- optional buttons that had not replicated yet
    for name in OPTIONAL_SLOTS do
        local button = menu:FindFirstChild(name)
        if button then track(name, button) else table.insert(late, name) end
    end
    local current = nil
    local currentBench = nil
    local currentBuilding = nil -- build mode (BuildMenuClient sets the HUD attribute BuildMode): the whole menu tucks away
    local settled = false -- the first mode is applied without motion
    local connections = {}
    local elapsed = 0
    local function setMode(inside, onBench, building)
        onBench = onBench == true
        building = building == true and inside
        if current == inside and currentBench == onBench and currentBuilding == building then return end
        current = inside
        currentBench = onBench
        currentBuilding = building
        local wanted = {
            Shop = not inside,
            Index = not inside and not onBench,
            Build = inside and not building,
            Manage = inside and not onBench and not building,
            BenchStrength = onBench and not building,
            Pets = not building and not onBench, -- 2026-09-22: the paw stays in and out of the base
        }
        -- a slot whose occupant is leaving makes its newcomer wait for it
        local leaving = {}
        for name, state in states do
            if state.Target and not wanted[name] then leaving[SLOTS[name]] = true end
        end
        for name, state in states do
            local show = wanted[name]
            if show ~= state.Target then
                state.Target = show
                local stagger = (SLOTS[name] - 1) * ROW_STAGGER
                if not settled then
                    state.Token += 1
                    state.Presence = show and 1 or 0
                    Apply(state)
                elseif show then
                    -- wait for the slot's occupant to clear, unless this one is already part-way in (a reversal)
                    local delay = stagger + ((leaving[SLOTS[name]] and state.Presence <= 0) and SHOW_DELAY or 0)
                    Move(state, 1, SHOW_SECONDS, Enum.EasingStyle.Back, Enum.EasingDirection.Out, delay)
                else
                    Move(state, 0, HIDE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In, stagger)
                end
            end
        end
        settled = true
        hud:SetAttribute("BenchMode", onBench)
        hud:SetAttribute("BaseMode", inside)
    end
    local function update()
        local building = hud:GetAttribute("BuildMode") == true
        local dev = hud:GetAttribute("BaseDev")
        if dev == "inside" or dev == "bench" or dev == "outside" then
            setMode(dev ~= "outside", dev == "bench", building)
            return
        end
        local character = player.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        local seat = humanoid and humanoid.SeatPart
        local onBench = humanoid ~= nil and humanoid.Health > 0 and seat ~= nil and seat:GetAttribute("LiePose") == true
        if root and humanoid and humanoid.Health > 0 then
            for _, plot in plots:GetChildren() do
                if plot:IsA("BasePart") and plot:GetAttribute("Owner") == player.UserId
                    and Controller.Contains(plot, root.Position) then
                    setMode(true, onBench, building)
                    return
                end
            end
        end
        setMode(false, onBench, building)
    end
    -- hover / press pops on the base pair, the way MenuController does Shop / Index: a HoverScale
    -- UIScale eased on Heartbeat; a newer target cancels the running ease
    local hoverTokens = {}
    local function scaleTo(button, target)
        local scale = button:FindFirstChild("HoverScale")
        if not scale then
            scale = Instance.new("UIScale")
            scale.Name = "HoverScale"
            scale.Parent = button
        end
        local token = (hoverTokens[button] or 0) + 1
        hoverTokens[button] = token
        local from = scale.Scale
        task.spawn(function()
            ButtonFX.Animate(HOVER_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, function(a)
                scale.Scale = from + (target - from) * a
            end, function() return hoverTokens[button] == token and button.Parent ~= nil end)
        end)
    end
    local function isPointer(input)
        return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
    end
    for name, pressName in HOVERED do
        local button = states[name].Button
        local press = button:WaitForChild(pressName)
        table.insert(connections, press.MouseEnter:Connect(function() scaleTo(button, HOVER_SCALE) end))
        table.insert(connections, press.MouseLeave:Connect(function() scaleTo(button, 1) end))
        table.insert(connections, press.InputBegan:Connect(function(input) if isPointer(input) then scaleTo(button, PRESS_SCALE) end end))
        table.insert(connections, press.InputEnded:Connect(function(input) if isPointer(input) then scaleTo(button, 1) end end))
    end
    table.insert(connections, RunService.Heartbeat:Connect(function(dt)
        elapsed += dt
        if elapsed < 0.1 then return end
        elapsed = 0
        update()
    end))
    table.insert(connections, player.CharacterRemoving:Connect(function() setMode(false) end))
    table.insert(connections, player.CharacterAdded:Connect(update))
    table.insert(connections, hud:GetAttributeChangedSignal("BaseDev"):Connect(update))
    table.insert(connections, hud:GetAttributeChangedSignal("BuildMode"):Connect(update))
    table.insert(connections, hud:GetAttributeChangedSignal("HoverDev"):Connect(function()
        local cmd = hud:GetAttribute("HoverDev")
        if type(cmd) ~= "string" or cmd == "" then return end
        hud:SetAttribute("HoverDev", nil)
        local action, name = cmd:match("^(%a+):(%a+)$")
        local state = name and states[name]
        if not state then return end
        if action == "hover" then scaleTo(state.Button, HOVER_SCALE)
        elseif action == "press" then scaleTo(state.Button, PRESS_SCALE)
        elseif action == "leave" then scaleTo(state.Button, 1) end
    end))
    update()
    -- 2026-09-22: an optional button that replicates after Start joins in its own thread and takes the
    -- current mode at once (no motion, like the first mode); the others are already there, so nothing moves
    local stopped = false
    for _, name in late do
        task.spawn(function()
            local button = menu:WaitForChild(name, OPTIONAL_WAIT)
            if stopped or not button or states[name] then return end
            track(name, button)
            current = nil
            settled = false
            update()
        end)
    end
    return {Destroy = function()
        stopped = true
        for _, connection in connections do connection:Disconnect() end
        for _, state in states do state.Token += 1 end
        for button in hoverTokens do hoverTokens[button] += 1 end
    end}
end
return Controller
