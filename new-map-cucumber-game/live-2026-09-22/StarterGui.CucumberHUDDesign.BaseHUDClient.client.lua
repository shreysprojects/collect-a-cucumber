local controller=require(script.Parent.BaseHUDController).Start(script.Parent)
script.Destroying:Connect(controller.Destroy)