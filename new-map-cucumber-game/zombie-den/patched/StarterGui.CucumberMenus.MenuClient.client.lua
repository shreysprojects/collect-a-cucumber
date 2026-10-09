local playerGui=script.Parent.Parent
local hud=playerGui:WaitForChild("CucumberHUDDesign")
local menus=require(script.Parent.MenuController).Start(script.Parent,hud)
local index=require(script.Parent.IndexController).Start(script.Parent,menus)
local shop=require(script.Parent.ShopController).Start(script.Parent,menus)
-- 2026-09-23: the Pets menu is gone (reserve pets live in the hotbar); the Manage panel starts guarded
local okManage,manage=pcall(function() return require(script.Parent.ManageController).Start(script.Parent,menus) end)
if not okManage then warn("[MenuClient] Manage menu unavailable: "..tostring(manage)) manage=nil end
-- 2026-09-23: the lobby ITEM SHOP (BuyShopPanel, opened by the potion cart's prompt) starts guarded too
local okItemShop,itemShop=pcall(function() return require(script.Parent.ItemShopController).Start(script.Parent,menus) end)
if not okItemShop then warn("[MenuClient] Item shop unavailable: "..tostring(itemShop)) itemShop=nil end
-- 2026-09-24: the ZOMBIE DEN panel (DenPanel, opened by walking up to the den), guarded the same way
local okDen,den=pcall(function() return require(script.Parent.DenController).Start(script.Parent,menus) end)
if not okDen then warn("[MenuClient] Zombie Den unavailable: "..tostring(den)) den=nil end
script.Destroying:Connect(function() if den then den.Destroy() end;if itemShop then itemShop.Destroy() end;if manage then manage.Destroy() end;shop.Destroy();index.Destroy();menus.Destroy() end)
