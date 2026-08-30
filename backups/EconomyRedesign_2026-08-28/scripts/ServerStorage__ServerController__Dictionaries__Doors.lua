--..Services..--
--.. (August 2026: all biome doors use Coins. Prices remain centralized here
--.. so the client prompt and server deduction always agree.)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

--..Modules..--


--..Variables..--
local Doors = workspace.Doors

--..Functions..--

return {

    ["Stats"] = {
        ["Spawn"] = {
            Index = "Spawn";
            Name = "Spawn";

            Stats = {
                Price = 0;
                Currency = "Coins";
            };

            Orbs = {
                Multi = 1;
                Orb = 1; -- was 1.5: trimmed 2026-08-22 so the first minute pays ~1/3 less;
                -- Spawn-only lever, later biomes keep their values
            };

            ClientSided = {
                Order = 1;

                Color = Color3.fromRGB(17,255,0);
                HoverGradient = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, Color3.fromRGB(17,255,0)),
                    ColorSequenceKeypoint.new(0.552, Color3.fromRGB(181, 255, 176)),
                    ColorSequenceKeypoint.new(1, Color3.fromRGB(17,255,0))
                });
            };

            Door = nil;
        };

        ["Desert"] = {
            Index = "Desert";
            Name = "The Wild West";

            Stats = {
                Price = 4000; -- was 10000 (2026-08-22): real ad-cohort saves showed EVERY
                -- tutorial completer leaving with 600-2,200 cucumbers and zero doors -- the
                -- first door sat outside session one entirely, and session length correlates
                -- 1:1 with doors owned. 4k lands the first unlock inside the first session.
                Currency = "Coins";
            };

            Orbs = {
                Multi = 1.5;
                Orb = 2;
            };

            ClientSided = {
                Order = 2;

                Color = Color3.fromRGB(246,194,135);
                HoverGradient = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, Color3.fromRGB(246,194,135)),
                    ColorSequenceKeypoint.new(0.552, Color3.fromRGB(255, 242, 225)),
                    ColorSequenceKeypoint.new(1, Color3.fromRGB(246,194,135))
                });
            };

            Door = Doors["Desert"];
        };

        ["Samurai"] = {
            Index = "Samurai";
            Name = "Samurai Palace";

            Stats = {
                Price = 30000; -- was 175000, then 85000 (2026-08-22): with Desert now 4k,
                -- 85k recreated the exact 21x cliff the first cut killed. 4k -> 30k -> rebirth
                -- (100k) -> Farm keeps every early goal within a session of the previous one.
                Currency = "Coins";
            };

            Orbs = {
                Multi = 2;
                Orb = 2.5;
            };

            ClientSided = {
                Order = 3;

                Color = Color3.fromRGB(230, 113, 255);
                HoverGradient = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, Color3.fromRGB(254, 171, 255)),
                    ColorSequenceKeypoint.new(0.552, Color3.fromRGB(254, 211, 232)),
                    ColorSequenceKeypoint.new(1, Color3.fromRGB(254, 171, 255))
                });
            };

            Door = Doors["Samurai"];
        };

        ["Farm"] = {
            Index = "Farm";
            Name = "The Farm";

            Stats = {
                Price = 1000000;
                Currency = "Coins";
                MinRebirths = 1;
            };

            Orbs = {
                Multi = 2.5;
                Orb = 3;
            };

            ClientSided = {
                Order = 4;

                Color = Color3.fromRGB(255, 208, 88);
                HoverGradient = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 208, 88)),
                    ColorSequenceKeypoint.new(0.552, Color3.fromRGB(255, 242, 175)),
                    ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 208, 88))
                });
            };

            Door = Doors["Farm"];
        };

        ["Snow"] = {
            Index = "Snow";
            Name = "The Arctic";

            Stats = {
                Price = 7500000;
                Currency = "Coins";
                MinRebirths = 2;
            };

            Orbs = {
                Multi = 3;
                Orb = 3.5;
            };

            ClientSided = {
                Order = 5;

                Color = Color3.fromRGB(180, 214, 255);
                HoverGradient = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, Color3.fromRGB(180, 214, 255)),
                    ColorSequenceKeypoint.new(0.552, Color3.fromRGB(216, 244, 255)),
                    ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 214, 255))
                });
            };

            Door = Doors["Snow"];
        };

        ["Underwater"] = {
            Index = "Underwater";
            Name = "The Ocean";

            Stats = {
                Price = 45000000;
                Currency = "Coins";
                MinRebirths = 3;
            };

            Orbs = {
                Multi = 4;
                Orb = 5;
            };

            ClientSided = {
                Order = 6;

                Color = Color3.fromRGB(85, 177, 255);
                HoverGradient = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, Color3.fromRGB(85, 177, 255)),
                    ColorSequenceKeypoint.new(0.552, Color3.fromRGB(195, 228, 255)),
                    ColorSequenceKeypoint.new(1, Color3.fromRGB(85, 177, 255))
                });
            };

            Door = Doors["Underwater"];

        };

        ["Volcano"] = {
            Index = "Volcano";
            Name = "The Volcano";

            Stats = {
                Price = 250000000;
                Currency = "Coins";
                MinRebirths = 4;
            };

            Orbs = {
                Multi = 5;
                Orb = 6;
            };

            ClientSided = {
                Order = 7;

                Color = Color3.fromRGB(253, 128, 8);
                HoverGradient = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, Color3.fromRGB(254, 184, 55)),
                    ColorSequenceKeypoint.new(0.552, Color3.fromRGB(255, 241, 178)),
                    ColorSequenceKeypoint.new(1, Color3.fromRGB(254, 184, 55))
                });
            };

            Door = Doors["Volcano"];

        };

        ["Narmek"] = {
            Index = "Narmek";
            Name = "The Greenland";

            Stats = {
                Price = 1500000000;
                Currency = "Coins";
                MinRebirths = 5;
            };

            Orbs = {
                Multi = 6;
                Orb = 7;
            };

            ClientSided = {
                Order = 8;

                Color = Color3.fromRGB(85, 177, 255);
                HoverGradient = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, Color3.fromRGB(85, 177, 255)),
                    ColorSequenceKeypoint.new(0.552, Color3.fromRGB(195, 228, 255)),
                    ColorSequenceKeypoint.new(1, Color3.fromRGB(85, 177, 255))
                });
            };

            Door = Doors["Narmek"];
        };
    };
}
