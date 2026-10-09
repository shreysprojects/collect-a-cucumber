local playerGui=script.Parent.Parent
local hud=playerGui:WaitForChild("CucumberHUDDesign")
local menus=require(script.Parent.MenuController).Start(script.Parent,hud)
local index=require(script.Parent.IndexController).Start(script.Parent,menus)
local shop=require(script.Parent.ShopController).Start(script.Parent,menus)
-- 2026-09-22: the Pets menu starts last and guarded (require errors included), so it can never break Shop / Index
local okPets,pets=pcall(function() return require(script.Parent.PetController).Start(script.Parent,menus) end)
if not okPets then warn("[MenuClient] Pets menu unavailable: "..tostring(pets)) pets=nil end
script.Destroying:Connect(function() if pets then pets.Destroy() end;shop.Destroy();index.Destroy();menus.Destroy() end)
