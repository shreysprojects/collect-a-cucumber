--..Services..--
--.. (2026-08-28 ECONOMY REDESIGN: Multi1 floors x3/area (1 -> 2.5K), Damage x~12/area (2 -> 270M).)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

--..Modules..--


--..Variables..--
local Assets = ReplicatedStorage:FindFirstChild("Assets")
local Pets = Assets.Pets

--..Functions..--

return {

    ["Stats"] = {
        ["Cat"] = {
            Type = "Waddle";
            Model = Pets:FindFirstChild("Cat");

            Stats = {
                Multi1 = 1;
                Damage = 2;
                Multi2 = 1;
            };

            Rarity = "Common";
            Order = 10000;
            Icon = "rbxassetid://7223840857";
        };
        ["Dog"] = {
            Type = "Waddle";
            Model = Pets:FindFirstChild("Dog");

            Stats = {
                Multi1 = 1;
                Damage = 2.5;
                Multi2 = 1;
            };

            Rarity = "Common";
            Order = 9999;
            Icon = "rbxassetid://7223840481";
        };
        ["Bunny"] = {
            Type = "Waddle";
            Model = Pets:FindFirstChild("Bunny");

            Stats = {
                Multi1 = 1.5;
                Damage = 3;
                Multi2 = 1;
            };

            Rarity = "Uncommon";
            Order = 9998;
            Icon = "rbxassetid://7259997908";
        };
        ["Wolf"] = {
            Type = "Waddle";
            Model = Pets:FindFirstChild("Wolf");

            Stats = {
                Multi1 = 2;
                Damage = 4;
                Multi2 = 1;
            };

            Rarity = "Rare";
            Order = 9997;
            Icon = "rbxassetid://7259997627";
        };
        ["Tabby"] = {
            Type = "Waddle";
            Model = Pets:FindFirstChild("Tabby");

            Stats = {
                Multi1 = 3;
                Damage = 5.5;
                Multi2 = 1.5;
            };

            Rarity = "Rare";
            Order = 9996;
            Icon = "rbxassetid://7260983657";
        };
        ["Fox"] = {
            Type = "Waddle";
            Model = Pets:FindFirstChild("Fox");

            Stats = {
                Multi1 = 4.5;
                Damage = 9;
                Multi2 = 1.5;
            };

            Rarity = "Legendary";
            Order = 9995;
            Icon = "rbxassetid://7260983899";
        };

        ["Barrel"] = {
            Type = "Waddle";
            Model = Pets["Barrel"];

            Stats = {
                Multi1 = 3.5;
                Damage = 25;
                Multi2 = 1.5;
            };

            Rarity = "Common";
            Order = 9994;
            Icon = "rbxassetid://7260983899";
        };
        ["Treasure Gem"] = {
            Type = "Waddle";
            Model = Pets["Treasure Gem"];

            Stats = {
                Multi1 = 4.5;
                Damage = 31;
                Multi2 = 1.5;
            };

            Rarity = "Common";
            Order = 9993;
            Icon = "rbxassetid://7260983899";
        };
        ["Cannon"] = {
            Type = "Waddle";
            Model = Pets["Cannon"];

            Stats = {
                Multi1 = 5.5;
                Damage = 40;
                Multi2 = 1.5;
            };

            Rarity = "Common";
            Order = 9992;
            Icon = "rbxassetid://7260983899";
        };
        ["Chest"] = {
            Type = "Waddle";
            Model = Pets.Chest;

            Stats = {
                Multi1 = 7.5;
                Damage = 52;
                Multi2 = 2;
            };

            Rarity = "Uncommon";
            Order = 9991;
            Icon = "rbxassetid://7260983899";
        };
        ["Desert Overlord"] = {
            Type = "Waddle";
            Model = Pets["Desert Overlord"];

            Stats = {
                Multi1 = 10;
                Damage = 70;
                Multi2 = 2;
            };

            Rarity = "Rare";
            Order = 9990;
            Icon = "rbxassetid://7260983899";
        };
        ["Cactus"] = {
            Type = "Flying";
            Model = Pets:FindFirstChild("Cactus");

            Stats = {
                Multi1 = 16;
                Damage = 110;
                Multi2 = 2.5;
            };

            Rarity = "Legendary";
            Order = 9989;
            Icon = "rbxassetid://7243354360";
        };

        ["Dog Ninja"] = {
            Type = "Waddle";
            Model = Pets["Dog Ninja"];

            Stats = {
                Multi1 = 10;
                Damage = 280;
                Multi2 = 2;
            };

            Rarity = "Common";
            Order = 9988;
            Icon = "rbxassetid://7260983899";
        };
        ["Good Ninja"] = {
            Type = "Waddle";
            Model = Pets["Good Ninja"];

            Stats = {
                Multi1 = 12;
                Damage = 350;
                Multi2 = 2;
            };

            Rarity = "Uncommon";
            Order = 9987;
            Icon = "rbxassetid://7260983899";
        };
        ["Evil Ninja"] = {
            Type = "Waddle";
            Model = Pets["Evil Ninja"];

            Stats = {
                Multi1 = 16;
                Damage = 450;
                Multi2 = 2.5;
            };

            Rarity = "Uncommon";
            Order = 9986;
            Icon = "rbxassetid://7260983899";
        };
        ["Good Samurai"] = {
            Type = "Waddle";
            Model = Pets["Good Samurai"];

            Stats = {
                Multi1 = 21;
                Damage = 590;
                Multi2 = 3;
            };

            Rarity = "Rare";
            Order = 9985;
            Icon = "rbxassetid://7260983899";
        };
        ["Evil Samurai"] = {
            Type = "Waddle";
            Model = Pets["Evil Samurai"];

            Stats = {
                Multi1 = 28;
                Damage = 780;
                Multi2 = 4;
            };

            Rarity = "Rare";
            Order = 9984;
            Icon = "rbxassetid://7260983899";
        };
        ["Sensei"] = {
            Type = "Waddle";
            Model = Pets["Sensei"];

            Stats = {
                Multi1 = 45;
                Damage = 1300;
                Multi2 = 5.5;
            };

            Rarity = "Legendary";
            Order = 9983;
            Icon = "rbxassetid://7260983899";
        };

        ["Hay"] = {
            Type = "Waddle";
            Model = Pets["Hay"];

            Stats = {
                Multi1 = 30;
                Damage = 3200;
                Multi2 = 4;
            };

            Rarity = "Common";
            Order = 9982;
            Icon = "rbxassetid://7260983899";
        };
        ["Bird"] = {
            Type = "Waddle";
            Model = Pets["Bird"];

            Stats = {
                Multi1 = 38;
                Damage = 4000;
                Multi2 = 5;
            };

            Rarity = "Common";
            Order = 9981;
            Icon = "rbxassetid://7260983899";
        };
        ["Panda"] = {
            Type = "Waddle";
            Model = Pets["Panda"];

            Stats = {
                Multi1 = 48;
                Damage = 5100;
                Multi2 = 6;
            };

            Rarity = "Uncommon";
            Order = 9980;
            Icon = "rbxassetid://7260983899";
        };
        ["Cow"] = {
            Type = "Waddle";
            Model = Pets["Cow"];

            Stats = {
                Multi1 = 63;
                Damage = 6700;
                Multi2 = 7.5;
            };

            Rarity = "Uncommon";
            Order = 9979;
            Icon = "rbxassetid://7260983899";
        };
        ["Pig"] = {
            Type = "Waddle";
            Model = Pets["Pig"];

            Stats = {
                Multi1 = 84;
                Damage = 9000;
                Multi2 = 9.5;
            };

            Rarity = "Rare";
            Order = 9978;
            Icon = "rbxassetid://7260983899";
        };
        ["Farmer"] = {
            Type = "Waddle";
            Model = Pets["Farmer"];

            Stats = {
                Multi1 = 140;
                Damage = 14000;
                Multi2 = 15;
            };

            Rarity = "Legendary";
            Order = 9977;
            Icon = "rbxassetid://7260983899";
        };

        ["Red Snowman"] = {
            Type = "Waddle";
            Model = Pets["Red Snowman"];

            Stats = {
                Multi1 = 90;
                Damage = 38000;
                Multi2 = 10;
            };

            Rarity = "Common";
            Order = 9976;
            Icon = "rbxassetid://7260983899";
        };
        ["Blue Snowman"] = {
            Type = "Waddle";
            Model = Pets["Blue Snowman"];

            Stats = {
                Multi1 = 110;
                Damage = 48000;
                Multi2 = 12;
            };

            Rarity = "Common";
            Order = 9975;
            Icon = "rbxassetid://7260983899";
        };
        ["Frozen Dragon"] = {
            Type = "Waddle";
            Model = Pets["Frozen Dragon"];

            Stats = {
                Multi1 = 140;
                Damage = 61000;
                Multi2 = 15;
            };

            Rarity = "Uncommon";
            Order = 9974;
            Icon = "rbxassetid://7260983899";
        };
        ["Frozen Hydra"] = {
            Type = "Waddle";
            Model = Pets["Frozen Hydra"];

            Stats = {
                Multi1 = 190;
                Damage = 80000;
                Multi2 = 20;
            };

            Rarity = "Uncommon";
            Order = 9973;
            Icon = "rbxassetid://7260983899";
        };
        ["Frozen Ice Shock"] = {
            Type = "Waddle";
            Model = Pets["Frozen Ice Shock"];

            Stats = {
                Multi1 = 250;
                Damage = 110000;
                Multi2 = 26;
            };

            Rarity = "Rare";
            Order = 9972;
            Icon = "rbxassetid://7260983899";
        };
        ["Frozen Gem"] = {
            Type = "Waddle";
            Model = Pets["Frozen Gem"];

            Stats = {
                Multi1 = 400;
                Damage = 170000;
                Multi2 = 41;
            };

            Rarity = "Legendary";
            Order = 9971;
            Icon = "rbxassetid://7260983899";
        };

        ["Oceanic Dog"] = {
            Type = "Waddle";
            Model = Pets["Oceanic Dog"];

            Stats = {
                Multi1 = 280;
                Damage = 430000;
                Multi2 = 29;
            };

            Rarity = "Common";
            Order = 9970;
            Icon = "rbxassetid://7260983899";
        };
        ["Oceanic Kitty"] = {
            Type = "Waddle";
            Model = Pets["Oceanic Kitty"];

            Stats = {
                Multi1 = 340;
                Damage = 540000;
                Multi2 = 35;
            };

            Rarity = "Common";
            Order = 9969;
            Icon = "rbxassetid://7260983899";
        };
        ["Oceanic Bunny"] = {
            Type = "Waddle";
            Model = Pets["Oceanic Bunny"];

            Stats = {
                Multi1 = 440;
                Damage = 690000;
                Multi2 = 45;
            };

            Rarity = "Uncommon";
            Order = 9968;
            Icon = "rbxassetid://7260983899";
        };
        ["Oceanic Bear"] = {
            Type = "Waddle";
            Model = Pets["Oceanic Bear"];

            Stats = {
                Multi1 = 580;
                Damage = 900000;
                Multi2 = 59;
            };

            Rarity = "Uncommon";
            Order = 9967;
            Icon = "rbxassetid://7260983899";
        };
        ["Ocean Dragon"] = {
            Type = "Waddle";
            Model = Pets["Ocean Dragon"];

            Stats = {
                Multi1 = 770;
                Damage = 1200000;
                Multi2 = 78;
            };

            Rarity = "Rare";
            Order = 9966;
            Icon = "rbxassetid://7260983899";
        };
        ["Atlantic Hydra"] = {
            Type = "Waddle";
            Model = Pets["Atlantic Hydra"];

            Stats = {
                Multi1 = 1200;
                Damage = 1900000;
                Multi2 = 120;
            };

            Rarity = "Legendary";
            Order = 9965;
            Icon = "rbxassetid://7260983899";
        };

        ["Lava Plume"] = {
            Type = "Waddle";
            Model = Pets["Lava Plume"];

            Stats = {
                Multi1 = 800;
                Damage = 5000000;
                Multi2 = 81;
            };

            Rarity = "Common";
            Order = 9964;
            Icon = "rbxassetid://7260983899";
        };
        ["Lava Golem"] = {
            Type = "Waddle";
            Model = Pets["Lava Golem"];

            Stats = {
                Multi1 = 1000;
                Damage = 6200000;
                Multi2 = 100;
            };

            Rarity = "Common";
            Order = 9963;
            Icon = "rbxassetid://7260983899";
        };
        ["Lava Veltal"] = {
            Type = "Waddle";
            Model = Pets["Lava Veltal"];

            Stats = {
                Multi1 = 1300;
                Damage = 8000000;
                Multi2 = 130;
            };

            Rarity = "Uncommon";
            Order = 9962;
            Icon = "rbxassetid://7260983899";
        };
        ["Lava Trio"] = {
            Type = "Waddle";
            Model = Pets["Lava Trio"];

            Stats = {
                Multi1 = 1700;
                Damage = 10000000;
                Multi2 = 170;
            };

            Rarity = "Rare";
            Order = 9961;
            Icon = "rbxassetid://7260983899";
        };
        ["Lava Dragon"] = {
            Type = "Waddle";
            Model = Pets["Lava Dragon"];

            Stats = {
                Multi1 = 2200;
                Damage = 14000000;
                Multi2 = 220;
            };

            Rarity = "Rare";
            Order = 9960;
            Icon = "rbxassetid://7260983899";
        };
        ["Demon Dog"] = {
            Type = "Waddle";
            Model = Pets["Demon Dog"];

            Stats = {
                Multi1 = 3600;
                Damage = 22000000;
                Multi2 = 360;
            };

            Rarity = "Mythical"; -- was Legendary (2026-08-22): at 1-in-10,000 odds the label
            -- undersold it -- Basic Egg hands out "Legendary" at 1.5%. Mythical matches its
            -- true chase-pet status (and the rarity color players learn to hunt).
            Order = 9959;
            Icon = "rbxassetid://7260983899";
		};
		
		--..Narmek egg pets (space band, zone 8 -- hand-modelled Blender imports,
		--..sits just above the Lava band: Multi 5.9-6.8, Damage 150-375)..--
		["Moon Bunny"] = {
			Type = "Waddle";
			Model = Pets["Moon Bunny"];

			Stats = {
				Multi1 = 2500;
				Damage = 60000000;
				Multi2 = 250;
			};

			Rarity = "Common";
			Order = 9957;
			Icon = "rbxassetid://7260983899";
		};
		["Satellite Pup"] = {
			Type = "Waddle";
			Model = Pets["Satellite Pup"];

			Stats = {
				Multi1 = 3100;
				Damage = 75000000;
				Multi2 = 310;
			};

			Rarity = "Common";
			Order = 9956;
			Icon = "rbxassetid://7260983899";
		};
		["Alien Slime"] = {
			Type = "Waddle";
			Model = Pets["Alien Slime"];

			Stats = {
				Multi1 = 4000;
				Damage = 96000000;
				Multi2 = 400;
			};

			Rarity = "Uncommon";
			Order = 9955;
			Icon = "rbxassetid://7260983899";
		};
		["Meteor Moth"] = {
			Type = "Waddle";
			Model = Pets["Meteor Moth"];

			Stats = {
				Multi1 = 5200;
				Damage = 130000000;
				Multi2 = 520;
			};

			Rarity = "Rare";
			Order = 9954;
			Icon = "rbxassetid://7260983899";
		};
		["Nebula Fox"] = {
			Type = "Waddle";
			Model = Pets["Nebula Fox"];

			Stats = {
				Multi1 = 7000;
				Damage = 170000000;
				Multi2 = 700;
			};

			Rarity = "Legendary";
			Order = 9953;
			Icon = "rbxassetid://7260983899";
		};
		["Cosmo Cat"] = {
			Type = "Waddle";
			Model = Pets["Cosmo Cat"];

			Stats = {
				Multi1 = 11000;
				Damage = 270000000;
				Multi2 = 1100;
			};

			Rarity = "Mythical";
			Order = 9952;
			Icon = "rbxassetid://7260983899";
		};
		
		--..Products..--
        ["Red Demon"] = {
            Type = "Flying";
            Model = Pets:FindFirstChild("Red Demon");

            Stats = {
                Multi1 = 500;
                Damage = 500000;
                Multi2 = 51;
            };

            Rarity = "Omega";
            Order = 9510;
            Icon = "rbxassetid://7243354360";
        };

        ["Purple Hydra"] = {
            Type = "Flying";
            Model = Pets:FindFirstChild("Purple Hydra");

            Stats = {
                Multi1 = 800;
                Damage = 900000;
                Multi2 = 81;
            };

            Rarity = "Omega";
            Order = 9509;
            Icon = "rbxassetid://7243354697";
        };
        ["Heavenly Angel"] = {
            Type = "Flying";
            Model = Pets['Heavenly Angel'];

            Stats = {
                Multi1 = 800;
                Damage = 900000;
                Multi2 = 81;
            };

            Rarity = "Mythical";
            Order = 9508;
            Icon = "rbxassetid://7243354360";
        };


        --..Cucumber pets (starter gift + season prizes, never in egg pools)..--
        ["Lil Pickle"] = {
            Type = "Waddle";
            Model = Pets:FindFirstChild("Lil Pickle");

            Stats = {
                Multi1 = 2;
                Damage = 3;
                Multi2 = 1;
            };

            Rarity = "Special";
            Order = 5;
            Icon = "rbxassetid://7243354360";
        };
--.. BOSS PETS — one per zone boss, each a shrunken copy of that boss's own cucumber
        --.. (models are generated from the same BuildCucumber geometry, so a boss pet looks
        --.. exactly like a mini version of the boss you beat). Earned ONLY from that boss:
        --.. every kill you damaged drops 1 shard of THAT boss, and 10 of them forge its pet.
        --.. The shards are spent, so each pet is repeatable — 10 more forges another.
        --.. Stats climb with zone difficulty but stay under the Robux pets (500 dmg / 30x)
        --.. so the paid tier is still the strongest. Tune freely here.
        ["Colossal Cucumber"] = {
            Type = "Waddle";
            Model = Pets:FindFirstChild("Colossal Cucumber");

            Stats = {
                Multi1 = 3;
                Damage = 8;
                Multi2 = 1.5;
            };

            Rarity = "Special";
            Order = 1;
            Icon = "rbxassetid://7243354360";
        };
        ["Cactus Colossus"] = {
            Type = "Waddle";
            Model = Pets:FindFirstChild("Cactus Colossus");

            Stats = {
                Multi1 = 11;
                Damage = 100;
                Multi2 = 2;
            };

            Rarity = "Special";
            Order = 2;
            Icon = "rbxassetid://7243354360";
        };
        ["Shogun Colossus"] = {
            Type = "Waddle";
            Model = Pets:FindFirstChild("Shogun Colossus");

            Stats = {
                Multi1 = 32;
                Damage = 1100;
                Multi2 = 4;
            };

            Rarity = "Special";
            Order = 3;
            Icon = "rbxassetid://7243354360";
        };
        ["Harvest Colossus"] = {
            Type = "Waddle";
            Model = Pets:FindFirstChild("Harvest Colossus");

            Stats = {
                Multi1 = 96;
                Damage = 13000;
                Multi2 = 11;
            };

            Rarity = "Special";
            Order = 4;
            Icon = "rbxassetid://7243354360";
        };
        ["Frozen Colossus"] = {
            Type = "Waddle";
            Model = Pets:FindFirstChild("Frozen Colossus");

            Stats = {
                Multi1 = 290;
                Damage = 150000;
                Multi2 = 30;
            };

            Rarity = "Special";
            Order = 5;
            Icon = "rbxassetid://7243354360";
        };
        ["Abyssal Colossus"] = {
            Type = "Waddle";
            Model = Pets:FindFirstChild("Abyssal Colossus");

            Stats = {
                Multi1 = 880;
                Damage = 1700000;
                Multi2 = 89;
            };

            Rarity = "Special";
            Order = 6;
            Icon = "rbxassetid://7243354360";
        };
        ["Magma Colossus"] = {
            Type = "Waddle";
            Model = Pets:FindFirstChild("Magma Colossus");

            Stats = {
                Multi1 = 2600;
                Damage = 20000000;
                Multi2 = 260;
            };

            Rarity = "Special";
            Order = 7;
            Icon = "rbxassetid://7243354360";
        };
        ["Cosmic Colossus"] = {
            Type = "Waddle";
            Model = Pets:FindFirstChild("Cosmic Colossus");

            Stats = {
                Multi1 = 8000;
                Damage = 240000000;
                Multi2 = 800;
            };

            Rarity = "Special";
            Order = 8;
            Icon = "rbxassetid://7243354360";
        };
        --.. GREGORY (2026-08-23): the SECRET. 1-in-50,000 from the BASIC egg, so every
        --.. player alive holds a lottery ticket from minute two. Hatches announce
        --.. game-wide automatically (RareHatchChat fires for any Percent <= 10). This is
        --.. deliberate content-creator bait: "I spent 10 hours hunting Gregory" videos.
        --.. Never tell players he exists. Let them find him.
        ["Gregory"] = {
            Type = "Waddle";
            Model = Pets:FindFirstChild("Gregory"); -- dedicated named clone (2026-08-23):
            -- name-based consumers (egg reveal, roster validator) need Assets.Pets.Gregory

            Stats = {
                Multi1 = 50;
                Damage = 10000;
                Multi2 = 6;
            };

            Rarity = "Mythical";
            Order = 1;
            Icon = "rbxassetid://7243354360";
        };
        ["Golden Cucumber"] = {
            Type = "Waddle";
            Model = Pets:FindFirstChild("Golden Cucumber");

            Stats = {
                Multi1 = 1200;
                Damage = 2000000;
                Multi2 = 120;
            };

            Rarity = "Special";
            Order = 1;
            Icon = "rbxassetid://7243354360";
        };
        ["Solid Gold Coin"] = {
            Type = "Waddle";
            Model = Pets:FindFirstChild("Solid Gold Coin");

            Stats = {
                Multi1 = 600;
                Damage = 800000;
                Multi2 = 61;
            };

            Rarity = "Special";
            Order = 2;
            Icon = "rbxassetid://7243354360";
        };
        ["Diamond Gherkin"] = {
            Type = "Waddle";
            Model = Pets:FindFirstChild("Diamond Gherkin");

            Stats = {
                Multi1 = 600;
                Damage = 800000;
                Multi2 = 61;
            };

            Rarity = "Special";
            Order = 3;
            Icon = "rbxassetid://7243354360";
        };
        --.. OG PICKLE (2026-08-22): launch-exclusive gift, granted once per player by
        --.. OGPetService while the launch window is open, then NEVER obtainable again.
        --.. Retired exclusives anchor the trading economy long-term. Reuses the Silver
        --.. Pickle model/icon; stats sit between Lil Pickle and the shop pets on purpose:
        --.. a real head start, not a progression skip.
        ["OG Pickle"] = {
            Type = "Waddle";
            Model = Pets:FindFirstChild("OG Pickle"); -- dedicated named clone, same reason as Gregory

            Stats = {
                Multi1 = 3;
                Damage = 8;
                Multi2 = 1.5;
            };

            Rarity = "Special";
            Order = 4;
            Icon = "rbxassetid://7243354360";
        };
        ["Silver Pickle"] = {
            Type = "Waddle";
            Model = Pets:FindFirstChild("Silver Pickle");

            Stats = {
                Multi1 = 300;
                Damage = 300000;
                Multi2 = 31;
            };

            Rarity = "Special";
            Order = 4;
            Icon = "rbxassetid://7243354360";
        };
        --.. Food Cuke Egg pets (added 2026-07-15) ..--
        ["Popcorn Cuke"] = {
            Type = "Waddle";
            Model = Pets:FindFirstChild("Popcorn Cuke");
            Stats = { Multi1 = 4; Damage = 60; Multi2 = 1.5; };
            Rarity = "Common";
            Order = 8500;
            Icon = "rbxassetid://7260983899";
        };
        ["Cotton Candy Cuke"] = {
            Type = "Waddle";
            Model = Pets:FindFirstChild("Cotton Candy Cuke");
            Stats = { Multi1 = 5; Damage = 80; Multi2 = 1.5; };
            Rarity = "Common";
            Order = 8499;
            Icon = "rbxassetid://7260983899";
        };
        ["Lollipop Cuke"] = {
            Type = "Waddle";
            Model = Pets:FindFirstChild("Lollipop Cuke");
            Stats = { Multi1 = 6.5; Damage = 110; Multi2 = 1.5; };
            Rarity = "Uncommon";
            Order = 8498;
            Icon = "rbxassetid://7260983899";
        };
        ["Fried Egg Cuke"] = {
            Type = "Waddle";
            Model = Pets:FindFirstChild("Fried Egg Cuke");
            Stats = { Multi1 = 8; Damage = 150; Multi2 = 2; };
            Rarity = "Uncommon";
            Order = 8497;
            Icon = "rbxassetid://7260983899";
        };
        ["Cupcake Cuke"] = {
            Type = "Waddle";
            Model = Pets:FindFirstChild("Cupcake Cuke");
            Stats = { Multi1 = 10; Damage = 210; Multi2 = 2; };
            Rarity = "Rare";
            Order = 8496;
            Icon = "rbxassetid://7260983899";
        };
        ["Taco Cuke"] = {
            Type = "Waddle";
            Model = Pets:FindFirstChild("Taco Cuke");
            Stats = { Multi1 = 13; Damage = 280; Multi2 = 2.5; };
            Rarity = "Rare";
            Order = 8495;
            Icon = "rbxassetid://7260983899";
        };
        ["Watermelon Cuke"] = {
            Type = "Waddle";
            Model = Pets:FindFirstChild("Watermelon Cuke");
            Stats = { Multi1 = 16; Damage = 380; Multi2 = 2.5; };
            Rarity = "Legendary";
            Order = 8494;
            Icon = "rbxassetid://7260983899";
        };
        ["Burger Cuke"] = {
            Type = "Waddle";
            Model = Pets:FindFirstChild("Burger Cuke");
            Stats = { Multi1 = 20; Damage = 500; Multi2 = 3; };
            Rarity = "Legendary";
            Order = 8493;
            Icon = "rbxassetid://7260983899";
        };
        ["Pizza Cuke"] = {
            Type = "Waddle";
            Model = Pets:FindFirstChild("Pizza Cuke");
            Stats = { Multi1 = 28; Damage = 900; Multi2 = 4; };
            Rarity = "Mythical";
            Order = 8492;
            Icon = "rbxassetid://7260983899";
        };
        ["Ice Cream Cuke"] = {
            Type = "Waddle";
            Model = Pets:FindFirstChild("Ice Cream Cuke");
            Stats = { Multi1 = 40; Damage = 3000; Multi2 = 5; };
            Rarity = "Omega";
            Order = 8491;
            Icon = "rbxassetid://7260983899";
        };
        --.. Playtime-reward exclusive pets (session ladder, not in any egg pool)
        ["Blazing Pickle"] = {
            Type = "Waddle";
            Model = Pets:FindFirstChild("Blazing Pickle");
            Stats = { Multi1 = 25; Damage = 5000; Multi2 = 3.5; };
            Rarity = "Omega";
            Order = 8490;
            Icon = "rbxassetid://7260983899";
        };
        ["King Cuke"] = {
            Type = "Waddle";
            Model = Pets:FindFirstChild("King Cuke");
            Stats = { Multi1 = 60; Damage = 25000; Multi2 = 7; };
            Rarity = "Omega";
            Order = 8489;
            Icon = "rbxassetid://7260983899";
        };
    };
}
