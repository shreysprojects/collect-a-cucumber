--..Services..--
--.. (stats rebalanced July 2026: Multi1/Multi2 1-8.2 bands + explicit per-pet Damage)
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
                Damage = 2;
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
                Multi1 = 1;
                Damage = 3;
                Multi2 = 1.1;
            };

            Rarity = "Uncommon";
            Order = 9998;
            Icon = "rbxassetid://7259997908";
        };
        ["Wolf"] = {
            Type = "Waddle";
            Model = Pets:FindFirstChild("Wolf");

            Stats = {
                Multi1 = 1;
                Damage = 3;
                Multi2 = 1.1;
            };

            Rarity = "Rare";
            Order = 9997;
            Icon = "rbxassetid://7259997627";
        };
        ["Tabby"] = {
            Type = "Waddle";
            Model = Pets:FindFirstChild("Tabby");

            Stats = {
                Multi1 = 1.1;
                Damage = 4;
                Multi2 = 1.2;
            };

            Rarity = "Rare";
            Order = 9996;
            Icon = "rbxassetid://7260983657";
        };
        ["Fox"] = {
            Type = "Waddle";
            Model = Pets:FindFirstChild("Fox");

            Stats = {
                Multi1 = 1.3;
                Damage = 5;
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
                Multi1 = 1.6;
                Damage = 4;
                Multi2 = 1.7;
            };

            Rarity = "Common";
            Order = 9994;
            Icon = "rbxassetid://7260983899";
        };
        ["Treasure Gem"] = {
            Type = "Waddle";
            Model = Pets["Treasure Gem"];

            Stats = {
                Multi1 = 1.6;
                Damage = 5;
                Multi2 = 1.7;
            };

            Rarity = "Common";
            Order = 9993;
            Icon = "rbxassetid://7260983899";
        };
        ["Cannon"] = {
            Type = "Waddle";
            Model = Pets["Cannon"];

            Stats = {
                Multi1 = 1.7;
                Damage = 5;
                Multi2 = 1.7;
            };

            Rarity = "Common";
            Order = 9992;
            Icon = "rbxassetid://7260983899";
        };
        ["Chest"] = {
            Type = "Waddle";
            Model = Pets.Chest;

            Stats = {
                Multi1 = 1.7;
                Damage = 6;
                Multi2 = 1.8;
            };

            Rarity = "Uncommon";
            Order = 9991;
            Icon = "rbxassetid://7260983899";
        };
        ["Desert Overlord"] = {
            Type = "Waddle";
            Model = Pets["Desert Overlord"];

            Stats = {
                Multi1 = 1.8;
                Damage = 7;
                Multi2 = 1.9;
            };

            Rarity = "Rare";
            Order = 9990;
            Icon = "rbxassetid://7260983899";
        };
        ["Cactus"] = {
            Type = "Flying";
            Model = Pets:FindFirstChild("Cactus");

            Stats = {
                Multi1 = 2.1;
                Damage = 10;
                Multi2 = 2.1;
            };

            Rarity = "Legendary";
            Order = 9989;
            Icon = "rbxassetid://7243354360";
        };

        ["Dog Ninja"] = {
            Type = "Waddle";
            Model = Pets["Dog Ninja"];

            Stats = {
                Multi1 = 2.3;
                Damage = 8;
                Multi2 = 2.4;
            };

            Rarity = "Common";
            Order = 9988;
            Icon = "rbxassetid://7260983899";
        };
        ["Good Ninja"] = {
            Type = "Waddle";
            Model = Pets["Good Ninja"];

            Stats = {
                Multi1 = 2.4;
                Damage = 9;
                Multi2 = 2.5;
            };

            Rarity = "Uncommon";
            Order = 9987;
            Icon = "rbxassetid://7260983899";
        };
        ["Evil Ninja"] = {
            Type = "Waddle";
            Model = Pets["Evil Ninja"];

            Stats = {
                Multi1 = 2.4;
                Damage = 10;
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
                Multi1 = 2.5;
                Damage = 12;
                Multi2 = 2.5;
            };

            Rarity = "Rare";
            Order = 9985;
            Icon = "rbxassetid://7260983899";
        };
        ["Evil Samurai"] = {
            Type = "Waddle";
            Model = Pets["Evil Samurai"];

            Stats = {
                Multi1 = 2.5;
                Damage = 14;
                Multi2 = 2.6;
            };

            Rarity = "Rare";
            Order = 9984;
            Icon = "rbxassetid://7260983899";
        };
        ["Sensei"] = {
            Type = "Waddle";
            Model = Pets["Sensei"];

            Stats = {
                Multi1 = 2.7;
                Damage = 20;
                Multi2 = 2.8;
            };

            Rarity = "Legendary";
            Order = 9983;
            Icon = "rbxassetid://7260983899";
        };

        ["Hay"] = {
            Type = "Waddle";
            Model = Pets["Hay"];

            Stats = {
                Multi1 = 3;
                Damage = 16;
                Multi2 = 3;
            };

            Rarity = "Common";
            Order = 9982;
            Icon = "rbxassetid://7260983899";
        };
        ["Bird"] = {
            Type = "Waddle";
            Model = Pets["Bird"];

            Stats = {
                Multi1 = 3;
                Damage = 18;
                Multi2 = 3.1;
            };

            Rarity = "Common";
            Order = 9981;
            Icon = "rbxassetid://7260983899";
        };
        ["Panda"] = {
            Type = "Waddle";
            Model = Pets["Panda"];

            Stats = {
                Multi1 = 3;
                Damage = 21;
                Multi2 = 3.1;
            };

            Rarity = "Uncommon";
            Order = 9980;
            Icon = "rbxassetid://7260983899";
        };
        ["Cow"] = {
            Type = "Waddle";
            Model = Pets["Cow"];

            Stats = {
                Multi1 = 3.1;
                Damage = 24;
                Multi2 = 3.1;
            };

            Rarity = "Uncommon";
            Order = 9979;
            Icon = "rbxassetid://7260983899";
        };
        ["Pig"] = {
            Type = "Waddle";
            Model = Pets["Pig"];

            Stats = {
                Multi1 = 3.1;
                Damage = 28;
                Multi2 = 3.2;
            };

            Rarity = "Rare";
            Order = 9978;
            Icon = "rbxassetid://7260983899";
        };
        ["Farmer"] = {
            Type = "Waddle";
            Model = Pets["Farmer"];

            Stats = {
                Multi1 = 3.4;
                Damage = 40;
                Multi2 = 3.6;
            };

            Rarity = "Legendary";
            Order = 9977;
            Icon = "rbxassetid://7260983899";
        };

        ["Red Snowman"] = {
            Type = "Waddle";
            Model = Pets["Red Snowman"];

            Stats = {
                Multi1 = 3.7;
                Damage = 32;
                Multi2 = 3.8;
            };

            Rarity = "Common";
            Order = 9976;
            Icon = "rbxassetid://7260983899";
        };
        ["Blue Snowman"] = {
            Type = "Waddle";
            Model = Pets["Blue Snowman"];

            Stats = {
                Multi1 = 3.7;
                Damage = 37;
                Multi2 = 3.8;
            };

            Rarity = "Common";
            Order = 9975;
            Icon = "rbxassetid://7260983899";
        };
        ["Frozen Dragon"] = {
            Type = "Waddle";
            Model = Pets["Frozen Dragon"];

            Stats = {
                Multi1 = 3.8;
                Damage = 42;
                Multi2 = 3.8;
            };

            Rarity = "Uncommon";
            Order = 9974;
            Icon = "rbxassetid://7260983899";
        };
        ["Frozen Hydra"] = {
            Type = "Waddle";
            Model = Pets["Frozen Hydra"];

            Stats = {
                Multi1 = 3.8;
                Damage = 48;
                Multi2 = 3.9;
            };

            Rarity = "Uncommon";
            Order = 9973;
            Icon = "rbxassetid://7260983899";
        };
        ["Frozen Ice Shock"] = {
            Type = "Waddle";
            Model = Pets["Frozen Ice Shock"];

            Stats = {
                Multi1 = 3.9;
                Damage = 56;
                Multi2 = 3.9;
            };

            Rarity = "Rare";
            Order = 9972;
            Icon = "rbxassetid://7260983899";
        };
        ["Frozen Gem"] = {
            Type = "Waddle";
            Model = Pets["Frozen Gem"];

            Stats = {
                Multi1 = 4.2;
                Damage = 80;
                Multi2 = 4.3;
            };

            Rarity = "Legendary";
            Order = 9971;
            Icon = "rbxassetid://7260983899";
        };

        ["Oceanic Dog"] = {
            Type = "Waddle";
            Model = Pets["Oceanic Dog"];

            Stats = {
                Multi1 = 4.4;
                Damage = 64;
                Multi2 = 4.5;
            };

            Rarity = "Common";
            Order = 9970;
            Icon = "rbxassetid://7260983899";
        };
        ["Oceanic Kitty"] = {
            Type = "Waddle";
            Model = Pets["Oceanic Kitty"];

            Stats = {
                Multi1 = 4.5;
                Damage = 74;
                Multi2 = 4.6;
            };

            Rarity = "Common";
            Order = 9969;
            Icon = "rbxassetid://7260983899";
        };
        ["Oceanic Bunny"] = {
            Type = "Waddle";
            Model = Pets["Oceanic Bunny"];

            Stats = {
                Multi1 = 4.5;
                Damage = 83;
                Multi2 = 4.6;
            };

            Rarity = "Uncommon";
            Order = 9968;
            Icon = "rbxassetid://7260983899";
        };
        ["Oceanic Bear"] = {
            Type = "Waddle";
            Model = Pets["Oceanic Bear"];

            Stats = {
                Multi1 = 4.6;
                Damage = 96;
                Multi2 = 4.6;
            };

            Rarity = "Uncommon";
            Order = 9967;
            Icon = "rbxassetid://7260983899";
        };
        ["Ocean Dragon"] = {
            Type = "Waddle";
            Model = Pets["Ocean Dragon"];

            Stats = {
                Multi1 = 4.6;
                Damage = 112;
                Multi2 = 4.7;
            };

            Rarity = "Rare";
            Order = 9966;
            Icon = "rbxassetid://7260983899";
        };
        ["Atlantic Hydra"] = {
            Type = "Waddle";
            Model = Pets["Atlantic Hydra"];

            Stats = {
                Multi1 = 4.9;
                Damage = 160;
                Multi2 = 5.1;
            };

            Rarity = "Legendary";
            Order = 9965;
            Icon = "rbxassetid://7260983899";
        };

        ["Lava Plume"] = {
            Type = "Waddle";
            Model = Pets["Lava Plume"];

            Stats = {
                Multi1 = 5.2;
                Damage = 128;
                Multi2 = 5.3;
            };

            Rarity = "Common";
            Order = 9964;
            Icon = "rbxassetid://7260983899";
        };
        ["Lava Golem"] = {
            Type = "Waddle";
            Model = Pets["Lava Golem"];

            Stats = {
                Multi1 = 5.2;
                Damage = 147;
                Multi2 = 5.3;
            };

            Rarity = "Common";
            Order = 9963;
            Icon = "rbxassetid://7260983899";
        };
        ["Lava Veltal"] = {
            Type = "Waddle";
            Model = Pets["Lava Veltal"];

            Stats = {
                Multi1 = 5.3;
                Damage = 166;
                Multi2 = 5.3;
            };

            Rarity = "Uncommon";
            Order = 9962;
            Icon = "rbxassetid://7260983899";
        };
        ["Lava Trio"] = {
            Type = "Waddle";
            Model = Pets["Lava Trio"];

            Stats = {
                Multi1 = 5.3;
                Damage = 192;
                Multi2 = 5.4;
            };

            Rarity = "Rare";
            Order = 9961;
            Icon = "rbxassetid://7260983899";
        };
        ["Lava Dragon"] = {
            Type = "Waddle";
            Model = Pets["Lava Dragon"];

            Stats = {
                Multi1 = 5.4;
                Damage = 224;
                Multi2 = 5.4;
            };

            Rarity = "Rare";
            Order = 9960;
            Icon = "rbxassetid://7260983899";
        };
        ["Demon Dog"] = {
            Type = "Waddle";
            Model = Pets["Demon Dog"];

            Stats = {
                Multi1 = 5.6;
                Damage = 320;
                Multi2 = 5.8;
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
				Multi1 = 5.9;
				Damage = 150;
				Multi2 = 6.0;
			};

			Rarity = "Common";
			Order = 9957;
			Icon = "rbxassetid://7260983899";
		};
		["Satellite Pup"] = {
			Type = "Waddle";
			Model = Pets["Satellite Pup"];

			Stats = {
				Multi1 = 5.9;
				Damage = 172;
				Multi2 = 6.0;
			};

			Rarity = "Common";
			Order = 9956;
			Icon = "rbxassetid://7260983899";
		};
		["Alien Slime"] = {
			Type = "Waddle";
			Model = Pets["Alien Slime"];

			Stats = {
				Multi1 = 6.0;
				Damage = 195;
				Multi2 = 6.1;
			};

			Rarity = "Uncommon";
			Order = 9955;
			Icon = "rbxassetid://7260983899";
		};
		["Meteor Moth"] = {
			Type = "Waddle";
			Model = Pets["Meteor Moth"];

			Stats = {
				Multi1 = 6.1;
				Damage = 225;
				Multi2 = 6.2;
			};

			Rarity = "Rare";
			Order = 9954;
			Icon = "rbxassetid://7260983899";
		};
		["Nebula Fox"] = {
			Type = "Waddle";
			Model = Pets["Nebula Fox"];

			Stats = {
				Multi1 = 6.3;
				Damage = 262;
				Multi2 = 6.4;
			};

			Rarity = "Legendary";
			Order = 9953;
			Icon = "rbxassetid://7260983899";
		};
		["Cosmo Cat"] = {
			Type = "Waddle";
			Model = Pets["Cosmo Cat"];

			Stats = {
				Multi1 = 6.6;
				Damage = 375;
				Multi2 = 6.8;
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
                Multi1 = 25;
                Damage = 500;
                Multi2 = 25;
            };

            Rarity = "Omega";
            Order = 9510;
            Icon = "rbxassetid://7243354360";
        };

        ["Purple Hydra"] = {
            Type = "Flying";
            Model = Pets:FindFirstChild("Purple Hydra");

            Stats = {
                Multi1 = 30;
                Damage = 500;
                Multi2 = 30;
            };

            Rarity = "Omega";
            Order = 9509;
            Icon = "rbxassetid://7243354697";
        };
        ["Heavenly Angel"] = {
            Type = "Flying";
            Model = Pets['Heavenly Angel'];

            Stats = {
                Multi1 = 30;
                Damage = 500;
                Multi2 = 30;
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
                Multi1 = 1;
                Damage = 2;
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
                Multi1 = 6;
                Damage = 125;
                Multi2 = 6;
            };

            Rarity = "Special";
            Order = 1;
            Icon = "rbxassetid://7243354360";
        };
        ["Cactus Colossus"] = {
            Type = "Waddle";
            Model = Pets:FindFirstChild("Cactus Colossus");

            Stats = {
                Multi1 = 8;
                Damage = 145;
                Multi2 = 8;
            };

            Rarity = "Special";
            Order = 2;
            Icon = "rbxassetid://7243354360";
        };
        ["Shogun Colossus"] = {
            Type = "Waddle";
            Model = Pets:FindFirstChild("Shogun Colossus");

            Stats = {
                Multi1 = 10;
                Damage = 165;
                Multi2 = 10;
            };

            Rarity = "Special";
            Order = 3;
            Icon = "rbxassetid://7243354360";
        };
        ["Harvest Colossus"] = {
            Type = "Waddle";
            Model = Pets:FindFirstChild("Harvest Colossus");

            Stats = {
                Multi1 = 12;
                Damage = 185;
                Multi2 = 12;
            };

            Rarity = "Special";
            Order = 4;
            Icon = "rbxassetid://7243354360";
        };
        ["Frozen Colossus"] = {
            Type = "Waddle";
            Model = Pets:FindFirstChild("Frozen Colossus");

            Stats = {
                Multi1 = 14;
                Damage = 200;
                Multi2 = 14;
            };

            Rarity = "Special";
            Order = 5;
            Icon = "rbxassetid://7243354360";
        };
        ["Abyssal Colossus"] = {
            Type = "Waddle";
            Model = Pets:FindFirstChild("Abyssal Colossus");

            Stats = {
                Multi1 = 17;
                Damage = 215;
                Multi2 = 17;
            };

            Rarity = "Special";
            Order = 6;
            Icon = "rbxassetid://7243354360";
        };
        ["Magma Colossus"] = {
            Type = "Waddle";
            Model = Pets:FindFirstChild("Magma Colossus");

            Stats = {
                Multi1 = 20;
                Damage = 230;
                Multi2 = 20;
            };

            Rarity = "Special";
            Order = 7;
            Icon = "rbxassetid://7243354360";
        };
        ["Cosmic Colossus"] = {
            Type = "Waddle";
            Model = Pets:FindFirstChild("Cosmic Colossus");

            Stats = {
                Multi1 = 24;
                Damage = 245;
                Multi2 = 24;
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
                Multi1 = 12;
                Damage = 500;
                Multi2 = 12;
            };

            Rarity = "Mythical";
            Order = 1;
            Icon = "rbxassetid://7243354360";
        };
        ["Golden Cucumber"] = {
            Type = "Waddle";
            Model = Pets:FindFirstChild("Golden Cucumber");

            Stats = {
                Multi1 = 8.2;
                Damage = 400;
                Multi2 = 8.2;
            };

            Rarity = "Special";
            Order = 1;
            Icon = "rbxassetid://7243354360";
        };
        ["Solid Gold Coin"] = {
            Type = "Waddle";
            Model = Pets:FindFirstChild("Solid Gold Coin");

            Stats = {
                Multi1 = 4.4;
                Damage = 120;
                Multi2 = 4.4;
            };

            Rarity = "Special";
            Order = 2;
            Icon = "rbxassetid://7243354360";
        };
        ["Diamond Gherkin"] = {
            Type = "Waddle";
            Model = Pets:FindFirstChild("Diamond Gherkin");

            Stats = {
                Multi1 = 4.4;
                Damage = 120;
                Multi2 = 4.4;
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
                Multi1 = 1.5;
                Damage = 5;
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
                Multi1 = 2.2;
                Damage = 16;
                Multi2 = 2.2;
            };

            Rarity = "Special";
            Order = 4;
            Icon = "rbxassetid://7243354360";
        };
        --.. Food Cuke Egg pets (added 2026-07-15) ..--
        ["Popcorn Cuke"] = {
            Type = "Waddle";
            Model = Pets:FindFirstChild("Popcorn Cuke");
            Stats = { Multi1 = 1.2; Damage = 5; Multi2 = 1.2; };
            Rarity = "Common";
            Order = 8500;
            Icon = "rbxassetid://7260983899";
        };
        ["Cotton Candy Cuke"] = {
            Type = "Waddle";
            Model = Pets:FindFirstChild("Cotton Candy Cuke");
            Stats = { Multi1 = 1.4; Damage = 7; Multi2 = 1.4; };
            Rarity = "Common";
            Order = 8499;
            Icon = "rbxassetid://7260983899";
        };
        ["Lollipop Cuke"] = {
            Type = "Waddle";
            Model = Pets:FindFirstChild("Lollipop Cuke");
            Stats = { Multi1 = 1.8; Damage = 10; Multi2 = 1.8; };
            Rarity = "Uncommon";
            Order = 8498;
            Icon = "rbxassetid://7260983899";
        };
        ["Fried Egg Cuke"] = {
            Type = "Waddle";
            Model = Pets:FindFirstChild("Fried Egg Cuke");
            Stats = { Multi1 = 2.2; Damage = 14; Multi2 = 2.2; };
            Rarity = "Uncommon";
            Order = 8497;
            Icon = "rbxassetid://7260983899";
        };
        ["Cupcake Cuke"] = {
            Type = "Waddle";
            Model = Pets:FindFirstChild("Cupcake Cuke");
            Stats = { Multi1 = 2.8; Damage = 20; Multi2 = 2.8; };
            Rarity = "Rare";
            Order = 8496;
            Icon = "rbxassetid://7260983899";
        };
        ["Taco Cuke"] = {
            Type = "Waddle";
            Model = Pets:FindFirstChild("Taco Cuke");
            Stats = { Multi1 = 3.3; Damage = 26; Multi2 = 3.3; };
            Rarity = "Rare";
            Order = 8495;
            Icon = "rbxassetid://7260983899";
        };
        ["Watermelon Cuke"] = {
            Type = "Waddle";
            Model = Pets:FindFirstChild("Watermelon Cuke");
            Stats = { Multi1 = 4.0; Damage = 33; Multi2 = 4.0; };
            Rarity = "Legendary";
            Order = 8494;
            Icon = "rbxassetid://7260983899";
        };
        ["Burger Cuke"] = {
            Type = "Waddle";
            Model = Pets:FindFirstChild("Burger Cuke");
            Stats = { Multi1 = 4.6; Damage = 40; Multi2 = 4.6; };
            Rarity = "Legendary";
            Order = 8493;
            Icon = "rbxassetid://7260983899";
        };
        ["Pizza Cuke"] = {
            Type = "Waddle";
            Model = Pets:FindFirstChild("Pizza Cuke");
            Stats = { Multi1 = 5.3; Damage = 46; Multi2 = 5.3; };
            Rarity = "Mythical";
            Order = 8492;
            Icon = "rbxassetid://7260983899";
        };
        ["Ice Cream Cuke"] = {
            Type = "Waddle";
            Model = Pets:FindFirstChild("Ice Cream Cuke");
            Stats = { Multi1 = 6.0; Damage = 50; Multi2 = 6.0; };
            Rarity = "Omega";
            Order = 8491;
            Icon = "rbxassetid://7260983899";
        };
        --.. Playtime-reward exclusive pets (session ladder, not in any egg pool)
        ["Blazing Pickle"] = {
            Type = "Waddle";
            Model = Pets:FindFirstChild("Blazing Pickle");
            Stats = { Multi1 = 8; Damage = 100; Multi2 = 8; };
            Rarity = "Omega";
            Order = 8490;
            Icon = "rbxassetid://7260983899";
        };
        ["King Cuke"] = {
            Type = "Waddle";
            Model = Pets:FindFirstChild("King Cuke");
            Stats = { Multi1 = 15; Damage = 300; Multi2 = 15; };
            Rarity = "Omega";
            Order = 8489;
            Icon = "rbxassetid://7260983899";
        };
    };
}
