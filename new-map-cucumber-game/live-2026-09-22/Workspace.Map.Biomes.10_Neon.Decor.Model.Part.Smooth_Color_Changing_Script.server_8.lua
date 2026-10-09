r = 255
g = 0
b = 0

while true do
	wait(0.005)
	
    while (r == 255 and g ~= 255) do
	wait(0.005)
	g = g + 1
	script.Parent.Color = Color3.fromRGB(r,g,b)
	end
	wait(0.005)
	r = r - 1
	script.Parent.Color = Color3.fromRGB(r,g,b)
	while (r ~= 0) do
	wait(0.005)
	r = r - 1
	script.Parent.Color = Color3.fromRGB(r,g,b)
	end

    while (g == 255 and b ~= 255) do
	wait(0.005)
	b = b + 1
	script.Parent.Color = Color3.fromRGB(r,g,b)
	end
	wait(0.005)
	g = g - 1
	script.Parent.Color = Color3.fromRGB(r,g,b)
	while (g ~= 0) do
	wait(0.005)
	g = g - 1
	script.Parent.Color = Color3.fromRGB(r,g,b)
	end
	
	while (b == 255 and r ~= 255) do
	wait(0.005)
	r = r + 1
	script.Parent.Color = Color3.fromRGB(r,g,b)
	end
	wait(0.005)
	b = b - 1
	script.Parent.Color = Color3.fromRGB(r,g,b)
	while (b ~= 0) do
	wait(0.005)
	b = b - 1
	script.Parent.Color = Color3.fromRGB(r,g,b)
	end
	
end