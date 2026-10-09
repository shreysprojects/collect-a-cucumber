--[[
    --..CiAxe..--
    
    Discord: CiAxe#0001
    Twitter: @axe_ci
    Date: 5.8.2021
]]

--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

--..Modules..--
local ControllerLoader = require(ReplicatedStorage.Modules.ControllerLoader)

local FastWait = ControllerLoader.GetController("FastWait")

--..Variables..--


local module = {

	["Bypass"] = {
        [1] = true; -- Tempest
        [1660029941] = true; -- Ethan
        [1196256323] = true; -- x5ew (Studio test account: owns all passes for testing)
	};

	["Gamepasses"] = {
		["2x Cucumbers"] = {
            Id = 1902852565;
			Order = 1;
			
			Icon = "rbxassetid://7130780022";
		};
		["Sprint"] = {
            Id = 1899183262;
			Order = 4;

			Icon = "rbxassetid://7130777591";
			Function = function(Player)
				do
					if Player then
						Player:SetAttribute("OwnsSprint", true)
						if Player:GetAttribute("SprintEnabled") == nil then
							Player:SetAttribute("SprintEnabled", true)
						end
						local Character = Player.Character
						if Character then
							local Humanoid = Character:FindFirstChild("Humanoid");
							if Humanoid then
								--.. Sprint = 2x your (default + upgrade) walkspeed. The real math lives in
								--.. ServerController Upgrades.setWalkSpeed so a respawn or a speed-upgrade
								--.. purchase can't wipe the buff -- here we just re-trigger that authority.
								local ok, SC = pcall(require, game:GetService("ServerStorage"):WaitForChild("ServerController"))
								if ok and SC and SC.GetDictionary then
									local Up = SC.GetDictionary("Upgrades")
									if Up and Up.SetWalkSpeed then Up.SetWalkSpeed(Player) end
								end
							end
						end
					end
				end
			end;
		};
		["Jetpack"] = {
			Id = 1919180303;
			Order = 8;

			Icon = "rbxassetid://7130777810";
			Function = function(Player)
				if Player then
					Player:SetAttribute("OwnsJetpack", true)
					if Player:GetAttribute("JetpackEnabled") == nil then
						Player:SetAttribute("JetpackEnabled", true)
					end
				end
			end;
		};
		["Autofarm"] = {
			Id = 1919162313;
			Order = 3;

			Icon = "rbxassetid://133062084543816";
			Function = function(Player)
				if Player then
					Player:SetAttribute("OwnsAutofarm", true)
					if Player:GetAttribute("AutoFarmEnabled") == nil then
						Player:SetAttribute("AutoFarmEnabled", true)
					end
				end
			end;
		};
		["Auto Egg Hatch"] = {
            Id = 1898883147;
			Order = 5;

			Icon = "rbxassetid://7130778624";
		};
		["Triple Egg Hatch"] = {
            Id = 1903566581;
			Order = 6;

			Icon = "rbxassetid://7130779292";
		};
		["Instant Egg Hatch"] = {
            Id = 1911700950;
			Order = 7;

			Icon = "rbxassetid://7130779180";
		};
		["+75 Pet Storage"] = {
            Id = 1899609194;
			Order = 9;

			Icon = "rbxassetid://7130781434";
			Function = function(Player)
				do
					local PlayerData = Player:WaitForChild("PlayerData")
					local PetsFolder = PlayerData:WaitForChild("Pets")
					local MaxInventory = PetsFolder:WaitForChild("MaxInventory")
					
					MaxInventory.Value += 75
				end
			end,
		};
		["+4 Pet Slots"] = {
            Id = 1903134517;
			Order = 13;

			Icon = "rbxassetid://7130781764";
			Function = function(Player)
				local ok, SC = pcall(require, game:GetService("ServerStorage"):WaitForChild("ServerController"))
				if ok and SC and SC.GetDictionary then
					local Upgrades = SC.GetDictionary("Upgrades")
					if Upgrades and Upgrades.SetPetEquips then Upgrades.SetPetEquips(Player) end
				end
			end,
		};
	};

	["Products"] = {
		
		
		["Boosts"] = {
			["2x Cucumbers"] = {
				["15 Minutes"] = {
					Id = 3609774448;
					Time = 900;
				};
				["1 Hour"] = {
					Id = 3609774551;
					Time = 3600;
				};
				["5 Hours"] = {
					Id = 3609774625;
					Time = 18000;
				};
			};
		};
		
		["Offers"] = {
			["Pets"] = {
				["Red Demon"] = {
					Order = 1;
				};
				["Purple Hydra"] = {
					Order = 2;
				};
				["Heavenly Angel"] = {
					Order = 3;
				};
			};
			
			["Packs"] = {
				["Starter Pack"] = {
					Description = "LIMITED TIME!";
					--.. Recreated 2026-07-14 under Group Frenzy.
                    Id = 3609836817;
					Order = 1;
					Items = {
						Coins = 20000;
						Pets = {"Red Demon"};
					};
				};
			};
		};
		
		--.. Pet dev products. These IDs drive BOTH the Offers UI cards AND the physical
		--.. Robux pet billboards around the map (StarterGui.PromotedPets.PromoteHandler
		--.. reads ProductController.Products.Pets[name].Id), so one edit covers both.
		["Pets"] = {
			["Red Demon"] = {
				Id = 3609774225;
				PetName = "Red Demon";
			};
			["Purple Hydra"] = {
				Id = 3609774320;
				PetName = "Purple Hydra";
			};
			["Heavenly Angel"] = {
				Id = 3609773882;
				PetName = "Heavenly Angel";
			}
		};
		
		--.. Recreated 2026-07-14 under Group Frenzy. The old ids (1230535503 / 1230535355)
		--.. belonged to the original kit's creator, so Robux spent on them never reached us
		--.. and our own ProcessReceipt could never fire for them.
		["+10 Pet Inventory"] = {
			Id = 3609836686;
		};
		
		["+2 Pets Equip"] = {
			Id = 3609836815;
		};

		--.. Time Skip durations and live dashboard product ids. Amount remains a compatibility
		--.. alias for Seconds; payout is always quoted by TimeSkipRateService from the player's
		--.. deterministic pickaxe + pet production rate for the highest unlocked zone.
		["TimeSkips"] = {
			["1 Minute"]   = { Id = 3609921759; Amount = 60;     Order = 1; Title = "1 MIN";  Seconds = 60; };
			["5 Minutes"]  = { Id = 3609921779; Amount = 300;    Order = 2; Title = "5 MIN";  Seconds = 300; };
			["30 Minutes"] = { Id = 3609921799; Amount = 1800;   Order = 3; Title = "30 MIN"; Seconds = 1800; };
			["5 Hours"]    = { Id = 3609921818; Amount = 18000;  Order = 4; Title = "5 HR";   Seconds = 18000; };
			["1 Day"]      = { Id = 3609921841; Amount = 86400;  Order = 5; Title = "1 DAY";  Seconds = 86400;  Emphasis = true; };
			["1 Week"]     = { Id = 3609921920; Amount = 604800; Order = 6; Title = "1 WEEK"; Seconds = 604800; Emphasis = true; };
		};

		--.. VAULT Time Skips (2026-08-26): the second skip mechanic -- fast-forwards
		--.. the COINS your stored vault cucumbers print (VaultTimeSkipService quotes
		--.. sum of EffectiveRate x seconds). Id 0 = placeholder: create the dev
		--.. products on the dashboard and paste their ids here; ProductHandler
		--.. skips Id 0 entries until then.
		["VaultTimeSkips"] = {
			["1 Minute"]   = { Id = 0; Amount = 60;     Order = 1; Title = "1 MIN";  Seconds = 60; };
			["5 Minutes"]  = { Id = 0; Amount = 300;    Order = 2; Title = "5 MIN";  Seconds = 300; };
			["30 Minutes"] = { Id = 0; Amount = 1800;   Order = 3; Title = "30 MIN"; Seconds = 1800; };
			["5 Hours"]    = { Id = 0; Amount = 18000;  Order = 4; Title = "5 HR";   Seconds = 18000; };
			["1 Day"]      = { Id = 0; Amount = 86400;  Order = 5; Title = "1 DAY";  Seconds = 86400;  Emphasis = true; };
			["1 Week"]     = { Id = 0; Amount = 604800; Order = 6; Title = "1 WEEK"; Seconds = 604800; Emphasis = true; };
		};

		["Skip Boss/Event Requirement"] = {
			Id = 3709040752;
		};

		["Unlock Portal Now!"] = {
			Id = 3709119039;
		};

		--[[
		
		["Product Name"] = {
			Id = 00000000;
		};
		
		--]]

	};

}

