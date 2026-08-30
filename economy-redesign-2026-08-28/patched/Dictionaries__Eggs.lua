--..Services..--
--.. (coins economy July 2026: all eggs priced in Coins)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

--..Modules..--


--..Variables..--
local Eggs = workspace.Eggs

--..Functions..--

return {

    ["Stats"] = {
        ["Basic Egg"] = {
            Name = "Basic Egg";
            Price = 250;
            Currency = "Coins";
            Order = 1;
            Pets = {
                ["Gregory"] = {
                    Percent = 0.002; -- 1 in 50,000: the secret. See the Pets dictionary note.
                    -- No Rank ON PURPOSE: rank-less entries are invisible to the egg
                    -- display (EggController.UiController skips them), so he stays secret.
                };
                ["Cat"] = {
                    Percent = 40;
                    Rank = 1;
                };
                ["Dog"] = {
                    Percent = 30;
                    Rank = 2;
                };
                ["Bunny"] = {
                    Percent = 15;
                    Rank = 3;
                };
                ["Wolf"] = {
                    Percent = 9;
                    Rank = 4;
                };
                ["Tabby"] = {
                    Percent = 5;
                    Rank = 5;
                };
                ["Fox"] = {
                    Percent = 1;
                    Rank = 6;
                };
            };
        };

        ["Samurai Egg"] = {
            Name = "Samurai Egg";
            Price = 3000000;
            Currency = "Coins";
            Order = 3;
            Pets = {
                ["Dog Ninja"] = {
                    Percent = 40;
                    Rank = 1;
                };
                ["Good Ninja"] = {
                    Percent = 30;
                    Rank = 2;
                };
                ["Evil Ninja"] = {
                    Percent = 15;
                    Rank = 3;
                };
                ["Good Samurai"] = {
                    Percent = 9;
                    Rank = 4;
                };
                ["Evil Samurai"] = {
                    Percent = 5;
                    Rank = 5;
                };
                ["Sensei"] = {
                    Percent = 1;
                    Rank = 6;
                };
            };
        };

        ["Farm Egg"] = {
            Name = "Farm Egg";
            Price = 200000000;
            Currency = "Coins";
            Order = 4;
            Pets = {
                ["Hay"] = {
                    Percent = 40;
                    Rank = 1;
                };
                ["Bird"] = {
                    Percent = 30;
                    Rank = 2;
                };
                ["Panda"] = {
                    Percent = 15;
                    Rank = 3;
                };
                ["Cow"] = {
                    Percent = 9;
                    Rank = 4;
                };
                ["Pig"] = {
                    Percent = 5;
                    Rank = 5;
                };
                ["Farmer"] = {
                    Percent = 1;
                    Rank = 6;
                };
            };
        };

        ["Desert Egg"] = {
            Name = "Desert Egg";
            Price = 100000;
            Currency = "Coins";
            Order = 2;
            Pets = {
                ["Barrel"] = {
                    Percent = 40;
                    Rank = 1;
                };
                ["Treasure Gem"] = {
                    Percent = 30;
                    Rank = 2;
                };
                ["Cannon"] = {
                    Percent = 15;
                    Rank = 3;
                };
                ["Chest"] = {
                    Percent = 9;
                    Rank = 4;
                };
                ["Desert Overlord"] = {
                    Percent = 5;
                    Rank = 5;
                };
                ["Cactus"] = {
                    Percent = 1;
                    Rank = 6;
                };
            };
        };

        ["Ocean Egg"] = {
            Name = "Ocean Egg";
            Price = 500000000000;
            Currency = "Coins";
            Order = 6;
            Pets = {
                ["Oceanic Dog"] = {
                    Percent = 40;
                    Rank = 1;
                };
                ["Oceanic Kitty"] = {
                    Percent = 30;
                    Rank = 2;
                };
                ["Oceanic Bunny"] = {
                    Percent = 15;
                    Rank = 3;
                };
                ["Oceanic Bear"] = {
                    Percent = 9;
                    Rank = 4;
                };
                ["Ocean Dragon"] = {
                    Percent = 5;
                    Rank = 5;
                };
                ["Atlantic Hydra"] = {
                    Percent = 1;
                    Rank = 6;
                };
            };
        };

        ["Frozen Egg"] = {
            Name = "Frozen Egg";
            Price = 10000000000;
            Currency = "Coins";
            Order = 5;
            Pets = {
                ["Red Snowman"] = {
                    Percent = 40;
                    Rank = 1;
                };
                ["Blue Snowman"] = {
                    Percent = 30;
                    Rank = 2;
                };
                ["Frozen Dragon"] = {
                    Percent = 15;
                    Rank = 3;
                };
                ["Frozen Hydra"] = {
                    Percent = 9;
                    Rank = 4;
                };
                ["Frozen Ice Shock"] = {
                    Percent = 5;
                    Rank = 5;
                };
                ["Frozen Gem"] = {
                    Percent = 1;
                    Rank = 6;
                };
            };
        };

        ["Lava Egg"] = {
            Name = "Lava Egg";
            Price = 30000000000000;
            Currency = "Coins";
            Order = 7;
            Pets = {
                ["Lava Plume"] = {
                    Percent = 40;
                    Rank = 1;
                };
                ["Lava Golem"] = {
                    Percent = 30;
                    Rank = 2;
                };
                ["Lava Veltal"] = {
                    Percent = 15;
                    Rank = 3;
                };
                ["Lava Trio"] = {
                    Percent = 9.95;
                    Rank = 4;
                };
                ["Lava Dragon"] = {
                    Percent = 5;
                    Rank = 5;
                };
                ["Demon Dog"] = {
                    Percent = 0.05;
                    Rank = 6;
                };
            };
		};
		
		["Narmek Egg"] = {
			Name = "Narmek Egg";
			Price = 2000000000000000;
			-- while strictly better (m1 5.9-6.6 vs 5.2-5.6) made Lava pointless to buy.
			-- 5.5M keeps the egg ladder monotonic with the pet power curve.
			Currency = "Coins";
			Order = 8; --.. was a duplicate of Lava Egg's 7
			--.. own space-pet pool since 2026-08-21 (was a copy of Lava Egg's)
			Pets = {
				["Moon Bunny"] = {
					Percent = 40;
					Rank = 1;
				};
				["Satellite Pup"] = {
					Percent = 30;
					Rank = 2;
				};
				["Alien Slime"] = {
					Percent = 15;
					Rank = 3;
				};
				["Meteor Moth"] = {
					Percent = 9.95;
					Rank = 4;
				};
				["Nebula Fox"] = {
					Percent = 5;
					Rank = 5;
				};
				["Cosmo Cat"] = {
					Percent = 0.05;
					Rank = 6;
				};
			};
		};
		--.. Food Cuke Egg (added 2026-07-15) - reward-only; granted via PlaytimeRewards, no walk-up pad ..--
		["Food Cuke Egg"] = {
			Name = "Food Cuke Egg";
			Price = 600000;
			Currency = "Coins";
			Order = 99;
			Pets = {
				["Popcorn Cuke"] = { Percent = 30; Rank = 1; };
				["Cotton Candy Cuke"] = { Percent = 24; Rank = 2; };
				["Lollipop Cuke"] = { Percent = 18; Rank = 3; };
				["Fried Egg Cuke"] = { Percent = 12; Rank = 4; };
				["Cupcake Cuke"] = { Percent = 8; Rank = 5; };
				["Taco Cuke"] = { Percent = 4; Rank = 6; };
				["Watermelon Cuke"] = { Percent = 2.5; Rank = 7; };
				["Burger Cuke"] = { Percent = 1; Rank = 8; };
				["Pizza Cuke"] = { Percent = 0.49; Rank = 9; };
				["Ice Cream Cuke"] = { Percent = 0.01; Rank = 10; };
			};
		};
    };
}
