local playerGui=script.Parent.Parent
local hud=playerGui:WaitForChild("CucumberHUDDesign")
local menus=require(script.Parent.MenuController).Start(script.Parent,hud)
local index=require(script.Parent.IndexController).Start(script.Parent,menus)
local shop=require(script.Parent.ShopController).Start(script.Parent,menus)
-- 2026-09-22: the Pets menu starts last and guarded (require errors included), so it can never break Shop / Index
local okPets,pets=pcall(function() return require(script.Parent.PetController).Start(script.Parent,menus) end)
if not okPets then warn("[MenuClient] Pets menu unavailable: "..tostring(pets)) pets=nil end
-- 2026-09-23: the Manage panel, guarded the same way
local okManage,manage=pcall(function() return require(script.Parent.ManageController).Start(script.Parent,menus) end)
if not okManage then warn("[MenuClient] Manage menu unavailable: "..tostring(manage)) manage=nil end
script.Destroying:Connect(function() if manage then manage.Destroy() end;if pets then pets.Destroy() end;shop.Destroy();index.Destroy();menus.Destroy() end)