--..Functions..--

--.. Gets The Products Info -> Returns Table
--.. Marketplace hiccups (HTTP 5xx) get retried; if it still fails we return a
--.. harmless stub so callers indexing .PriceInRobux/.IsForSale can't crash a
--.. whole UI module mid-OnStart — prices just read 0 until the next session.
local ProductInfoCache = {}

function module.GetProductInfo(ProductId, Type)
	local infoType
	if Type == "Gamepass" then
		infoType = Enum.InfoType.GamePass
	elseif Type == "Product" then
		infoType = Enum.InfoType.Product
	end

	local cacheKey = tostring(Type) .. ":" .. tostring(ProductId)
	if ProductInfoCache[cacheKey] then
		return ProductInfoCache[cacheKey]
	end

	if infoType ~= nil and ProductId ~= nil then
		for attempt = 1, 3 do
			local Success, Result = pcall(function()
				return MarketplaceService:GetProductInfo(ProductId, infoType)
			end)
			if Success and type(Result) == "table" then
				ProductInfoCache[cacheKey] = Result
				return Result
			end
			if attempt < 3 then task.wait(attempt) end
		end
	end

	-- Marketplace lookup failures are transient and must not abort UI startup.
	-- Do not cache the stub, so a later panel can retry during the same session.
	return {PriceInRobux = 0, IsForSale = false, Name = "?", Description = ""}
