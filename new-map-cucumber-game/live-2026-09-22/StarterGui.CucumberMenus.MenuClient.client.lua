local playerGui=script.Parent.Parent
local hud=playerGui:WaitForChild("CucumberHUDDesign")
local menus=require(script.Parent.MenuController).Start(script.Parent,hud)
local index=require(script.Parent.IndexController).Start(script.Parent,menus)
local shop=require(script.Parent.ShopController).Start(script.Parent,menus)
script.Destroying:Connect(function() shop.Destroy();index.Destroy();menus.Destroy() end)
