--..Services..--
--.. (2026-08-28 ECONOMY REDESIGN: new price ladder + Orb/Multi zone-value ladder (Orb*Multi = 8^tier).
--.. (all biome doors use Coins. Prices remain centralized here
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
                Orb = 1;
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
                Price = 60000;
                -- tutorial completer leaving with 600-2,200 cucumbers and zero doors -- the
                -- first door sat outside session one entirely, and session length correlates
                -- 1:1 with doors owned. 4k lands the first unlock inside the first session.
                Currency = "Coins";
            };

            Orbs = {
                Multi = 2;
                Orb = 4;
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
                Price = 5000000;
                -- 85k recreated the exact 21x cliff the first cut killed. 4k -> 30k -> rebirth
                -- (100k) -> Farm keeps every early goal within a session of the previous one.
                Currency = "Coins";
            };

            Orbs = {
                Multi = 4;
                Orb = 16;
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
                Price = 300000000;
                Currency = "Coins";
                MinRebirths = 1;
            };

            Orbs = {
                Multi = 8;
                Orb = 64;
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
                Price = 60000000000;
                Currency = "Coins";
                MinRebirths = 2;
            };

            Orbs = {
                Multi = 16;
                Orb = 256;
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
                Price = 5000000000000;
                Currency = "Coins";
                MinRebirths = 3;
            };

            Orbs = {
                Multi = 32;
                Orb = 1024;
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
                Price = 400000000000000;
                Currency = "Coins";
                MinRebirths = 4;
            };

            Orbs = {
                Multi = 64;
                Orb = 4096;
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
                Price = 25000000000000000;
                Currency = "Coins";
                MinRebirths = 5;
            };

            Orbs = {
                Multi = 128;
                Orb = 16384;
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
