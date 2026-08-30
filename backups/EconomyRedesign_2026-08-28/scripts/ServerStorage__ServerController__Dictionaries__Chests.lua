--..Services..--
--.. (coins economy July 2026: chests pay Coins, flat)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

--..Modules..--


--..Variables..--
local Chests = workspace.Chests

--..Functions..--

return {

    ["Stats"] = {
        ["Treasure"] = {
            ChestModel = Chests.Treasure;
            HitBox = Chests.Treasure.PrimaryPart;
            Timer = Chests.Treasure.TimerPart.Title.Frame.Timer;

            Type = "Daily";
            IsMultiReward = false;
            WaitTime = 43200; --.. 12 Hours

            Currency = {
                ["Coins"] = 1500;
            };
        };
        ["Volcano"] = {
            ChestModel = Chests.Volcano;
            HitBox = Chests.Volcano.PrimaryPart;
            Timer = Chests.Volcano.TimerPart.Title.Frame.Timer;

            Type = "Daily";
            IsMultiReward = false;
            WaitTime = 43200; --.. 12 Hours

            Currency = {
                ["Coins"] = 15000;
            };
        };
        ["Samurai"] = {
            ChestModel = Chests.Samurai;
            HitBox = Chests.Samurai.PrimaryPart;
            Timer = Chests.Samurai.TimerPart.Title.Frame.Timer;

            Type = "Daily";
            IsMultiReward = false;
            WaitTime = 43200; --.. 12 Hours

            Currency = {
                ["Coins"] = 4000;
            };
        };
        ["Snow"] = {
            ChestModel = Chests.Snow;
            HitBox = Chests.Snow.PrimaryPart;
            Timer = Chests.Snow.TimerPart.Title.Frame.Timer;

            Type = "Daily";
            IsMultiReward = false;
            WaitTime = 43200; --.. 12 Hours

            Currency = {
                ["Coins"] = 10000;
            };
        };
        ["Group"] = {
            ChestModel = Chests.Group;
            HitBox = Chests.Group.PrimaryPart;
            Timer = Chests.Group.TimerPart.Title.Frame.Timer;

            Type = "Group";
            IsMultiReward = false;
            WaitTime = 43200; --.. 12 Hours

            Currency = {
                ["Coins"] = 1000;
            };
        };
        ["Daily"] = {
            ChestModel = Chests.Daily;
            HitBox = Chests.Daily.PrimaryPart;
            Timer = Chests.Daily.TimerPart.Title.Frame.Timer;

            Type = "Daily";
            IsMultiReward = false;
            WaitTime = 43200; --.. 12 Hours

            Currency = {
                ["Coins"] = 500;
            };
        };
    };
}
