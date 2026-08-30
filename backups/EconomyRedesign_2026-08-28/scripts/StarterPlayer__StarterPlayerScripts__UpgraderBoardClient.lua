local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ControllerLoader = require(ReplicatedStorage.Modules.ControllerLoader)
local Network = ControllerLoader.GetController("Network")

local player = Players.LocalPlayer
local playerData = player:WaitForChild("PlayerData", 30)
local upgradesFolder = playerData:WaitForChild("Upgrades")
local petsFolder = playerData:WaitForChild("Pets")
local maxEquipped = petsFolder:WaitForChild("MaxEquipped")
local upgrader = workspace:WaitForChild("Upgrader", 30)
local boardPart = upgrader and upgrader:WaitForChild("Board", 30)
local surfaceGui = boardPart and boardPart:WaitForChild("SurfaceGui", 10)
local board = surfaceGui and surfaceGui:WaitForChild("UpgradeBoard", 10)
if not board then
	warn("[UpgraderBoardClient] Upgrade board was unavailable; client board wiring skipped.")
	return
end

local upgradeData = Network:InvokeServer("GetData", "Dictionary", {Name = "Upgrades"})
local upgradeStats = upgradeData.Stats or upgradeData

local cards = {
    PodiumsCard = {
        Upgrade = "Vault slots";
        Title = "Vault slots";
        Text = function(level)
            --.. mirrors BankBuilder.CapacityFor: 6 + rebirths (capped 50) + bought slots
            local leaderstats = player:FindFirstChild("leaderstats")
            local rebirths = leaderstats and leaderstats:FindFirstChild("Rebirths")
            local current = 6 + math.min(rebirths and rebirths.Value or 0, 50) + level
            return string.format("%d > %d", current, current + 1)
        end;
    };
    LuckCard = {
        Upgrade = "Pet equips";
        Title = "Pet equips";
        Text = function(level)
            local current = maxEquipped.Value
            return string.format("%d > %d", current, current + 1)
        end;
    };
    CooldownCard = {
        Upgrade = "Smashes required";
        Title = "-3 smashes required for portals";
        Text = function(level)
            --.. -3 required cucumbers per level on portal unlocks (portals only)
            return string.format("-%d > -%d", level * 3, (level + 1) * 3)
        end;
    };
}

local function formatPrice(value)
    value = math.floor(value + 0.5)
    local text = tostring(value)
    while true do
        local nextText, replacements = text:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
        text = nextText
        if replacements == 0 then break end
    end
    return text .. " Coins"
end

local function levelOf(upgradeName)
    local value = upgradesFolder:FindFirstChild(upgradeName)
    return value and value.Value or 0
end

local function priceOf(stats, level)
    return math.floor((stats.Price + stats.Price * level * stats.Increment) / 100 + 0.5) * 100
end

local function refreshCard(cardName)
    local config = cards[cardName]
    local card = board:FindFirstChild(cardName)
    if not config or not card then return end

    local title = card:FindFirstChild("UpgradeName")
    local stat = card:FindFirstChild("StatPanel") and card.StatPanel:FindFirstChild("Value")
    local button = card:FindFirstChild("UpgradeButton")
    local price = button and button:FindFirstChild("Price")

    if title then title.Text = config.Title end

    if config.ComingSoon then
        if stat then stat.Text = "Coming soon" end
        if price then price.Text = "--" end
        if button then
            button.Active = false
            button.AutoButtonColor = false
        end
        return
    end

    local stats = upgradeStats[config.Upgrade]
    if not stats then return end

    local level = levelOf(config.Upgrade)
    local maxed = level >= stats.Stats.MaxUpgrade
    if stat then stat.Text = maxed and "MAX" or config.Text(level) end
    if price then price.Text = maxed and "MAX" or formatPrice(priceOf(stats.Stats, level)) end
    if button then
        button.Active = not maxed
        button.AutoButtonColor = not maxed
    end
end

local function refreshAll()
    for cardName in pairs(cards) do
        refreshCard(cardName)
    end
end

for cardName, config in pairs(cards) do
    local card = board:FindFirstChild(cardName)
    local button = card and card:FindFirstChild("UpgradeButton")
    if button and config.Upgrade then
        button.MouseButton1Click:Connect(function()
            local stats = upgradeStats[config.Upgrade]
            if not stats or levelOf(config.Upgrade) >= stats.Stats.MaxUpgrade then return end
            if Network:InvokeServer("PurchaseUpgrade", config.Upgrade) then
                task.wait(0.1)
                refreshAll()
            end
        end)
    end
end

for _, value in ipairs(upgradesFolder:GetChildren()) do
    value.Changed:Connect(refreshAll)
end
upgradesFolder.ChildAdded:Connect(function(value)
    value.Changed:Connect(refreshAll)
    refreshAll()
end)
maxEquipped.Changed:Connect(refreshAll)

--.. the Vault slots card shows current capacity, which moves with rebirths too
task.spawn(function()
    local leaderstats = player:WaitForChild("leaderstats", 15)
    local rebirths = leaderstats and leaderstats:WaitForChild("Rebirths", 10)
    if rebirths then
        rebirths.Changed:Connect(refreshAll)
        refreshAll()
    end
end)

refreshAll()
