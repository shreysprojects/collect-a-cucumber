local playerGui=script.Parent.Parent
local hud=playerGui:WaitForChild("CucumberHUDDesign")
local menus=require(script.Parent.MenuController).Start(script.Parent,hud)
local index=require(script.Parent.IndexController).Start(script.Parent,menus)
local shop=require(script.Parent.ShopController).Start(script.Parent,menus)
-- 2026-09-23: the Pets menu is gone (reserve pets live in the hotbar); the Manage panel starts guarded
local okManage,manage=pcall(function() return require(script.Parent.ManageController).Start(script.Parent,menus) end)
if not okManage then warn("[MenuClient] Manage menu unavailable: "..tostring(manage)) manage=nil end
script.Destroying:Connect(function() if manage then manage.Destroy() end;shop.Destroy();index.Destroy();menus.Destroy() end)