end

--.. Cached ownership check for HOT paths (currency multipliers, auto-strike
--.. loops). Refreshes on purchase; safe with placeholder Id=0 (pcall false).
local OwnershipCache = {} -- [player] = {[name] = bool}

function module.CheckGamepassCached(Player, GamepassName)
	local cache = OwnershipCache[Player]
	if cache and cache[GamepassName] ~= nil then
		return cache[GamepassName]
	end
	if not cache then cache = {} OwnershipCache[Player] = cache end
	cache[GamepassName] = false -- pessimistic while the async check runs
	task.spawn(function()
		cache[GamepassName] = module.CheckGamepass(Player, GamepassName) == true
	end)
	return cache[GamepassName]
end

task.spawn(function()
	local MPS = game:GetService("MarketplaceService")
	local PlayersService = game:GetService("Players")
	MPS.PromptGamePassPurchaseFinished:Connect(function(Player, passId, purchased)
		if purchased then OwnershipCache[Player] = nil end -- recheck everything
	end)
	PlayersService.PlayerRemoving:Connect(function(Player)
		OwnershipCache[Player] = nil
	end)
end)

--.. Checks If The Player Owns Gamepass -> Returns Bool
function module.CheckGamepass(Player, GamepassName, PromptPurchase)
	local Success, Result = pcall(function()
		if Player then
			if Players:FindFirstChild(Player.Name) then
				local Gamepass = module.Gamepasses[GamepassName]
				if Gamepass ~= nil then
					if module.Bypass[Player.UserId] then return true end
					if MarketplaceService:UserOwnsGamePassAsync(Player.UserId, Gamepass.Id) then
						return true
					else
						if PromptPurchase then
							MarketplaceService:PromptGamePassPurchase(Player, Gamepass.Id)
							return false
						else
							return false
						end
					end
				end
			else
				return false
			end
		else
			return false
		end
	end)
	
	if not Success then
		warn("[CiAxe]: ".. Result)
		return false
	else
		return Result
	end
end

--.. Checks If The Player Owns Gamepass -> Returns Bool
function module.PromptProduct(Player, ProductId)
	local Success, Result = pcall(function()
		if Players:FindFirstChild(Player.Name) then
			if ProductId ~= nil then
				MarketplaceService:PromptProductPurchase(Player, ProductId)
			end
		end
	end)
	
	if not Success then
		warn("[CiAxe]: ".. Result)
		return false
	end
end

return module
