local main = {
	Services = {
		Players = game:GetService("Players"),
		UserInputService = game:GetService("UserInputService"),
		RunService = game:GetService("RunService"),
	},
	State = {
		Toggles = {},
		Setters = {},
	},
	Settings = {
		notifications = false,
		showStatusBar = false,
		autoCloseDropdowns = false,
		toastDuration = 2.5,
		dropdownHeight = 330,
		panelOpacity = 40,
		compactMode = false,
		showHints = true,
		highContrast = false,
		showIconLabels = true,
		lockPanelPosition = false,
		silent = false,
	},
	UI = {},
}

local uiScale_LAYOUT_CLASSES = { "UIListLayout", "UIGridLayout", "UIPageLayout", "UITableLayout" }

local function uiScale_resolve(udim: UDim, extent: number): number
	return udim.Scale * extent + udim.Offset
end

local function uiScale_hasLayout(parent: Instance): boolean
	for _, className in uiScale_LAYOUT_CLASSES do
		if parent:FindFirstChildWhichIsA(className) then
			return true
		end
	end
	return false
end

local function uiScale_contentBox(parent: GuiBase2d): (Vector2, Vector2)
	local size = parent.AbsoluteSize
	local origin = parent.AbsolutePosition
	local padding = parent:FindFirstChildWhichIsA("UIPadding")
	if not padding then
		return origin, size
	end
	local left = uiScale_resolve(padding.PaddingLeft, size.X)
	local right = uiScale_resolve(padding.PaddingRight, size.X)
	local top = uiScale_resolve(padding.PaddingTop, size.Y)
	local bottom = uiScale_resolve(padding.PaddingBottom, size.Y)
	return origin + Vector2.new(left, top), size - Vector2.new(left + right, top + bottom)
end

local function uiScale_toScale(absolute: Vector2, content: Vector2): UDim2
	return UDim2.fromScale(absolute.X / content.X, absolute.Y / content.Y)
end

local function uiScale_planObject(object: GuiObject, plan: { () -> () })
	local parent = object.Parent
	if not (parent and parent:IsA("GuiBase2d")) then
		return
	end
	if parent:FindFirstChildWhichIsA("UIGridLayout") then
		return
	end
	local contentOrigin, content = uiScale_contentBox(parent)
	if content.X <= 0 or content.Y <= 0 then
		return
	end
	local absoluteSize = object.AbsoluteSize
	local size = object.Size
	local automatic = object.AutomaticSize
	local scaled = uiScale_toScale(absoluteSize, content)
	local keepX = automatic == Enum.AutomaticSize.X or automatic == Enum.AutomaticSize.XY
	local keepY = automatic == Enum.AutomaticSize.Y or automatic == Enum.AutomaticSize.XY
	local newSize = UDim2.new(if keepX then size.X else scaled.X, if keepY then size.Y else scaled.Y)
	local positionManaged = uiScale_hasLayout(parent)
	local anchored = object.AbsolutePosition - contentOrigin + object.AnchorPoint * absoluteSize
	local newPosition = uiScale_toScale(anchored, content)
	local pureOffset = size.X.Scale == 0 and size.Y.Scale == 0 and absoluteSize.X > 0 and absoluteSize.Y > 0
	local fixedShape = pureOffset and automatic == Enum.AutomaticSize.None
	local aspect = if fixedShape and not object:FindFirstChildWhichIsA("UIAspectRatioConstraint")
		then absoluteSize.X / absoluteSize.Y
		else nil
	table.insert(plan, function()
		object.Size = newSize
		if not positionManaged then
			object.Position = newPosition
		end
		if aspect then
			local constraint = Instance.new("UIAspectRatioConstraint")
			constraint.AspectRatio = aspect
			constraint.Parent = object
		end
	end)
end

local function uiScale_planHelpers(object: GuiBase2d, plan: { () -> () })
	local _, content = uiScale_contentBox(object)
	local size = object.AbsoluteSize
	for _, child in object:GetChildren() do
		if child:IsA("UIGridLayout") then
			local cell = Vector2.new(
				uiScale_resolve(child.CellSize.X, content.X),
				uiScale_resolve(child.CellSize.Y, content.Y)
			)
			local gap = Vector2.new(
				uiScale_resolve(child.CellPadding.X, content.X),
				uiScale_resolve(child.CellPadding.Y, content.Y)
			)
			table.insert(plan, function()
				child.CellSize = uiScale_toScale(cell, content)
				child.CellPadding = uiScale_toScale(gap, content)
			end)
		elseif child:IsA("UIListLayout") then
			local extent = if child.FillDirection == Enum.FillDirection.Horizontal then content.X else content.Y
			local gap = uiScale_resolve(child.Padding, extent)
			table.insert(plan, function()
				child.Padding = UDim.new(gap / extent, 0)
			end)
		elseif child:IsA("UIPadding") then
			local left = uiScale_resolve(child.PaddingLeft, size.X)
			local right = uiScale_resolve(child.PaddingRight, size.X)
			local top = uiScale_resolve(child.PaddingTop, size.Y)
			local bottom = uiScale_resolve(child.PaddingBottom, size.Y)
			table.insert(plan, function()
				child.PaddingLeft = UDim.new(left / size.X, 0)
				child.PaddingRight = UDim.new(right / size.X, 0)
				child.PaddingTop = UDim.new(top / size.Y, 0)
				child.PaddingBottom = UDim.new(bottom / size.Y, 0)
			end)
		elseif child:IsA("UICorner") then
			local shortest = math.min(size.X, size.Y)
			local radius = uiScale_resolve(child.CornerRadius, shortest)
			table.insert(plan, function()
				child.CornerRadius = UDim.new(radius / shortest, 0)
			end)
		end
	end
end

local function uiScale_hasOwnScale(screenGui: ScreenGui): boolean
	for _, descendant in screenGui:GetDescendants() do
		if descendant:IsA("UIScale") and not descendant.Parent:IsA("GuiButton") then
			return true
		end
	end
	return false
end

local function uiScale_convert(screenGui: ScreenGui)
	if screenGui.AbsoluteSize.X <= 0 or screenGui.AbsoluteSize.Y <= 0 then
		return
	end
	-- A UIScale is the tree's own responsiveness: AbsoluteSize already carries
	-- its factor, so rewriting to Scale would apply it twice on the next
	-- viewport change while fixed TextSizes only get it once.
	if uiScale_hasOwnScale(screenGui) then
		return
	end
	local plan: { () -> () } = {}
	for _, descendant in screenGui:GetDescendants() do
		if descendant:IsA("GuiObject") then
			uiScale_planObject(descendant, plan)
			if descendant.AbsoluteSize.X > 0 and descendant.AbsoluteSize.Y > 0 then
				uiScale_planHelpers(descendant, plan)
			end
		end
	end
	for _, apply in plan do
		apply()
	end
end

if main.Services.RunService:IsRunning() and main.Services.RunService:IsClient() then
	local playerGui = main.Services.Players.LocalPlayer:WaitForChild("PlayerGui")
	playerGui.ChildAdded:Connect(function(child)
		if not child:IsA("ScreenGui") then
			return
		end
		task.defer(function()
			main.Services.RunService.RenderStepped:Wait()
			uiScale_convert(child)
		end)
	end)
end

-- layout: admin-control-panel
-- BahayKubo Panel — control panel (studded-blocky-cartoon theme)
Players = main.Services.Players
UIS = main.Services.UserInputService
RunService = main.Services.RunService
playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

-- Static interaction mode: no tween, fade, or press animation.
function addPressFeedback(button)
	return button
end

function animatePanelOpen(panelFrame)
	panelFrame.Visible = true
	panelFrame.BackgroundTransparency = uiSettings.panelOpacity / 100
end

function animatePanelClose(panelFrame, callback)
	panelFrame.Visible = false
	panelFrame.BackgroundTransparency = uiSettings.panelOpacity / 100
	if callback then callback() end
end

function makeDraggable(panelFrame, handle)
	local dragging = false
	local dragStart = Vector2.zero
	local startPos = panelFrame.Position
	local dragInput = nil

	local function begin(io)
		if io.UserInputType ~= Enum.UserInputType.MouseButton1 and io.UserInputType ~= Enum.UserInputType.Touch then return end
		dragging = true
		dragInput = io
		dragStart = io.Position
		startPos = panelFrame.Position
	end

	local function finish(io)
		if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then
			dragging = false
			dragInput = nil
		end
	end

	handle.Active = true
	handle.InputBegan:Connect(begin)
	UIS.InputEnded:Connect(finish)

	UIS.InputChanged:Connect(function(io)
		if not dragging then return end
		if io.UserInputType ~= Enum.UserInputType.MouseMovement and io.UserInputType ~= Enum.UserInputType.Touch then return end
		if dragInput and dragInput.UserInputType == Enum.UserInputType.Touch and io.UserInputType ~= Enum.UserInputType.Touch then return end
		local cam = workspace.CurrentCamera
		if not cam then return end
		local delta = io.Position - dragStart
		local viewport = cam.ViewportSize
		local panelSize = panelFrame.AbsoluteSize
		local margin = 10
		local maxX = math.max(0, viewport.X * 0.5 - panelSize.X * 0.5 - margin)
		local maxY = math.max(0, viewport.Y * 0.5 - panelSize.Y * 0.5 - margin)
		local x = math.clamp(startPos.X.Offset + delta.X, -maxX, maxX)
		local y = math.clamp(startPos.Y.Offset + delta.Y, -maxY, maxY)
		panelFrame.Position = UDim2.new(startPos.X.Scale, x, startPos.Y.Scale, y)
	end)
end

STUDS = "rbxassetid://92521981645530"
C = {
	green = Color3.fromRGB(88, 176, 66),
	leaf = Color3.fromRGB(58, 130, 48),
	brown = Color3.fromRGB(160, 104, 52),
	orange = Color3.fromRGB(232, 138, 42),
	blue = Color3.fromRGB(66, 132, 222),
	sky = Color3.fromRGB(84, 176, 226),
	red = Color3.fromRGB(214, 62, 52),
	purple = Color3.fromRGB(150, 84, 216),
	gold = Color3.fromRGB(255, 196, 47),
	pink = Color3.fromRGB(226, 92, 152),
	gray = Color3.fromRGB(122, 128, 134),
	dark = Color3.fromRGB(30, 32, 36),
}
RARITY = {
	Common = C.gray, Uncommon = C.green, Rare = C.blue,
	Epic = C.purple, Legendary = C.orange, Mythic = C.red,
	Ancient = C.sky, Divine = C.gold, Secret = Color3.new(1, 1, 1),
}
function shade(c, f)
	return Color3.new(c.R * f, c.G * f, c.B * f)
end

function applyFace(base, color, faceH)
	local face = Instance.new("Frame")
	face.Name = "Face"
	face.BackgroundColor3 = Color3.new(1, 1, 1)
	face.BorderSizePixel = 0
	face.Size = UDim2.new(1, 0, faceH, 0)
	face.ZIndex = base.ZIndex + 1
	face.Parent = base
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	grad.Parent = face
	local pat = Instance.new("ImageLabel")
	pat.Name = "Studs"
	pat.BackgroundTransparency = 1
	pat.Image = STUDS
	pat.ImageTransparency = 0.55
	pat.Size = UDim2.new(1, 0, 1, 0)
	pat.ZIndex = face.ZIndex
	pat.Parent = face
	return face, grad
end

function bevelFrame(parent, color, faceH, name)
	local base = Instance.new("Frame")
	base.Name = name or "Bevel"
	base.BackgroundColor3 = shade(color, 0.45)
	base.BorderSizePixel = 0
	base.Parent = parent
	local st = Instance.new("UIStroke")
	st.Color = Color3.new(0, 0, 0)
	st.Thickness = 4
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	st.Parent = base
	applyFace(base, color, faceH)
	return base
end

function bevelButton(parent, color, name)
	local base = Instance.new("TextButton")
	base.Name = name or "Btn"
	base.Text = ""
	base.AutoButtonColor = false
	base.BackgroundColor3 = shade(color, 0.45)
	base.BorderSizePixel = 0
	base.Parent = parent
	local st = Instance.new("UIStroke")
	st.Color = Color3.new(0, 0, 0)
	st.Thickness = 4
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	st.Parent = base
	local face, grad = applyFace(base, color, 0.90)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = base
	local faceCorner = Instance.new("UICorner")
	faceCorner.CornerRadius = UDim.new(0, 8)
	faceCorner.Parent = face
	return base, face, grad
end

function makeText(parent, text, txtColor, pos, size, strokeT, z, align, textSize)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.Text = tostring(text or "")
	l.TextColor3 = txtColor
	l.TextScaled = false
	l.TextWrapped = false
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.TextYAlignment = Enum.TextYAlignment.Center
	l.Position = pos
	l.Size = size
	l.ZIndex = z or 4
	l.ClipsDescendants = true
	l.TextSize = textSize or 17
	l.LineHeight = 1
	l.RichText = false
	local cap = Instance.new("UITextSizeConstraint")
	cap.MinTextSize = math.max(13, math.min(textSize or 17, 15))
	cap.MaxTextSize = math.max(22, textSize or 17)
	cap.Parent = l
	if align == "right" then
		l.AnchorPoint = Vector2.new(1, 0)
		l.TextXAlignment = Enum.TextXAlignment.Right
	elseif align == "center" then
		l.TextXAlignment = Enum.TextXAlignment.Center
	else
		l.TextXAlignment = Enum.TextXAlignment.Left
	end
	if strokeT then
		local s = Instance.new("UIStroke")
		s.Color = Color3.new(0, 0, 0)
		s.Thickness = strokeT
		s.Parent = l
	end
	l.Parent = parent
	return l
end

-- Blocky/studded icon treatment: the same STUDS texture is used as a small backing plate
-- so every icon visually matches the studded UI instead of looking like a floating image.
function makeStudIcon(parent, icon, size, x, y, z, tint)
	local box = Instance.new("Frame")
	box.Name = "StudIcon"
	box.Size = UDim2.fromOffset(size, size)
	box.Position = UDim2.new(0, x or 0, 0.5, y or -(size/2))
	box.BackgroundColor3 = tint or C.dark
	box.BackgroundTransparency = 0.06
	box.BorderSizePixel = 0
	box.ZIndex = z or 20
	box.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, math.max(6, math.floor(size*0.22)))
	corner.Parent = box
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Thickness = 2
	stroke.Parent = box
	local studs = Instance.new("ImageLabel")
	studs.Name = "Studs"
	studs.BackgroundTransparency = 1
	studs.Image = STUDS
	studs.ImageTransparency = 0.62
	studs.Size = UDim2.fromScale(1, 1)
	studs.ZIndex = (z or 20) + 1
	studs.Parent = box
	local image = Instance.new("ImageLabel")
	image.Name = "Icon"
	image.BackgroundTransparency = 1
	image.Size = UDim2.new(0.70, 0, 0.70, 0)
	image.Position = UDim2.fromScale(0.15, 0.15)
	image.ScaleType = Enum.ScaleType.Fit
	image.ZIndex = (z or 20) + 2
	if type(icon) == "string" and icon:match("^rbxassetid://") then
		image.Image = icon
		image.ImageColor3 = Color3.new(1,1,1)
	else
		image.Visible = false
		local glyph = makeText(box, tostring(icon or "◆"), Color3.new(1,1,1), UDim2.fromScale(0.03,0.03), UDim2.new(0.94,0,0.94,0), 1.5, (z or 20)+2, "center")
		glyph.Name = "IconGlyph"
	end
	image.Parent = box
	return box, image
end

ToggleState = main.State.Toggles
ToggleSetters = main.State.Setters
-- notify is assigned below; this standalone identifier was invalid Luau syntax.
uiSettings = main.Settings
uiSettings.studIconStyle = uiSettings.studIconStyle ~= false

MASTER_IGNORE = {
	antiAFK=true, notifications=true, showStatusBar=true, autoCloseDropdowns=true,
	alertRareCrop=true, alertMutation=true, alertRestock=true, alertEggReady=true,
	alertLowWater=true, alertLowMoney=true, preferRareMutations=true,
	ignoreCommonDrops=true, buyNeededSeeds=true, hatchSelectedEggs=true,
	compactMode=true, showHints=true, highContrast=true, studIconStyle=true,
}
function isMasterTarget(key) return not MASTER_IGNORE[key] end

toggleIcons = {
	autoHarvest="rbxassetid://84998465111718", autoRefill="💧", autoSellAll="₱", autoSellSelected="✓",
	autoPayBill="₱", autoBuySeeds="🌱", autoBuyEggs="🥚", autoBuyGear="⚙", autoBuyBasics="▣",
	autoBuyDecor="▦", autoBuyMerchant="🛒", autoPlaceAll="🥚", autoPlaceSelected="✓", autoPlaceReady="★",
	autoSleep="☾", autoCodes="#", antiAFK="◉", autoBestPets="🐾", farmSetup="⌂",
	notifications="●", showStatusBar="▤", autoCloseDropdowns="⌄", compactMode="≡", showHints="?",
	highContrast="◐", showIconLabels="◆", studIconStyle="●", lockPanelPosition="⌐",
	preferRareMutations="★", ignoreCommonDrops="×", buyNeededSeeds="✓", hatchSelectedEggs="🥚",
	alertRareCrop="!", alertMutation="!", alertRestock="↻", alertEggReady="🥚", alertLowWater="💧", alertLowMoney="₱"
}

actionIcons = {
	["Center Panel"]="⌂", ["Reset UI View"]="↺", ["Apply UI Settings"]="✓",
	["🌱 Farming Profile"]="🌱", ["🛒 Shopping Profile"]="🛒", ["💤 Low Activity / Safe UI"]="◉"
}

function makeToggle(page, title, default, key)
	local base, face, grad = bevelButton(page, C.leaf, "Toggle_" .. key)
	base.Size = UDim2.new(1, 0, 0, 46)
	local state = default == true
	ToggleState[key] = state
	if uiSettings[key] ~= nil then uiSettings[key] = state end
	if key == "notifications" then uiSettings.notifications = state end
	if key == "showStatusBar" then uiSettings.showStatusBar = state end
	if key == "autoCloseDropdowns" then uiSettings.autoCloseDropdowns = state end
	local iconBadge = makeStudIcon(face, toggleIcons[key] or "◆", 26, 7, -13, 7, C.dark)
	local lab = makeText(face, title, Color3.new(1, 1, 1), UDim2.new(0, 42, 0.08, 0), UDim2.new(0.56, -4, 0.84, 0), 2.2, 8, "left", 16)
	local chip = makeText(face, "OFF", Color3.new(1, 1, 1), UDim2.new(0.97, -2, 0.08, 0), UDim2.new(0.25, 0, 0.84, 0), 2.2, 8, "right", 15)
	local function refresh()
		if state then
			grad.Color = ColorSequence.new(Color3.fromRGB(210, 255, 200), C.green)
			chip.Text = "ON · SAFE"
		else
			grad.Color = ColorSequence.new(Color3.fromRGB(198, 202, 206), C.gray)
			chip.Text = "OFF"
		end
		ToggleState[key] = state
	end
	local function setState(val)
		if state ~= val then
			state = val
			refresh()
			if uiSettings[key] ~= nil then uiSettings[key] = state end
			if key == "notifications" then uiSettings.notifications = state end
			if key == "showStatusBar" then uiSettings.showStatusBar = state end
			if key == "autoCloseDropdowns" then uiSettings.autoCloseDropdowns = state end
			print("[BahayKuboGarden] Toggle " .. title .. " = " .. tostring(state))
			if notify and not uiSettings.silent then
				notify(title .. (state and " enabled" or " disabled"), state and C.green or C.gray)
			end
		end
	end
	ToggleSetters[key] = setState
	base.MouseButton1Click:Connect(function()
		if key == "antiAFK" then
			if notify then notify("Anti-AFK is locked ON", C.blue) end
			return
		end
		setState(not state)
	end)
	refresh()
	addPressFeedback(base)
	return base
end

openDropdown = nil
function closeDropdown()
	if openDropdown and openDropdown.Parent then
		local wrap = openDropdown.Parent
		openDropdown.Visible = false
		if wrap and wrap:IsA("Frame") and wrap.Name:sub(1, 7) == "DDWrap_" then
			wrap.Size = UDim2.new(1, 0, 0, 46)
		end
	end
	openDropdown = nil
end

function makeDropdown(page, title, items, opts)
	opts = opts or {}
	local single = opts.single == true
	local onChange = opts.onChange
	local wrap = Instance.new("Frame")
	wrap.Name = "DDWrap_" .. title:gsub("%W", "")
	wrap.BackgroundTransparency = 1
	wrap.Size = UDim2.new(1, 0, 0, 46)
	wrap.ClipsDescendants = false
	wrap.ZIndex = 10
	wrap.Parent = page

	local base, face, grad = bevelButton(wrap, C.blue, "DD_" .. title)
	base.Size = UDim2.new(1, 0, 0, 46)
	base.ZIndex = 40
	face.ZIndex = 41
	face.ClipsDescendants = false

	-- Consistent dropdown header columns: title stays left, selection stays right.
	local titleLabel = makeText(
		face,
		title,
		Color3.new(1, 1, 1),
		UDim2.new(0, 14, 0, 3),
		UDim2.new(0.56, -14, 1, -6),
		2.5,
		42,
		"left",
		18
	)
	titleLabel.TextTruncate = Enum.TextTruncate.AtEnd

	local countPill = Instance.new("Frame")
	countPill.Name = "SelectionPill"
	countPill.AnchorPoint = Vector2.new(1, 0.5)
	countPill.Position = UDim2.new(1, -32, 0.5, 0)
	countPill.Size = UDim2.fromOffset(112, 30)
	countPill.BackgroundColor3 = C.dark
	countPill.BackgroundTransparency = 0.10
	countPill.BorderSizePixel = 0
	countPill.ZIndex = 42
	countPill.Parent = face
	local pillCorner = Instance.new("UICorner")
	pillCorner.CornerRadius = UDim.new(0, 7)
	pillCorner.Parent = countPill
	local pillStroke = Instance.new("UIStroke")
	pillStroke.Color = Color3.fromRGB(0, 0, 0)
	pillStroke.Thickness = 2
	pillStroke.Parent = countPill

	local countLab = makeText(
		countPill,
		"0 selected",
		Color3.fromRGB(245, 248, 250),
		UDim2.new(0, 8, 0, 1),
		UDim2.new(1, -16, 1, -2),
		1.8,
		43,
		"center",
		16
	)
	countLab.TextTruncate = Enum.TextTruncate.AtEnd

	local chevron = makeText(
		face,
		"▼",
		Color3.fromRGB(230, 238, 245),
		UDim2.new(1, -25, 0, 2),
		UDim2.new(0, 18, 1, -4),
		1.5,
		43,
		"center",
		13
	)
	chevron.TextYAlignment = Enum.TextYAlignment.Center

	local selected = {}
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundColor3 = Color3.fromRGB(26, 28, 32)
	body.BackgroundTransparency = 0.03
	body.BorderSizePixel = 0
	body.Position = UDim2.new(0, 0, 0, 52)
	body.Size = UDim2.new(1, 0, 0, uiSettings.dropdownHeight)
	body.Visible = false
	body.ClipsDescendants = true
	body.ZIndex = 50
	body.Parent = wrap
	local bst = Instance.new("UIStroke")
	bst.Color = Color3.fromRGB(0, 0, 0)
	bst.Thickness = 3
	bst.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	bst.Parent = body
	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(0, 8)
	bc.Parent = body

	local search = Instance.new("TextBox")
	search.Name = "Search"
	search.PlaceholderText = "Search items..."
	search.Text = ""
	search.Font = Enum.Font.GothamMedium
	search.TextColor3 = Color3.fromRGB(245, 247, 250)
	search.PlaceholderColor3 = Color3.fromRGB(160, 166, 174)
	search.TextSize = 17
	search.TextXAlignment = Enum.TextXAlignment.Left
	search.TextYAlignment = Enum.TextYAlignment.Center
	search.TextWrapped = false
	search.TextScaled = false
	search.ClearTextOnFocus = false
	search.BackgroundColor3 = C.dark
	search.BorderSizePixel = 0
	search.Position = UDim2.new(0, 10, 0, 9)
	search.Size = UDim2.new(1, -20, 0, 38)
	search.ZIndex = 55
	search.Parent = body
	local sst = Instance.new("UIStroke")
	sst.Color = Color3.fromRGB(0, 0, 0)
	sst.Thickness = 2
	sst.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	sst.Parent = search
	local sc = Instance.new("UICorner")
	sc.CornerRadius = UDim.new(0, 7)
	sc.Parent = search
	local spad = Instance.new("UIPadding")
	spad.PaddingLeft = UDim.new(0, 12)
	spad.PaddingRight = UDim.new(0, 10)
	spad.Parent = search

	local rows = {}
	local list = Instance.new("ScrollingFrame")
	list.Name = "ItemList"
	list.BackgroundTransparency = 1
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new(0, 0, 0, 0)
	list.ScrollBarThickness = 6
	list.ScrollBarImageColor3 = C.green
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.Position = UDim2.new(0, 10, 0, single and 58 or 102)
	list.Size = UDim2.new(1, -20, 1, -(single and 68 or 112))
	list.ZIndex = 54
	list.ClipsDescendants = true
	list.Parent = body
	local ll = Instance.new("UIListLayout")
	ll.Padding = UDim.new(0, 7)
	ll.SortOrder = Enum.SortOrder.LayoutOrder
	ll.Parent = list

	local function resizeWrap(isOpen)
		wrap.Size = UDim2.new(1, 0, 0, isOpen and (54 + uiSettings.dropdownHeight) or 46)
	end

	local function refreshCount()
		local n = 0
		for _ in pairs(selected) do n += 1 end
		countLab.Text = n == 0 and "None selected" or (tostring(n) .. " selected")
	end

	local function clearVisibleRows()
		for _, r in pairs(rows) do
			r.box.Text = ""
			r.box.BackgroundColor3 = C.dark
		end
	end

	local function setItem(item)
		local row = rows[item.name]
		if not row then return end
		if single then
			table.clear(selected) -- keep the same table so returned selections stay live
			clearVisibleRows()
		end
		if selected[item.name] then
			selected[item.name] = nil
			row.box.Text = ""
			row.box.BackgroundColor3 = C.dark
		else
			selected[item.name] = true
			row.box.Text = "✓"
			row.box.BackgroundColor3 = C.green
		end
		refreshCount()
		if onChange then onChange(selected) end
	end

	if not single then
		local allB, allF = bevelButton(body, C.green, "All")
		allB.Position = UDim2.new(0, 10, 0, 55)
		allB.Size = UDim2.new(0.5, -15, 0, 38)
		allB.ZIndex = 56
		allF.ZIndex = 57
		local allText = makeText(allF, "Select All", Color3.new(1, 1, 1), UDim2.new(0, 6, 0, 1), UDim2.new(1, -12, 1, -2), 2.5, 57, "center", 16)
		allText.TextTruncate = Enum.TextTruncate.AtEnd
		allB.MouseButton1Click:Connect(function()
			for _, item in items do selected[item.name] = true end
			for _, r in pairs(rows) do r.box.Text = "✓"; r.box.BackgroundColor3 = C.green end
			refreshCount()
			if onChange then onChange(selected) end
		end)

		local noneB, noneF = bevelButton(body, C.red, "None")
		noneB.Position = UDim2.new(0.5, 5, 0, 55)
		noneB.Size = UDim2.new(0.5, -15, 0, 38)
		noneB.ZIndex = 56
		noneF.ZIndex = 57
		local noneText = makeText(noneF, "Deselect All", Color3.new(1, 1, 1), UDim2.new(0, 6, 0, 1), UDim2.new(1, -12, 1, -2), 2.5, 57, "center", 16)
		noneText.TextTruncate = Enum.TextTruncate.AtEnd
		noneB.MouseButton1Click:Connect(function()
			table.clear(selected) -- keep the same table so returned selections stay live
			clearVisibleRows()
			refreshCount()
			if onChange then onChange(selected) end
		end)
	end

	for index, item in ipairs(items) do
		local row = Instance.new("Frame")
		row.Name = "Item_" .. tostring(index)
		row.BackgroundColor3 = index % 2 == 0 and Color3.fromRGB(47, 50, 55) or Color3.fromRGB(54, 57, 62)
		row.BorderSizePixel = 0
		row.Size = UDim2.new(1, 0, 0, 58)
		row.LayoutOrder = index
		row.ZIndex = 58
		row.Parent = list
		local rst = Instance.new("UIStroke")
		rst.Color = Color3.fromRGB(0, 0, 0)
		rst.Thickness = 2
		rst.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		rst.Parent = row
		local rc = Instance.new("UICorner")
		rc.CornerRadius = UDim.new(0, 6)
		rc.Parent = row

		local box = Instance.new("TextButton")
		box.Name = "Select"
		box.Text = ""
		box.AutoButtonColor = false
		box.BackgroundColor3 = C.dark
		box.BorderSizePixel = 0
		box.Position = UDim2.new(0, 7, 0, 16)
		box.Size = UDim2.fromOffset(26, 26)
		box.Font = Enum.Font.GothamBold
		box.TextColor3 = Color3.new(1, 1, 1)
		box.TextSize = 17
		box.TextXAlignment = Enum.TextXAlignment.Center
		box.TextYAlignment = Enum.TextYAlignment.Center
		box.ZIndex = 61
		box.Parent = row
		local bstk = Instance.new("UIStroke")
		bstk.Color = Color3.new(0, 0, 0)
		bstk.Thickness = 2
		bstk.Parent = box
		local bc2 = Instance.new("UICorner")
		bc2.CornerRadius = UDim.new(0, 5)
		bc2.Parent = box

		local rar = RARITY[item.rarity] or C.gray
		local nameLabel = makeText(row, item.name, rar, UDim2.new(0, 43, 0, 5), UDim2.new(0.56, -48, 0, 20), 2, 60, "left", 16)
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd

		local rarityLabel = makeText(row, item.rarity or "", rar, UDim2.new(0.58, 0, 0, 5), UDim2.new(0.40, -7, 0, 20), 2, 60, "right", 15)
		rarityLabel.TextTruncate = Enum.TextTruncate.AtEnd

		local descLab = Instance.new("TextLabel")
		descLab.BackgroundTransparency = 1
		descLab.Font = Enum.Font.GothamMedium
		descLab.Text = tostring(item.desc or "")
		descLab.TextColor3 = Color3.fromRGB(198, 204, 212)
		descLab.TextSize = 13
		descLab.TextScaled = false
		descLab.TextWrapped = false
		descLab.TextTruncate = Enum.TextTruncate.AtEnd
		descLab.TextXAlignment = Enum.TextXAlignment.Left
		descLab.TextYAlignment = Enum.TextYAlignment.Center
		descLab.Position = UDim2.new(0, 43, 0, 28)
		descLab.Size = UDim2.new(1, -52, 0, 22)
		descLab.ZIndex = 60
		descLab.ClipsDescendants = true
		descLab.Parent = row
		local dpad = Instance.new("UIPadding")
		dpad.PaddingRight = UDim.new(0, 4)
		dpad.Parent = descLab

		rows[item.name] = { box = box, row = row }
		box.MouseButton1Click:Connect(function() setItem(item) end)
		row.InputBegan:Connect(function(io)
			if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then
				setItem(item)
			end
		end)
	end

	search:GetPropertyChangedSignal("Text"):Connect(function()
		local q = string.lower(search.Text)
		for name, r in pairs(rows) do
			r.row.Visible = q == "" or string.find(string.lower(name), q, 1, true) ~= nil
		end
		list.CanvasPosition = Vector2.new(0, 0)
	end)

	base.MouseButton1Click:Connect(function()
		if openDropdown and openDropdown ~= body then closeDropdown() end
		local opening = not body.Visible
		body.Visible = opening
		openDropdown = opening and body or nil
		resizeWrap(opening)
		chevron.Text = opening and "▲" or "▼"
		if opening then
			body.ZIndex = 70
			chevron.TextColor3 = C.gold
			notify(title .. " opened", C.blue)
		else
			body.ZIndex = 50
			chevron.TextColor3 = Color3.fromRGB(230, 238, 245)
		end
	end)

	refreshCount()
	return base, body, selected
end

function makeHeader(page, title, color, iconId)
	local base = bevelFrame(page, color, 0.90, "Header_" .. title)
	base.Size = UDim2.new(1, 0, 0, 46)
	if iconId then
		makeStudIcon(base, iconId, 32, 7, -16, 7, C.dark)
	end
	local titleText = makeText(base, title, Color3.new(1, 1, 1), UDim2.new(0, iconId and 48 or 12, 0.07, 0), UDim2.new(0.84, iconId and -58 or -20, 0.86, 0), 2.6, 8, "left", 19)
	titleText.TextTruncate = Enum.TextTruncate.AtEnd
	return base
end

function makeDarkRow(page, label, value, color, h)
	local base = Instance.new("Frame")
	base.BackgroundColor3 = C.dark
	base.BackgroundTransparency = 0.18
	base.BorderSizePixel = 0
	base.Size = UDim2.new(1, 0, 0, h or 40)
	base.ZIndex = 3
	base.Parent = page
	local st = Instance.new("UIStroke")
	st.Color = Color3.new(0, 0, 0)
	st.Thickness = 3
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	st.Parent = base
	if label then
		local labelText = makeText(base, label, Color3.fromRGB(226, 230, 236), UDim2.new(0, 14, 0.06, 0), UDim2.new(0.61, -22, 0.88, 0), 1.6, 4, "left", 16)
		labelText.TextTruncate = Enum.TextTruncate.AtEnd
	end
	if value then
		local valueText = makeText(base, value, color or Color3.new(1, 1, 1), UDim2.new(0.64, 0, 0.06, 0), UDim2.new(0.34, -14, 0.88, 0), 1.6, 5, "right", 16)
		valueText.TextTruncate = Enum.TextTruncate.AtEnd
	end
	return base
end

function makeStat(page, label, value, color, iconId)
	local row = makeDarkRow(page, label, value, color, 38)
	if iconId then
		local badge = makeStudIcon(row, iconId, 24, 10, -12, 6, C.dark)
		local labelText = row:FindFirstChildWhichIsA("TextLabel")
		if labelText then
			labelText.Position = UDim2.new(0, 42, 0.06, 0)
			labelText.Size = UDim2.new(0.56, 0, 0.88, 0)
		end
	end
	return row
end

function makeStockRow(page, name)
	-- Stock entries intentionally show names only; quantity labels such as 6/2/3/27 are removed.
	return makeDarkRow(page, name, nil, C.gold, 40)
end

function makeInput(page, label, placeholder)
	local wrap = Instance.new("Frame")
	wrap.BackgroundTransparency = 1
	wrap.Size = UDim2.new(1, 0, 0, 60)
	wrap.Parent = page
	local lab = Instance.new("TextLabel")
	lab.BackgroundTransparency = 1
	lab.Font = Enum.Font.GothamBold
	lab.Text = tostring(label)
	lab.TextColor3 = Color3.fromRGB(226, 230, 236)
	lab.TextScaled = false
	lab.TextSize = 16
	lab.TextYAlignment = Enum.TextYAlignment.Center
	lab.TextXAlignment = Enum.TextXAlignment.Left
	lab.Size = UDim2.new(1, 0, 0, 20)
	lab.ZIndex = 4
	lab.Parent = wrap
	local cap = Instance.new("UITextSizeConstraint")
	cap.MaxTextSize = 17
	cap.MinTextSize = 12
	cap.Parent = lab
	local box = Instance.new("TextBox")
	box.PlaceholderText = placeholder
	box.Text = ""
	box.Font = Enum.Font.GothamBold
	box.TextColor3 = Color3.new(1, 1, 1)
	box.TextScaled = false
	box.TextSize = 16
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.TextYAlignment = Enum.TextYAlignment.Center
	box.ClearTextOnFocus = false
	box.BackgroundColor3 = C.dark
	box.BorderSizePixel = 0
	box.Position = UDim2.new(0, 0, 0, 24)
	box.Size = UDim2.new(1, 0, 0, 36)
	box.ZIndex = 4
	box.Parent = wrap
	local st = Instance.new("UIStroke")
	st.Color = Color3.new(0, 0, 0)
	st.Thickness = 3
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	st.Parent = box
	return wrap
end

function makeActionButton(page, title, color, callback)
	local base, face = bevelButton(page, color or C.green, "Action_" .. title:gsub("%W", ""))
	base.Size = UDim2.new(1, 0, 0, 46)
	makeStudIcon(face, actionIcons[title] or "◆", 28, 8, -14, 7, C.dark)
	local actionText = makeText(face, title, Color3.new(1, 1, 1), UDim2.new(0, 44, 0.08, 0), UDim2.new(1, -54, 0.84, 0), 2.5, 8, "center")
	actionText.TextTruncate = Enum.TextTruncate.AtEnd
	base.MouseButton1Click:Connect(function()
		if callback then callback(base) end
	end)
	addPressFeedback(base)
	return base
end


function makeSlider(page, title, minValue, maxValue, defaultValue, key, formatter)
	local wrap = Instance.new("Frame")
	wrap.BackgroundTransparency = 1
	wrap.Size = UDim2.new(1, 0, 0, 62)
	wrap.Parent = page
	local label = makeText(wrap, title, Color3.fromRGB(226, 230, 236), UDim2.new(0, 0, 0, 0), UDim2.new(0.68, 0, 0, 22), 1.5, 4)
	local valueLabel = makeText(wrap, "", C.gold, UDim2.new(0.68, 0, 0, 0), UDim2.new(0.32, 0, 0, 22), 1.5, 4, "right")
	local bar = Instance.new("TextButton")
	bar.Name = "Slider"
	bar.Text = ""
	bar.AutoButtonColor = false
	bar.BackgroundColor3 = C.dark
	bar.BorderSizePixel = 0
	bar.Position = UDim2.new(0, 0, 0, 28)
	bar.Size = UDim2.new(1, 0, 0, 28)
	bar.Parent = wrap
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Thickness = 3
	stroke.Parent = bar
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = C.green
	fill.BorderSizePixel = 0
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.Parent = bar
	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Position = UDim2.fromScale(0, 0.5)
	knob.Size = UDim2.fromOffset(14, 14)
	knob.BackgroundColor3 = Color3.new(1, 1, 1)
	knob.BorderSizePixel = 0
	knob.ZIndex = 3
	knob.Parent = bar
	local kCorner = Instance.new("UICorner")
	kCorner.CornerRadius = UDim.new(1, 0)
	kCorner.Parent = knob
	local dragging = false
	local value = math.clamp(defaultValue, minValue, maxValue)
	local function render()
		local alpha = (value - minValue) / math.max(1e-9, maxValue - minValue)
		fill.Size = UDim2.new(alpha, 0, 1, 0)
		knob.Position = UDim2.fromScale(alpha, 0.5)
		valueLabel.Text = formatter and formatter(value) or tostring(math.floor(value + 0.5))
		uiSettings[key] = value
	end
	local function setFromX(x)
		local left = bar.AbsolutePosition.X
		local width = math.max(1, bar.AbsoluteSize.X)
		local alpha = math.clamp((x - left) / width, 0, 1)
		value = minValue + (maxValue - minValue) * alpha
		render()
	end
	bar.InputBegan:Connect(function(io)
		if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			setFromX(io.Position.X)
		end
	end)
	bar.InputEnded:Connect(function(io)
		if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
	UIS.InputChanged:Connect(function(io)
		if dragging and (io.UserInputType == Enum.UserInputType.MouseMovement or io.UserInputType == Enum.UserInputType.Touch) then
			setFromX(io.Position.X)
		end
	end)
	local step = (maxValue - minValue) / 20
	bar.InputBegan:Connect(function(io)
		if io.KeyCode == Enum.KeyCode.Left then value = math.clamp(value - step, minValue, maxValue); render() end
		if io.KeyCode == Enum.KeyCode.Right then value = math.clamp(value + step, minValue, maxValue); render() end
	end)
	render()
	return wrap, function(v) value = math.clamp(v, minValue, maxValue); render() end
end

-- ==DATA==
-- Real crop list comes straight from the game's CropConfig so every dropdown
-- shows the actual crop IDs used on farms (CropName attributes, shop, selling).
ReplicatedStorage = game:GetService("ReplicatedStorage")
CropConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("CropConfig"))
CROPS = {}
do
	for cropId, cfg in pairs(CropConfig.Crops) do
		table.insert(CROPS, {
			name = cropId,
			rarity = cfg.Rarity,
			desc = "Seed ₱" .. tostring(cfg.SeedPrice) .. (cfg.DisplayName ~= cropId and ("  ·  " .. cfg.DisplayName) or ""),
		})
	end
	table.sort(CROPS, function(a, b)
		local ra = CropConfig.Rarities[a.rarity]
		local rb = CropConfig.Rarities[b.rarity]
		local oa = ra and ra.Order or 0
		local ob = rb and rb.Order or 0
		if oa ~= ob then return oa < ob end
		return a.name < b.name
	end)
end
MUTATIONS = {
	{ name = "Wet", rarity = "Common", desc = "Water or rain value bonus." },
	{ name = "Chilled", rarity = "Uncommon", desc = "Cold weather value bonus." },
	{ name = "Frozen", rarity = "Rare", desc = "Frost event value bonus." },
	{ name = "Golden", rarity = "Legendary", desc = "Rare shimmer value bonus." },
	{ name = "Rainbow", rarity = "Mythic", desc = "Special event value bonus." },
	{ name = "Shocked", rarity = "Mythic", desc = "Lightning strike value bonus." },
	{ name = "Silver", rarity = "Epic", desc = "Moonlit shimmer value bonus." },
	{ name = "Prismatic", rarity = "Mythic", desc = "Rare event bloom value bonus." },
	{ name = "Ancient", rarity = "Legendary", desc = "Old garden blessing value bonus." },
	{ name = "Glowing", rarity = "Epic", desc = "Bioluminescent leaf value bonus." },
}
EGGS = {
	{ name = "Common Egg", rarity = "Common", desc = "Basic pet egg, hatches fast." },
	{ name = "Rare Egg", rarity = "Rare", desc = "Better pet odds for the garden." },
	{ name = "Bug Egg", rarity = "Uncommon", desc = "Pollinator pets, boosts harvest." },
	{ name = "Mythical Egg", rarity = "Mythic", desc = "Top-tier pets, very rare stock." },
	{ name = "Ocean Egg", rarity = "Legendary", desc = "Aqua pets with wet mutations." },
	{ name = "Farm Egg", rarity = "Common", desc = "Classic farm pets with simple boosts." },
	{ name = "Forest Egg", rarity = "Rare", desc = "Woodland pets with mutation bonuses." },
	{ name = "Sky Egg", rarity = "Epic", desc = "Flying pets with speed bonuses." },
}

-- ==CORE==
existing = playerGui:FindFirstChild("BahayKuboPanel")
if existing then existing:Destroy() end
gui = Instance.new("ScreenGui")
gui.Name = "BahayKuboPanel"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
rootScale = Instance.new("UIScale")
rootScale.Name = "RootScale"
rootScale.Scale = 1
rootScale.Parent = gui
gui.Parent = playerGui

toastHolder = Instance.new("Frame")
toastHolder.Name = "ToastHolder"
toastHolder.AnchorPoint = Vector2.new(1, 0)
toastHolder.Position = UDim2.new(1, -18, 0, 18)
toastHolder.Size = UDim2.new(0, 300, 0, 210)
toastHolder.BackgroundTransparency = 1
toastHolder.ZIndex = 200
toastHolder.Parent = gui
toastList = Instance.new("UIListLayout")
toastList.Padding = UDim.new(0, 7)
toastList.HorizontalAlignment = Enum.HorizontalAlignment.Right
toastList.VerticalAlignment = Enum.VerticalAlignment.Top
toastList.Parent = toastHolder

notify = function(message, accent)
	if not uiSettings.notifications then return end
	local toast = Instance.new("Frame")
	toast.BackgroundColor3 = C.dark
	toast.BackgroundTransparency = 0.05
	toast.BorderSizePixel = 0
	toast.Size = UDim2.new(1, 0, 0, 46)
	toast.ZIndex = 201
	toast.Parent = toastHolder
	local st = Instance.new("UIStroke")
	st.Color = Color3.new(0, 0, 0)
	st.Thickness = 3
	st.Parent = toast
	local stripe = Instance.new("Frame")
	stripe.BorderSizePixel = 0
	stripe.BackgroundColor3 = accent or C.green
	stripe.Size = UDim2.new(0, 6, 1, 0)
	stripe.ZIndex = 202
	stripe.Parent = toast
	makeText(toast, message, Color3.fromRGB(235, 238, 242), UDim2.new(0, 16, 0.08, 0), UDim2.new(1, -24, 0.84, 0), 1.5, 202)
	toast.BackgroundTransparency = 0.05
	task.delay(uiSettings.toastDuration, function()
		if toast.Parent then toast:Destroy() end
	end)
end
panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.new(0.5, 0, 0.5, 0)
viewport = workspace.CurrentCamera.ViewportSize
aspectRatio = viewport.X / math.max(1, viewport.Y)
panelW = math.clamp(0.90 * math.min(1, 1.78 / math.max(0.01, aspectRatio)), 0.72, 0.90)
panel.Size = UDim2.new(panelW, 0, 0.84, 0)
panel.BackgroundColor3 = Color3.new(0, 0, 0)
panel.BackgroundTransparency = uiSettings.panelOpacity / 100
panel.Parent = gui
pst = Instance.new("UIStroke")
pst.Color = Color3.new(0, 0, 0)
pst.Thickness = 4
pst.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
pst.Parent = panel
panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 12)
panelCorner.Parent = panel

titleBar = bevelFrame(panel, C.leaf, 0.88, "TitleBar")
titleBar.Size = UDim2.new(1, 0, 0, 52)
tic = Instance.new("ImageLabel")
tic.BackgroundTransparency = 1
tic.Image = "rbxassetid://101953044632807"
tic.Size = UDim2.fromOffset(50, 50)
tic.Position = UDim2.new(0.015, 0, 0.5, 0)
tic.AnchorPoint = Vector2.new(0, 0.5)
tic.ScaleType = Enum.ScaleType.Fit
tic.ZIndex = 24
tic.Parent = titleBar
makeText(titleBar, "Bahay Kubo Garden", Color3.new(1, 1, 1), UDim2.new(0, 74, 0.08, 0), UDim2.new(0.58, 0, 0.62, 0), 3, 25)
titleSub = makeText(titleBar, "Garden Control Center", Color3.fromRGB(214, 240, 210), UDim2.new(0, 76, 0.60, 0), UDim2.new(0.38, 0, 0.25, 0), 1.2, 25)
titleStud = makeText(titleBar, "STUDDED UI", Color3.fromRGB(255, 235, 178), UDim2.new(0.30, 0, 0.62, 0), UDim2.new(0.18, 0, 0.22, 0), 1.0, 25, "center")
dragGrip = Instance.new("Frame")
dragGrip.Name = "DragGrip"
dragGrip.BackgroundTransparency = 1
dragGrip.Position = UDim2.new(0.46, 0, 0.08, 0)
dragGrip.Size = UDim2.new(0, 46, 0, 32)
dragGrip.ZIndex = 27
dragGrip.Parent = titleBar
for i = 0, 2 do
	local dot = Instance.new("Frame")
	dot.Size = UDim2.fromOffset(7, 7)
	dot.Position = UDim2.new(0, 4 + i * 14, 0.5, -3)
	dot.BackgroundColor3 = C.gold
	dot.BorderSizePixel = 0
	dot.ZIndex = 28
	dot.Parent = dragGrip
	local dc = Instance.new("UICorner")
	dc.CornerRadius = UDim.new(1, 0)
	dc.Parent = dot
end
-- Title-bar controls: kept in a dedicated, high-ZIndex group so they never disappear behind the header.
titleBar.Size = UDim2.new(1, 0, 0, 52)
titleBar.ZIndex = 20
titleBar.ClipsDescendants = false
titleFace = titleBar:FindFirstChild("Face")
if titleFace then titleFace.ZIndex = 21 end

livePill = titleBar:FindFirstChild("LivePill")
if livePill then livePill:Destroy() end
oldLiveDot = titleBar:FindFirstChild("LiveDot", true)
if oldLiveDot then oldLiveDot:Destroy() end

liveBadge = Instance.new("Frame")
liveBadge.Name = "LiveBadge"
liveBadge.AnchorPoint = Vector2.new(1, 0.5)
liveBadge.Position = UDim2.new(1, -92, 0.5, 0)
liveBadge.Size = UDim2.fromOffset(62, 28)
liveBadge.BackgroundColor3 = C.dark
liveBadge.BackgroundTransparency = 0.12
liveBadge.BorderSizePixel = 0
liveBadge.ZIndex = 30
liveBadge.Parent = titleBar
liveBadgeCorner = Instance.new("UICorner")
liveBadgeCorner.CornerRadius = UDim.new(0, 8)
liveBadgeCorner.Parent = liveBadge
liveStroke = Instance.new("UIStroke")
liveStroke.Color = C.green
liveStroke.Thickness = 2
liveStroke.Parent = liveBadge
liveDot = Instance.new("Frame")
liveDot.Name = "LiveDot"
liveDot.Size = UDim2.fromOffset(9, 9)
liveDot.Position = UDim2.new(0, 9, 0.5, -4)
liveDot.BackgroundColor3 = C.green
liveDot.BorderSizePixel = 0
liveDot.ZIndex = 31
liveDot.Parent = liveBadge
liveDotCorner = Instance.new("UICorner")
liveDotCorner.CornerRadius = UDim.new(1, 0)
liveDotCorner.Parent = liveDot
makeText(liveBadge, "READY", Color3.fromRGB(210, 245, 205), UDim2.new(0, 24, 0.05, 0), UDim2.new(1, -28, 0.9, 0), 1.2, 31, "center")

windowControls = Instance.new("Frame")
windowControls.Name = "WindowControls"
windowControls.AnchorPoint = Vector2.new(1, 0.5)
windowControls.Position = UDim2.new(1, -8, 0.5, 0)
windowControls.Size = UDim2.fromOffset(88, 38)
windowControls.BackgroundColor3 = C.dark
windowControls.BackgroundTransparency = 0.10
windowControls.BorderSizePixel = 0
windowControls.ZIndex = 30
windowControls.Parent = titleBar
controlsCorner = Instance.new("UICorner")
controlsCorner.CornerRadius = UDim.new(0, 9)
controlsCorner.Parent = windowControls
controlsStroke = Instance.new("UIStroke")
controlsStroke.Color = Color3.new(0, 0, 0)
controlsStroke.Thickness = 2
controlsStroke.Parent = windowControls
controlLayout = Instance.new("UIListLayout")
controlLayout.FillDirection = Enum.FillDirection.Horizontal
controlLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
controlLayout.VerticalAlignment = Enum.VerticalAlignment.Center
controlLayout.Padding = UDim.new(0, 4)
controlLayout.Parent = windowControls

function makeWindowControl(name, label, color)
	local btn, face, grad = bevelButton(windowControls, color, name)
	btn.Size = UDim2.fromOffset(38, 34)
	btn.ZIndex = 31
	face.ZIndex = 32
	local text = makeText(face, label, Color3.new(1, 1, 1), UDim2.fromScale(0.03, 0.02), UDim2.new(0.94, 0, 0.94, 0), 2, 33, "center")
	return btn, face, grad, text
end

normalPanelSize = panel.Size
minimized = false
-- rail/content/statusBar are assigned below; no standalone expression needed.

minimizeBtn, minimizeFace, minimizeGrad, minimizeLabel = makeWindowControl("MinimizeBtn", "—", C.orange)
closeBtn, closeFace, closeGrad, closeLabel = makeWindowControl("Close", "×", C.red)

function setMinimized(state)
	minimized = state == true
	if minimized then
		if rail then rail.Visible = false end
		if content then content.Visible = false end
		if statusBar then statusBar.Visible = false end
		panel.Size = UDim2.new(normalPanelSize.X.Scale, normalPanelSize.X.Offset, 0, 52)
		minimizeLabel.Text = "+"
		minimizeGrad.Color = ColorSequence.new(Color3.fromRGB(255, 226, 170), C.orange)
		liveDot.BackgroundColor3 = C.orange
		liveStroke.Color = C.orange
	else
		if rail then rail.Visible = true end
		if content then content.Visible = true end
		minimizeLabel.Text = "—"
		minimizeGrad.Color = ColorSequence.new(Color3.fromRGB(255, 222, 175), C.orange)
		liveDot.BackgroundColor3 = C.green
		liveStroke.Color = C.green
		panel.Size = normalPanelSize
		panel.BackgroundTransparency = uiSettings.panelOpacity / 100
		if statusBar then statusBar.Visible = uiSettings.showStatusBar end
	end
end

minimizeBtn.Activated:Connect(function()
	setMinimized(not minimized)
	notify(minimized and "Panel minimized" or "Panel restored", minimized and C.orange or C.green)
end)
addPressFeedback(minimizeBtn)

closeBtn.Activated:Connect(function()
	minimized = false
	if rail then rail.Visible = false end
	if content then content.Visible = false end
	if statusBar then statusBar.Visible = false end
	normalPanelSize = panel.Size
	notify("Panel hidden · press RightShift to show", C.red)
	animatePanelClose(panel)
end)
addPressFeedback(closeBtn)

-- Dedicated title drag zone: it never overlaps LIVE or the window controls.
dragZone = Instance.new("TextButton")
dragZone.Name = "DragZone"
dragZone.Text = ""
dragZone.AutoButtonColor = false
dragZone.BackgroundTransparency = 1
dragZone.BorderSizePixel = 0
dragZone.Position = UDim2.new(0, 0, 0, 0)
dragZone.Size = UDim2.new(0.70, 0, 1, 0)
dragZone.ZIndex = 29
dragZone.Parent = titleBar
makeDraggable(panel, dragZone)

railHeader = bevelFrame(panel, C.brown, 0.82, "RailHeader")
railHeader.Position = UDim2.new(0.018, 0, 0, 61)
railHeader.Size = UDim2.new(0.225, 0, 0, 30)
railHeader.ZIndex = 15
makeStudIcon(railHeader, "🌱", 22, 6, -11, 18, C.dark)
makeText(railHeader, "GARDEN MENU", Color3.fromRGB(255, 240, 194), UDim2.new(0, 34, 0.04, 0), UDim2.new(1, -40, 0.90, 0), 1.6, 20)

rail = Instance.new("Frame")
rail.Name = "Rail"
rail.Position = UDim2.new(0.018, 0, 0, 99)
rail.Size = UDim2.new(0.225, 0, 1, -130)
rail.BackgroundTransparency = 1
rail.ClipsDescendants = false
rail.ZIndex = 15
rail.Parent = panel
railList = Instance.new("UIListLayout")
railList.Padding = UDim.new(0, 8)
railList.SortOrder = Enum.SortOrder.LayoutOrder
railList.Parent = rail

content = Instance.new("Frame")
content.Name = "Content"
content.Position = UDim2.new(0.258, 0, 0, 61)
content.Size = UDim2.new(0.724, 0, 1, -92)
content.BackgroundTransparency = 1
content.ClipsDescendants = true
content.ZIndex = 10
content.Parent = panel

toolbar = bevelFrame(content, C.dark, 0.86, "Toolbar")
toolbar.Size = UDim2.new(1, 0, 0, 40)
toolbar.Position = UDim2.new(0, 0, 0, 0)
toolbar.ZIndex = 12
makeStudIcon(toolbar, "rbxassetid://101953044632807", 28, 8, -14, 15, C.dark)
toolbarTitle = makeText(toolbar, "Dashboard  /  Overview", Color3.fromRGB(236, 240, 244), UDim2.new(0, 43, 0.08, 0), UDim2.new(0.46, 0, 0.84, 0), 1.5, 16)
toolbarHint = makeText(toolbar, "SCROLL TO EXPLORE", Color3.fromRGB(166, 176, 188), UDim2.new(0.50, 0, 0.08, 0), UDim2.new(0.34, -116, 0.84, 0), 1.2, 14, "right")
toolbarLine = Instance.new("Frame")
toolbarLine.Name = "AccentLine"
toolbarLine.BackgroundColor3 = C.green
toolbarLine.BorderSizePixel = 0
toolbarLine.Position = UDim2.new(0, 8, 1, -3)
toolbarLine.Size = UDim2.new(0.34, 0, 0, 3)
toolbarLine.ZIndex = 16
toolbarLine.Parent = toolbar
scrollTopBtn, scrollTopFace = bevelButton(toolbar, C.blue, "ScrollTop")
scrollTopBtn.Size = UDim2.fromOffset(102, 32)
scrollTopBtn.AnchorPoint = Vector2.new(1, 0.5)
scrollTopBtn.Position = UDim2.new(1, -6, 0.5, 0)
scrollTopBtn.ZIndex = 16
scrollTopFace.ZIndex = 17
makeText(scrollTopFace, "↑  TOP", Color3.new(1, 1, 1), UDim2.fromScale(0.04, 0.04), UDim2.new(0.92, 0, 0.90, 0), 1.8, 18, "center")
scrollTopBtn.Active = true
scrollTopBtn.Selectable = true
function scrollToTop()
	if not pageScroll or not pageScroll.Parent then return end
	refreshScrollCanvas()
	pageScroll.ScrollingEnabled = true
	pageScroll.CanvasPosition = Vector2.new(0, 0)
	task.defer(function()
		if pageScroll.Parent then pageScroll.CanvasPosition = Vector2.new(0, 0) end
	end)
	notify("Scrolled to top", C.blue)
end
scrollTopBtn.Activated:Connect(scrollToTop)
addPressFeedback(scrollTopBtn)

statusBar = bevelFrame(panel, C.dark, 0.85, "StatusBar")
statusBar.Size = UDim2.new(0.96, 0, 0, 27)
statusBar.Position = UDim2.new(0.02, 0, 1, -31)
statusBar.Visible = uiSettings.showStatusBar
statusBar.ZIndex = 18
statusText = makeText(statusBar, "Bahay Kubo Garden v6.7  •  RightShift show/hide  •  0 active", Color3.fromRGB(188, 194, 200), UDim2.new(0.02, 0, 0.05, 0), UDim2.new(0.96, 0, 0.90, 0), 1.1, 19, "center", 13)
statusCap = Instance.new("UITextSizeConstraint")
statusCap.MaxTextSize = 13
statusCap.MinTextSize = 10
statusCap.Parent = statusText

subRow = Instance.new("Frame")
subRow.Name = "SubTabs"
subRow.BackgroundTransparency = 1
subRow.Position = UDim2.new(0, 0, 0, 46)
subRow.Size = UDim2.new(1, 0, 0, 44)
subRow.ZIndex = 12
subRow.Parent = content
subGrid = Instance.new("UIGridLayout")
subGrid.CellSize = UDim2.new(0.235, 0, 0, 38)
subGrid.CellPadding = UDim2.new(0.02, 0, 0, 6)
subGrid.FillDirectionMaxCells = 4
subGrid.SortOrder = Enum.SortOrder.LayoutOrder
subGrid.Parent = subRow
subGrid:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	local h = math.max(38, subGrid.AbsoluteContentSize.Y)
	subRow.Size = UDim2.new(1, 0, 0, h)
	pageScroll.Position = UDim2.new(0, 0, 0, 46 + h + 8)
	pageScroll.Size = UDim2.new(1, 0, 1, -(46 + h + 8))
end)

pageScroll = Instance.new("ScrollingFrame")
pageScroll.Name = "PageScroll"
pageScroll.BackgroundTransparency = 1
pageScroll.AutomaticCanvasSize = Enum.AutomaticSize.None
pageScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
pageScroll.ScrollBarThickness = 7
pageScroll.ScrollBarImageColor3 = C.green
pageScroll.ScrollingDirection = Enum.ScrollingDirection.Y
pageScroll.ScrollingEnabled = true
pageScroll.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
pageScroll.ClipsDescendants = true
pageScroll.Position = UDim2.new(0, 0, 0, 94)
pageScroll.Size = UDim2.new(1, 0, 1, -94)
pageScroll.ZIndex = 11
pageScroll.Parent = content
pageList = Instance.new("UIListLayout")
pageList.SortOrder = Enum.SortOrder.LayoutOrder
pageList.Padding = UDim.new(0, 8)
pageList.Parent = pageScroll
function refreshScrollCanvas()
	local contentY = pageList.AbsoluteContentSize.Y + 18
	local viewY = pageScroll.AbsoluteWindowSize.Y
	pageScroll.CanvasSize = UDim2.fromOffset(0, math.max(viewY, contentY))
end
pageList:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(refreshScrollCanvas)
pageScroll:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(refreshScrollCanvas)
task.defer(refreshScrollCanvas)
pageScroll:SetAttribute("KeyScrollHelper", true)
pageScroll.InputBegan:Connect(function(io)
	if io.UserInputType ~= Enum.UserInputType.Keyboard then return end
	local y = pageScroll.CanvasPosition.Y
	local step = math.max(120, pageScroll.AbsoluteWindowSize.Y * 0.72)
	if io.KeyCode == Enum.KeyCode.Home then
		pageScroll.CanvasPosition = Vector2.new(0, 0)
	elseif io.KeyCode == Enum.KeyCode.End then
		pageScroll.CanvasPosition = Vector2.new(0, math.max(0, pageScroll.AbsoluteCanvasSize.Y - pageScroll.AbsoluteWindowSize.Y))
	elseif io.KeyCode == Enum.KeyCode.PageDown then
		pageScroll.CanvasPosition = Vector2.new(0, y + step)
	elseif io.KeyCode == Enum.KeyCode.PageUp then
		pageScroll.CanvasPosition = Vector2.new(0, math.max(0, y - step))
	end
end)

pageFrames = {}
subTitles = {}
railBtns = {}
subIcons = {
	overview="rbxassetid://101953044632807", activity="⚡", profiles="★", alerts="!", index="◆",
	harvest="rbxassetid://84998465111718", water="rbxassetid://84697600263846", sell="₱", rewards="★",
	seeds="rbxassetid://120628031716892", pets="🐾", store="▣", merchant="🛒", upgrades="⬆", eggs="🥚", other="⋯",
	uiSettings="⚙", filters="⌕", aboutSettings="ⓘ"
}

function makeRailBtn(name, icon)
	local b, f = bevelButton(rail, C.gray, "Rail_" .. name)
	b.Size = UDim2.new(1, 0, 0, 54)
	b.ZIndex = 17
	f.ZIndex = 18
	b.Text = ""
	makeStudIcon(f, icon, 32, 7, -16, 20, C.dark)
	local title = makeText(f, name, Color3.new(1, 1, 1), UDim2.new(0, 48, 0.06, 0), UDim2.new(1, -60, 0.88, 0), 2.0, 21, "left", 17)
	title.TextTruncate = Enum.TextTruncate.AtEnd
	railBtns[name] = b
	addPressFeedback(b)
	return b
end
makeRailBtn("Dashboard", "rbxassetid://77830885604568")
makeRailBtn("About", "?")
makeRailBtn("Main", "rbxassetid://84998465111718")
makeRailBtn("Stocks", "rbxassetid://120628031716892")
makeRailBtn("Settings", "⚙")

currentTopTab = "Dashboard"
currentSubTab = "overview"

function showTop(tab)
	currentTopTab = tab
	toolbarTitle.Text = tab .. "  /  " .. ((tab == "Dashboard" and "Overview") or (tab == "Main" and "Harvest") or (tab == "Stocks" and "Seeds") or (tab == "Settings" and "UI Settings") or "About")
	for _, c in pairs(subRow:GetChildren()) do
		if c:IsA("TextButton") then c:Destroy() end
	end
	local subs = {}
	if tab == "Dashboard" then subs = { "overview", "activity", "profiles", "alerts", "index" } end
	if tab == "Main" then subs = { "harvest", "water", "sell", "rewards" } end
	if tab == "Stocks" then subs = { "seeds", "pets", "store", "merchant", "upgrades", "eggs", "other" } end
	if tab == "Settings" then subs = { "uiSettings", "filters", "aboutSettings" } end
	local rows = math.max(1, math.ceil(#subs / 4))
	local subHeight = rows * 38 + (rows - 1) * 6
	subRow.Size = UDim2.new(1, 0, 0, subHeight)
	pageScroll.Position = UDim2.new(0, 0, 0, 46 + subHeight + 8)
	pageScroll.Size = UDim2.new(1, 0, 1, -(46 + subHeight + 8))
	for _, sid in subs do
		local b, f = bevelButton(subRow, C.orange, "Sub_" .. sid)
		b.LayoutOrder = table.find(subs, sid) or 1
		b.Text = ""
		makeStudIcon(f, subIcons[sid] or "◆", 24, 7, -12, 6, C.dark)
		local subLabel = makeText(f, subTitles[sid], Color3.new(1, 1, 1), UDim2.new(0, 36, 0.08, 0), UDim2.new(1, -42, 0.84, 0), 2.2, 7, "center")
		subLabel.TextTruncate = Enum.TextTruncate.AtEnd
		b.MouseButton1Click:Connect(function()
			currentSubTab = sid
			toolbarTitle.Text = tab .. "  /  " .. (subTitles[sid] or sid)
			for _, other in pairs(subRow:GetChildren()) do
				if other:IsA("TextButton") then
					other.Face.UIGradient.Color = ColorSequence.new(Color3.fromRGB(255, 232, 200), C.orange)
				end
			end
			f.UIGradient.Color = ColorSequence.new(Color3.fromRGB(255, 245, 200), C.gold)
			for pid, fr in pairs(pageFrames) do
				fr.Visible = pid == sid
				fr.Size = UDim2.new(1, -10, 0, 0)
				fr.AutomaticSize = pid == sid and Enum.AutomaticSize.Y or Enum.AutomaticSize.None
			end
			pageScroll.CanvasPosition = Vector2.new(0, 0)
			if openDropdown then closeDropdown() end
		end)
		addPressFeedback(b)
	end
	local first = subs[1] or "about"
	for pid, fr in pairs(pageFrames) do
		fr.Visible = pid == first
		fr.Size = UDim2.new(1, -10, 0, 0)
		fr.AutomaticSize = pid == first and Enum.AutomaticSize.Y or Enum.AutomaticSize.None
	end
	if subs[1] then
		local fb = subRow:FindFirstChild("Sub_" .. subs[1])
		if fb then
			fb.Face.UIGradient.Color = ColorSequence.new(Color3.fromRGB(255, 245, 200), C.gold)
		end
	end
	for name, b in pairs(railBtns) do
		if name == tab then
			b.Face.UIGradient.Color = ColorSequence.new(Color3.fromRGB(225, 255, 215), C.green)
		else
			b.Face.UIGradient.Color = ColorSequence.new(Color3.fromRGB(180, 184, 188), C.gray)
		end
	end
end

for name, b in pairs(railBtns) do
	b.MouseButton1Click:Connect(function()
		closeDropdown()
		showTop(name)
	end)
end

subTitles.about = "About"
subTitles.overview = "Overview"
subTitles.activity = "Activity"
subTitles.profiles = "Profiles"
subTitles.alerts = "Alerts"
subTitles.index = "Garden Index"
subTitles.uiSettings = "UI Settings"
subTitles.filters = "Defaults"
subTitles.aboutSettings = "Panel Info"
subTitles.harvest = "Harvest"
subTitles.water = "Water"
subTitles.sell = "Sell"
subTitles.rewards = "Rewards"
subTitles.seeds = "Seeds"
subTitles.pets = "Pets"
subTitles.store = "Store"
subTitles.merchant = "Trade"
subTitles.upgrades = "Upgrades"
subTitles.eggs = "Eggs"
subTitles.other = "Other"

function newPage(id)
	local f = Instance.new("Frame")
	f.Name = "Page_" .. id
	f.BackgroundTransparency = 1
	f.Size = UDim2.new(1, -16, 0, 0)
	f.AutomaticSize = Enum.AutomaticSize.Y
	f.ClipsDescendants = false
	f.Visible = false
	f.ZIndex = 12
	f.Parent = pageScroll
	local ll = Instance.new("UIListLayout")
	ll.Padding = UDim.new(0, 8)
	ll.SortOrder = Enum.SortOrder.LayoutOrder
	ll.Parent = f
	pageFrames[id] = f
	return f
end

function section(f, text, order)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.Text = tostring(text)
	l.TextColor3 = C.gold
	l.TextScaled = false
	l.TextSize = 18
	l.TextYAlignment = Enum.TextYAlignment.Center
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Size = UDim2.new(1, 0, 0, 26)
	l.LayoutOrder = order
	l.ZIndex = 4
	l.Parent = f
	local s = Instance.new("UIStroke")
	s.Color = Color3.new(0, 0, 0)
	s.Thickness = 2
	s.Parent = l
end

function para(f, text, order, h)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamMedium
	l.Text = tostring(text)
	l.TextColor3 = Color3.fromRGB(226, 230, 236)
	l.TextScaled = false
	l.TextSize = 15
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Top
	l.TextWrapped = true
	l.Size = UDim2.new(1, 0, 0, h or 60)
	l.LayoutOrder = order
	l.ZIndex = 4
	l.Parent = f
	local s = Instance.new("UIStroke")
	s.Color = Color3.new(0, 0, 0)
	s.Thickness = 2
	s.Parent = l
	local cap = Instance.new("UITextSizeConstraint")
	cap.MaxTextSize = 18
	cap.MinTextSize = 12
	cap.Parent = l
end

-- ==DASHBOARD_PAGES==
overview = newPage("overview")
makeHeader(overview, "Garden Dashboard", C.leaf, "rbxassetid://101953044632807")

-- Status ribbon matching the supplied reference image: compact, high-contrast and information-first.
statusRibbon = Instance.new("Frame")
statusRibbon.Name = "ReferenceStatusRibbon"
statusRibbon.Size = UDim2.new(1, 0, 0, 34)
statusRibbon.BackgroundColor3 = C.dark
statusRibbon.BackgroundTransparency = 0.12
statusRibbon.BorderSizePixel = 0
statusRibbon.ZIndex = 5
statusRibbon.Parent = overview
rbStroke = Instance.new("UIStroke")
rbStroke.Color = Color3.new(0, 0, 0)
rbStroke.Thickness = 3
rbStroke.Parent = statusRibbon
rbIcon = Instance.new("ImageLabel")
rbIcon.BackgroundTransparency = 1
rbIcon.Image = "rbxassetid://84697600263846"
rbIcon.Size = UDim2.fromOffset(24, 24)
rbIcon.Position = UDim2.new(0, 8, 0.5, -12)
rbIcon.ScaleType = Enum.ScaleType.Fit
rbIcon.ZIndex = 6
rbIcon.Parent = statusRibbon
makeStudIcon(statusRibbon, "🌱", 24, 6, -12, 8, C.dark)
rbIcon.Visible = false
makeText(statusRibbon, "GARDEN", Color3.fromRGB(238, 242, 246), UDim2.new(0, 38, 0.08, 0), UDim2.new(0.28, 0, 0.84, 0), 1.6, 6)
rbRight = makeText(statusRibbon, "READY  •  DRAG TO MOVE  •  TOP = FIRST PAGE", Color3.fromRGB(204, 210, 218), UDim2.new(0.98, 0, 0.08, 0), UDim2.new(0.66, 0, 0.84, 0), 1.2, 6, "right")

function rightValueLabel(row)
	local labels = {}
	for _, d in row:GetChildren() do
		if d:IsA("TextLabel") then table.insert(labels, d) end
	end
	return labels[#labels]
end
dashActive = rightValueLabel(makeStat(overview, "Active Toggles", "0", C.green))
dashDrops = rightValueLabel(makeStat(overview, "Open Dropdown", "None", C.sky))
dashMode = rightValueLabel(makeStat(overview, "Panel Mode", "Full", C.purple))
rightValueLabel(makeStat(overview, "Tip", "Use Profiles to set multiple switches", C.gold))
section(overview, "Quick Actions", 1)
makeActionButton(overview, "🌱 Farming Profile", C.green, function()
	uiSettings.silent = true
	local targets = { autoHarvest=true, autoRefill=true, autoSellAll=true,  autoBestPets=true }
	for key, setter in pairs(ToggleSetters) do if isMasterTarget(key) then setter(targets[key] == true) end end
	uiSettings.silent = false
	notify("Farming profile applied", C.green)
end)
makeActionButton(overview, "🛒 Shopping Profile", C.orange, function()
	uiSettings.silent = true
	local targets = { autoBuySeeds=true, autoBuyEggs=true, autoBuyGear=true, autoBuyBasics=true, autoBuyDecor=true, autoBuyMerchant=true }
	for key, setter in pairs(ToggleSetters) do if isMasterTarget(key) then setter(targets[key] == true) end end
	uiSettings.silent = false
	notify("Shopping profile applied", C.orange)
end)
makeActionButton(overview, "⛔ Everything Off", C.red, function()
	uiSettings.silent = true
	for key, setter in pairs(ToggleSetters) do if isMasterTarget(key) then setter(false) end end
	uiSettings.silent = false
	notify("Automation switches cleared", C.red)
end)
makeActionButton(overview, "↻ Refresh UI Status", C.blue, function()
	notify("UI status refreshed", C.blue)
end)
makeActionButton(overview, "▢ Close Open Dropdown", C.gray, function()
	if openDropdown then closeDropdown(); notify("Dropdown closed", C.gray) else notify("No dropdown is open", C.gray) end
end)
para(overview, "Tip: use RightShift to show or hide the panel, the — button to minimize, and TOP to return to the beginning of any long list. Dropdowns close automatically when you switch sections.", 20, 46)

activity = newPage("activity")
makeHeader(activity, "Live Activity", C.sky, "rbxassetid://101953044632807")
para(activity, "Live toggle readout. Only active panel controls are marked ON.", 1, 48)
activityRows = {}
function activityRow(key, label)
	local row = makeDarkRow(activity, label, "OFF", C.gray, 36)
	local value = row:FindFirstChildWhichIsA("TextLabel")
	-- makeDarkRow creates two labels; use the rightmost one for the live state.
	local labels = {}
	for _, d in row:GetChildren() do if d:IsA("TextLabel") then table.insert(labels, d) end end
	value = labels[#labels]
	activityRows[key] = value
end
for _, pair in { {"autoHarvest","Auto Harvest"}, {"autoPayBill","Auto Pay Bill"}, {"autoSellAll","Auto Sell"}, {"autoBuySeeds","Auto Buy Seeds"}, {"autoBuyEggs","Auto Buy Eggs"}, {"autoUpgradePlot","Plot Upgrade"}, {"autoPlaceAll","Auto Place Eggs"}, {"antiAFK","Anti-AFK"} } do
	activityRow(pair[1], pair[2])
end

profiles = newPage("profiles")
makeHeader(profiles, "Automation Profiles", C.purple)
para(profiles, "Profiles only change this panel's toggle states. They do not add new remotes or bypass server validation.", 1, 56)
makeActionButton(profiles, "🌱 Farming", C.green, function()
	uiSettings.silent = true
	local t={autoHarvest=true,autoRefill=true,autoSellAll=true,autoBestPets=true}
	for k,sr in pairs(ToggleSetters) do if isMasterTarget(k) then sr(t[k] == true) end end
	uiSettings.silent=false
	notify("Farming profile applied", C.green)
end)
makeActionButton(profiles, "🛒 Shopping", C.orange, function()
	uiSettings.silent = true
	local t={autoBuySeeds=true,autoBuyEggs=true,autoBuyGear=true,autoBuyBasics=true,autoBuyDecor=true,autoBuyMerchant=true}
	for k,sr in pairs(ToggleSetters) do if isMasterTarget(k) then sr(t[k] == true) end end
	uiSettings.silent=false
	notify("Shopping profile applied", C.orange)
end)
makeActionButton(profiles, "💤 Low Activity / Safe UI", C.blue, function()
	uiSettings.silent = true
	local t={autoHarvest=true,autoRefill=false,autoSellAll=false,autoSellSelected=false,autoPayBill=true,autoBestPets=false}
	for k,sr in pairs(ToggleSetters) do if isMasterTarget(k) then sr(t[k] == true) end end
	uiSettings.silent=false
	notify("Low activity profile applied", C.blue)
end)

alerts = newPage("alerts")
makeHeader(alerts, "Garden Alerts", C.gold)
makeToggle(alerts, "Rare Crop Alert", false, "alertRareCrop")
makeToggle(alerts, "Mutation Alert", false, "alertMutation")
makeToggle(alerts, "Shop Restock Alert", false, "alertRestock")
makeToggle(alerts, "Egg Ready Alert", false, "alertEggReady")
makeToggle(alerts, "Low Water Alert", false, "alertLowWater")
makeToggle(alerts, "Low Money Warning", false, "alertLowMoney")

indexPage = newPage("index")
makeHeader(indexPage, "Garden Index", C.gold, "rbxassetid://84998465111718")
para(indexPage, "Browse the registered crop, mutation, and egg catalogs from one page.", 1, 48)
commonCount, rareCount, mythicCount = 0, 0, 0
for _, crop in CROPS do
	if crop.rarity == "Common" then commonCount += 1 end
	if crop.rarity == "Rare" then rareCount += 1 end
	if crop.rarity == "Mythic" then mythicCount += 1 end
end
makeStat(indexPage, "Crops", tostring(#CROPS) .. " registered", C.green)
makeStat(indexPage, "Mutations", tostring(#MUTATIONS) .. " registered", C.purple)
makeStat(indexPage, "Egg Types", tostring(#EGGS) .. " registered", C.pink)
makeStat(indexPage, "Rare + Mythic", string.format("%d rare  |  %d mythic", rareCount, mythicCount), C.gold)
makeDropdown(indexPage, "Crop Catalog", CROPS)
makeDropdown(indexPage, "Mutation Catalog", MUTATIONS)
makeDropdown(indexPage, "Egg Catalog", EGGS)

-- ==SETTINGS_PAGES==
uiSettingsPage = newPage("uiSettings")
makeHeader(uiSettingsPage, "UI Settings", C.gray)
section(uiSettingsPage, "Appearance", 1)
makeToggle(uiSettingsPage, "Notifications", false, "notifications")
makeToggle(uiSettingsPage, "Show Status Bar", false, "showStatusBar")
makeToggle(uiSettingsPage, "Auto Close Dropdowns", false, "autoCloseDropdowns")
makeToggle(uiSettingsPage, "Compact Layout", false, "compactMode")
makeToggle(uiSettingsPage, "Show Helper Text", true, "showHints")
makeToggle(uiSettingsPage, "High Contrast Text", false, "highContrast")
makeToggle(uiSettingsPage, "Show Icons", true, "showIconLabels")
makeToggle(uiSettingsPage, "Stud Icon Style", true, "studIconStyle")
makeToggle(uiSettingsPage, "Lock Panel Position", false, "lockPanelPosition")
makeSlider(uiSettingsPage, "Panel Opacity", 0, 60, 40, "panelOpacity", function(v) return string.format("%d%%", v) end)
makeSlider(uiSettingsPage, "Toast Duration", 1, 5, 2.5, "toastDuration", function(v) return string.format("%.1fs", v) end)
makeSlider(uiSettingsPage, "Dropdown Height", 220, 520, 330, "dropdownHeight", function(v) return string.format("%dpx", v) end)
section(uiSettingsPage, "Layout Tools", 20)
makeActionButton(uiSettingsPage, "Center Panel", C.blue, function()
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	notify("Panel centered", C.blue)
end)
makeActionButton(uiSettingsPage, "Reset UI View", C.orange, function()
	closeDropdown()
	setMinimized(false)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	pageScroll.CanvasPosition = Vector2.new(0, 0)
	showTop(currentTopTab)
	notify("UI view reset", C.orange)
end)
makeActionButton(uiSettingsPage, "Apply UI Settings", C.green, function()
	panel.BackgroundTransparency = uiSettings.panelOpacity / 100
	statusBar.Visible = uiSettings.showStatusBar and not minimized
	toolbarHint.Visible = uiSettings.showHints
	for _, iconBox in ipairs(gui:GetDescendants()) do
		if iconBox.Name == "StudIcon" and iconBox:IsA("Frame") then
			iconBox.Visible = uiSettings.showIconLabels ~= false
		end
		if iconBox.Name == "Studs" and iconBox:IsA("ImageLabel") then
			iconBox.Visible = uiSettings.studIconStyle ~= false
		end
		if iconBox.Name == "DragGrip" and iconBox:IsA("Frame") then
			iconBox.Visible = uiSettings.showIconLabels ~= false
		end
	end
	for _, d in ipairs(gui:GetDescendants()) do
		if d.Name == "Body" and d:IsA("Frame") then
			d.Size = UDim2.new(1, 0, 0, uiSettings.dropdownHeight)
			local wrap = d.Parent
			if wrap and wrap:IsA("Frame") and d.Visible then
				wrap.Size = UDim2.new(1, 0, 0, 54 + uiSettings.dropdownHeight)
			end
		end
	end
	local compactToggleHeight = uiSettings.compactMode and 40 or 46
	local compactActionHeight = uiSettings.compactMode and 38 or 44
	for _, d in ipairs(gui:GetDescendants()) do
		if d:IsA("TextButton") then
			if d.Name:sub(1, 7) == "Toggle_" then d.Size = UDim2.new(1, 0, 0, compactToggleHeight) end
			if d.Name:sub(1, 7) == "Action_" then d.Size = UDim2.new(1, 0, 0, compactActionHeight) end
		end
		if d:IsA("TextLabel") and uiSettings.highContrast then
			local c = d.TextColor3
			if c.R + c.G + c.B > 1.80 then
				d.TextColor3 = Color3.fromRGB(246, 246, 246)
			end
		end
	end
	notify("UI settings applied", C.green)
end)

filters = newPage("filters")
makeHeader(filters, "Default Filters", C.blue)
makeInput(filters, "Minimum Crop Weight", "1.15")
makeToggle(filters, "Prefer Rare Mutations", false, "preferRareMutations")
makeToggle(filters, "Ignore Common Drops", false, "ignoreCommonDrops")
makeToggle(filters, "Only Buy Needed Seeds", false, "buyNeededSeeds")
makeToggle(filters, "Only Hatch Selected Eggs", false, "hatchSelectedEggs")

aboutSettings = newPage("aboutSettings")
makeHeader(aboutSettings, "Panel Info", C.gray, "rbxassetid://101953044632807")
makeStat(aboutSettings, "Version", "6.6 Typography / Alignment", C.gold)
makeStat(aboutSettings, "Panel Type", "Client UI / controls", C.sky)
makeStat(aboutSettings, "Hotkey", "RightShift", C.green)
makeStat(aboutSettings, "Window", "— minimize  |  × hide", C.orange)
makeStat(aboutSettings, "Automation API", "Not included in UI-only upgrade", C.gray)
para(aboutSettings, "Version 6.4 focuses on cleaner spacing, readable text, compact window controls, stronger tab layout, protected scrolling, richer Settings, and a more useful About guide. The UI remains separate from game-specific server logic.", 5, 92)

-- ==ABOUT_PAGE==
about = newPage("about")
section(about, "Welcome", 1)
para(about, "Bahay Kubo Garden is a focused garden control center built around fast navigation, readable controls, and a compact farming workflow. The panel groups the garden, economy, settings, alerts, and index tools into a single interface.", 2, 78)
makeStat(about, "Build Focus", "Harvest + Water automation refresh", C.green)
makeStat(about, "Interaction", "Static, compact, scroll-safe UI", C.sky)

section(about, "Navigation", 3)
para(about, "Dashboard is the overview hub. Main contains Harvest, Water, Sell, and Rewards. Stocks contains Seeds, Pets, Store, Merchant, Upgrades, Eggs, and Other. Settings contains UI controls and default filters. Use the left navigation or the tab row to switch sections.", 4, 86)

section(about, "Window Controls", 5)
makeStat(about, "—", "Minimize the panel", C.orange)
makeStat(about, "×", "Hide the panel; press RightShift to show it again", C.red)
makeStat(about, "RightShift", "Show / hide the panel", C.green)

section(about, "Controls", 9)
para(about, "Toggle rows show their current state on the right. Dropdowns open a dedicated picker with search and selection controls. Sliders can be dragged or adjusted with the keyboard arrows. Text fields accept direct input and remain aligned with the rest of the page.", 10, 78)

section(about, "Dashboard Tools", 11)
para(about, "Activity shows active controls. Profiles let you apply grouped farming settings. Alerts provide optional warnings for rare crops, mutations, restocks, eggs, water, and money. Garden Index organizes the registered crop, mutation, and egg data.", 12, 82)

section(about, "UI / UX", 13)
para(about, "The interface uses a consistent card height, safe text truncation, centered tab labels, responsive spacing, a dedicated window-control group, and a protected scrolling region so long pages do not cover the tab area.", 14, 78)

section(about, "Troubleshooting", 15)
para(about, "When the panel layout feels crowded, open Settings and use Center Panel, Reset UI View, Compact Layout, or the Dropdown Height slider. When a page is long, use the mouse wheel, scrollbar, or the ↑ TOP button. RightShift always remains the main show / hide shortcut.", 16, 82)

section(about, "Important Notes", 17)
para(about, "This file provides the panel UI and its local control state. Game-specific actions still depend on the underlying game logic, available instances, and any connected remotes. The panel does not assume a server feature exists just because a UI control is present.", 18, 82)

section(about, "Page Guide", 19)
para(about, "Garden Status is a simple readiness ribbon. Live Activity is the live toggle monitor. Garden Index is the catalog browser. Panel Info is the quick reference for shortcuts, controls, and layout behavior.", 20, 74)

section(about, "Static UI Mode", 21)
para(about, "This build intentionally removes tween and fade animation. Minimize, restore, close, open, notifications, and button state changes happen immediately.", 22, 70)

section(about, "Text Safety", 23)
para(about, "Rows keep labels and right-side values in separate areas, long text is truncated or wrapped inside its own region, and stock entries no longer show quantity badges.", 24, 70)

section(about, "What's New", 25)
para(about, "Harvest automation now uses a direct ProximityPrompt trigger instead of E-key hold simulation. Safe Nearby stays inside 10 studs, while Instant TP and Tween TP can reach ripe fruit anywhere on the local player's farm and return safely afterward.", 26, 92)
para(about, "Water automation now uses the local Shared.Remotes.Farm.WaterPlant RemoteEvent with each plant's live world position. Auto Water Selected targets only the crops selected in the picker; Auto Water All processes every thirsty plant one by one with a 0.5 second cycle and returns to the starting position.", 27, 96)
para(about, "The panel UI also adds clearer automation status cards, more explicit range/trigger descriptions, stronger visual hierarchy, and better at-a-glance guidance for Harvest and Water pages.", 28, 76)

section(about, "Automation Notes", 29)
makeStat(about, "Harvest Trigger", "Direct prompt trigger", C.green)
makeStat(about, "Safe Harvest", "10-stud nearby range", C.sky)
makeStat(about, "Water Selected", "TP + remote at live plant position", C.purple)
makeStat(about, "Water Timing", "0.5s per plant", C.orange)

section(about, "Version", 33)
makeStat(about, "Version", "6.8 Harvest + Water refresh", C.gold)
makeStat(about, "Theme", "Bahay Kubo Garden", C.green)

section(about, "Quick Start", 21)
para(about, "Start in Dashboard for the overview, use Main for garden actions, Stocks for shop and inventory pages, and Settings for the panel itself. The left rail is the primary navigation and the smaller tab row changes with the selected section.", 22, 82)

section(about, "Window Behavior", 23)
para(about, "The — control collapses the panel to its title bar while keeping the window controls available. The × control hides the panel. RightShift restores a hidden panel or expands a minimized panel. The title drag zone keeps movement separate from the window controls.", 24, 82)

section(about, "Scrolling", 25)
para(about, "Long pages are contained inside a dedicated vertical ScrollingFrame. TOP resets the current page to its first position, while Home, End, PageUp and PageDown provide keyboard navigation when the scrolling area has focus.", 26, 82)

section(about, "Visual System", 27)
para(about, "Stud icon style uses a small textured backing plate behind navigation and section icons so the artwork feels integrated with the blocky garden theme. This is a visual-only setting and can be turned off from Settings without affecting navigation.", 27, 66)
para(about, "Garden green is used for active or positive controls, orange for attention and window actions, blue for navigation helpers, purple for grouped profiles, and red for destructive or stop-style actions. Icons are used where they improve recognition without replacing the label.", 28, 82)

section(about, "Layout Rules", 29)
para(about, "Rows use predictable heights, left-aligned labels, right-aligned values when a value exists, and truncation for long text. Stock rows no longer show inventory quantity badges such as 6, 2, 3, or 27.", 30, 82)

section(about, "Interaction Tips", 31)
para(about, "Click a subtab once to switch pages. Click an open dropdown again to close it. Use the Settings page to tune panel opacity, dropdown height, helper text, compact spacing, contrast, icon visibility, and panel locking. This build uses immediate UI changes with no animation. Changes are reflected immediately in the local UI state.", 32, 84)

section(about, "Performance", 33)
para(about, "The panel keeps status refreshes on a low cadence instead of continuously rebuilding pages. UI rows are created once and visibility is switched when navigating. This keeps the interface predictable while reducing unnecessary layout churn.", 34, 84)

section(about, "Troubleshooting", 35)
para(about, "When a page looks crowded, close any open dropdown, use TOP, or adjust Dropdown Height. When a panel is hidden, press RightShift. When the panel has moved off-center, use Center Panel or Reset UI View from Settings.", 36, 84)

section(about, "Reference Ribbon", 37)
para(about, "The Dashboard keeps a compact garden-status ribbon with a stud-backed garden icon, concise status messaging, and a clear information-first layout.", 38, 82)

section(about, "Design Goal", 39)
para(about, "The current UI is designed as a compact garden control center with stud-backed icons, clearer navigation, stronger section separation, larger readable labels, safer scrolling, and predictable static interactions.", 40, 82)

-- ==MAIN_PAGES==
harvest = newPage("harvest")
makeHeader(harvest, "Harvest", C.leaf, "rbxassetid://84998465111718")

-- Player farm check: always resolve the farm owned by the player using the UI
-- (Farm_<UserId>) instead of any hardcoded farm such as Farm_8498254452.
function getMyFarm()
	local farms = workspace:FindFirstChild("ActiveFarms")
	if not farms then return nil end
	local mine = farms:FindFirstChild("Farm_" .. Players.LocalPlayer.UserId)
	if mine then return mine end
	for _, farm in ipairs(farms:GetChildren()) do
		if farm:GetAttribute("OwnerUserId") == Players.LocalPlayer.UserId then
			return farm
		end
	end
	return nil
end

makeStat(harvest, "Money", "12,450 pesos", C.gold, "rbxassetid://84697600263846")
farmStat = rightValueLabel(makeStat(harvest, "Your Farm", "Checking...", C.green))
plantStat = rightValueLabel(makeStat(harvest, "Plants", "0", C.sky))
harvestStat = rightValueLabel(makeStat(harvest, "Harvested", "0 crops", Color3.new(1, 1, 1)))
ripeStat = rightValueLabel(makeStat(harvest, "Ripe Fruits", "0", C.green))

function refreshFarmStats()
	local farm = getMyFarm()
	if not farm then
		farmStat.Text = "None — claim a plot"
		farmStat.TextColor3 = C.red
		plantStat.Text = "0"
		ripeStat.Text = "0"
		return
	end
	farmStat.Text = farm.Name
	farmStat.TextColor3 = C.green
	local plants = farm:FindFirstChild("Plants")
	if not plants then
		plantStat.Text = "0"
		ripeStat.Text = "0"
		return
	end
	local now = os.time()
	local plantCount, ripeCount = 0, 0
	for _, plant in plants:GetChildren() do
		plantCount += 1
		local fruits = plant:FindFirstChild("Fruits")
		if fruits then
			for _, fruit in fruits:GetChildren() do
				local ripeAt = fruit:GetAttribute("RipeAt")
				if not ripeAt or ripeAt <= now then
					ripeCount += 1
				end
			end
		end
	end
	plantStat.Text = tostring(plantCount)
	ripeStat.Text = tostring(ripeCount) .. " ripe"
end
refreshFarmStats()
makeToggle(harvest, "Auto Harvest Crops", false, "autoHarvest")
makeStat(harvest, "Trigger", "Direct ProximityPrompt — no E/hold simulation", C.green)
makeStat(harvest, "Range", "Safe Nearby = 10 studs  |  TP modes = full own-farm reach", C.sky)
harvestTypeBase, harvestTypeBody, harvestTypeSelection = makeDropdown(harvest, "Harvest Type", {
	{ name = "Safe Harvest Nearby", rarity = "Common", desc = "Stay in place. Harvest ripe fruits within 10 studs, no teleport." },
	{ name = "Instant TP Harvest", rarity = "Rare", desc = "Instantly teleport to ripe fruits anywhere on your own farm, trigger directly, then return." },
	{ name = "Tween TP Harvest", rarity = "Epic", desc = "Tween smoothly to ripe fruits anywhere on your own farm, trigger directly, then return." },
}, { single = true })
makeDropdown(harvest, "Harvest Filter", {
	{ name = "Whitelist", rarity = "Common", desc = "Harvest ONLY crops selected below." },
	{ name = "Blocklist", rarity = "Common", desc = "Harvest everything EXCEPT selected crops." },
}, { single = true })
cropsBase, cropsBody, cropSelection = makeDropdown(harvest, "Crops", CROPS)
makeDarkRow(harvest, nil, "Filters", C.gold, 40)
makeDropdown(harvest, "Mutation", MUTATIONS)
makeInput(harvest, "Min kg to harvest", "1.15")

water = newPage("water")
makeHeader(water, "Water Tree", C.sky)
makeStat(water, "Bill", "0 pesos", C.gold, "rbxassetid://84697600263846")
makeStat(water, "Water Cup", "3/5", Color3.new(1, 1, 1))
makeStat(water, "Water Cup Level", "4", C.purple)
makeToggle(water, "Auto Pay Bill", false, "autoPayBill")
makeToggle(water, "Auto Refill Water", false, "autoRefill")
makeToggle(water, "Inf Water Cup", false, "infCup")
makeToggle(water, "Auto Water Selected Crops", false, "autoWaterSelected")
makeToggle(water, "Auto Water All One By One", false, "autoWaterAll")
makeStat(water, "Water Logic", "TP → live plant position → Farm.WaterPlant:FireServer(position)", C.green)
makeStat(water, "Cycle", "0.5s between plants  |  returns to your starting position", C.sky)
waterCropsBase, waterCropsBody, waterCropSelection = makeDropdown(water, "Crops", CROPS)

sell = newPage("sell")
makeHeader(sell, "Sell", C.gold)
-- Forward declaration: the favorite-sync implementation lives in the SELL_AUTOMATION
-- section at the bottom, but the dropdown needs it the moment crops are picked.
-- applySellFavorites is assigned later before the callback is used.
sellBackpackStat = rightValueLabel(makeStat(sell, "Backpack Crops", "0", C.sky))
makeToggle(sell, "Auto Sell All (when backpack full)", false, "autoSellAll")
-- Picking crops here marks every OTHER backpack crop as a favorite (the game's
-- Sell All keeps favorites), so only the selected crops get sold.
sellCropsBase, sellCropsBody, sellCropSelection = makeDropdown(sell, "Crops to Sell", CROPS, {
	onChange = function(sel)
		pcall(applySellFavorites, sel)
	end,
})
makeToggle(sell, "Auto Sell Selected", false, "autoSellSelected")
sellFullAtInput = makeInput(sell, "Backpack Full At (crops)", "58")
makeToggle(sell, "Auto Sell (every X seconds)", false, "autoSellTimer")
sellSecondsInput = makeInput(sell, "Auto Sell Every (seconds)", "25")
makeActionButton(sell, "Apply Sell Favorites", C.green, function()
	local fired = applySellFavorites() or 0
	notify("Favorites applied — " .. fired .. " update(s) sent", C.green)
end)

rewards = newPage("rewards")
makeHeader(rewards, "Rewards", C.orange, "rbxassetid://77830885604568")
makeToggle(rewards, "Auto Claim Achievements", false, "claimAchievements")
makeToggle(rewards, "Auto Claim Index", false, "claimIndex")
makeToggle(rewards, "Auto Claim Pass", false, "claimPass")
-- ==STOCK_PAGES==
seeds = newPage("seeds")
makeHeader(seeds, "Seeds", C.green, "rbxassetid://120628031716892")
for i = 1, 5 do
	local cropId = CropConfig.ShopLineup[i]
	if cropId then makeStockRow(seeds, cropId .. " Seed") end
end
makeDropdown(seeds, "Seeds to Buy", CROPS)
makeToggle(seeds, "Auto Buy Seeds", false, "autoBuySeeds")

pets = newPage("pets")
makeHeader(pets, "Pet Eggs", C.pink, "rbxassetid://113316632422703")
makeStockRow(pets, "Common Egg")
makeStockRow(pets, "Rare Egg")
makeStockRow(pets, "Bug Egg")
makeStockRow(pets, "Mythical Egg")
makeStockRow(pets, "Ocean Egg")
makeDropdown(pets, "Eggs to Buy", EGGS)
makeToggle(pets, "Auto Buy Eggs", false, "autoBuyEggs")

store = newPage("store")
makeHeader(store, "Supply Store", C.brown)
makeDropdown(store, "Gear to Buy", {
	{ name = "Watering Can", rarity = "Common", desc = "Waters one plot, chance of Wet mutation." },
	{ name = "Sprinkler", rarity = "Rare", desc = "Waters nearby plots automatically." },
	{ name = "Shovel", rarity = "Common", desc = "Digs up plots to replant." },
	{ name = "Fertilizer Bag", rarity = "Epic", desc = "Speeds up crop growth by 50%." },
})
makeToggle(store, "Auto Buy Gear", false, "autoBuyGear")
makeDropdown(store, "Basics to Buy", {
	{ name = "Fertilizer", rarity = "Common", desc = "Single-use growth boost." },
	{ name = "Water Cup", rarity = "Common", desc = "Holds water for the water tree." },
	{ name = "Bug Net", rarity = "Uncommon", desc = "Catches bugs for quest turns." },
	{ name = "Basket", rarity = "Uncommon", desc = "Adds backpack crop slots." },
})
makeToggle(store, "Auto Buy Basics", false, "autoBuyBasics")
makeDropdown(store, "Decorations to Buy", {
	{ name = "Bamboo Fence", rarity = "Common", desc = "Classic nipa-bahay fencing." },
	{ name = "Nipa Lamp", rarity = "Uncommon", desc = "Warm light for night farming." },
	{ name = "Stone Path", rarity = "Common", desc = "Walkway tile for your plot." },
	{ name = "Garden Gnome", rarity = "Legendary", desc = "Lucky charm, +2% sell price." },
})
makeToggle(store, "Auto Buy Decorations", false, "autoBuyDecor")
makeDropdown(store, "VIP to Buy", {
	{ name = "VIP Ticket", rarity = "Legendary", desc = "Permanent 2x pesos from selling." },
	{ name = "Mega Harvest Pass", rarity = "Mythic", desc = "Harvest two plots at once." },
	{ name = "Golden Watering Can", rarity = "Mythic", desc = "Golden mutation chance doubled." },
	{ name = "Millionaire Pass", rarity = "Mythic", desc = "+25% pesos on every sale." },
})
makeToggle(store, "Auto Buy VIP", false, "autoBuyVIP")

merchant = newPage("merchant")
makeHeader(merchant, "Trade", C.purple)
makeStockRow(merchant, "Rare Seed Crate")
makeStockRow(merchant, "Exotic Egg Crate")
makeStockRow(merchant, "Mutated Crop Bundle")
makeStockRow(merchant, "Ancient Tool Chest")
makeStockRow(merchant, "Golden Mango Tree")
makeDropdown(merchant, "Merchant Items", {
	{ name = "Rare Seed Crate", rarity = "Rare", desc = "Six random rare seeds inside." },
	{ name = "Exotic Egg Crate", rarity = "Epic", desc = "Two exotic pet eggs inside." },
	{ name = "Mutated Crop Bundle", rarity = "Legendary", desc = "Pre-mutated crops, instant pesos." },
	{ name = "Ancient Tool Chest", rarity = "Mythic", desc = "One mythic gear, roll the dice." },
	{ name = "Golden Mango Tree", rarity = "Mythic", desc = "Permanent legendary crop plot." },
})
makeToggle(merchant, "Auto Buy Merchant", false, "autoBuyMerchant")

upgrades = newPage("upgrades")
makeHeader(upgrades, "Farm Upgrades", C.orange, "rbxassetid://124300905660565")
makeToggle(upgrades, "Auto Upgrade Plot (if affordable)", false, "autoUpgradePlot")
makeToggle(upgrades, "Auto Upgrade House (if affordable)", false, "autoUpgradeHouse")

eggs = newPage("eggs")
makeHeader(eggs, "Eggs", C.pink, "rbxassetid://113316632422703")
makeStat(eggs, "Unplaced (backpack)", nil, C.sky)
makeStat(eggs, "Ready to hatch", nil, C.green)
makeDropdown(eggs, "Egg to Place", EGGS)
makeToggle(eggs, "Auto Place All Eggs", false, "autoPlaceAll")
makeToggle(eggs, "Auto Place Selected Eggs", false, "autoPlaceSelected")
makeToggle(eggs, "Auto Place All Ready Eggs", false, "autoPlaceReady")

other = newPage("other")
makeHeader(other, "Other Features", C.gray)
makeToggle(other, "Auto Sleep", false, "autoSleep")
makeToggle(other, "Auto Codes (BAHAYKUBO, RELEASE + live codes)", false, "autoCodes")
makeToggle(other, "Anti-AFK", true, "antiAFK")
makeToggle(other, "Auto Equip All Best Pets", false, "autoBestPets")
makeToggle(other, "Farm Setup (claim free plot, skip tutorial)", false, "farmSetup")
-- ==MAIN==
UIS.InputBegan:Connect(function(io, processed)
	if processed then return end
	if io.KeyCode == Enum.KeyCode.RightShift then
		if minimized then
			setMinimized(false)
		elseif panel.Visible then
			animatePanelClose(panel)
		else
			animatePanelOpen(panel)
			statusBar.Visible = uiSettings.showStatusBar
			notify("Panel shown", C.green)
		end
	end
end)

showTop("Dashboard")
notify("Bahay Kubo Garden v6.7 loaded", C.green)

lastStatusTick = 0
RunService.Heartbeat:Connect(function(dt)
	lastStatusTick += dt
	if lastStatusTick < 0.5 then return end
	lastStatusTick = 0
	local enabled = 0
	for key, state in pairs(ToggleState) do
		if state then enabled += 1 end
		local label = activityRows[key]
		if label then
			label.Text = state and "ON" or "OFF"
			label.TextColor3 = state and C.green or C.gray
		end
	end
	dashActive.Text = tostring(enabled)
	dashDrops.Text = openDropdown and "Open" or "None"
	dashMode.Text = minimized and "Minimized" or "Full"
	liveDot.BackgroundColor3 = minimized and C.orange or C.green
	statusText.Text = string.format("Bahay Kubo Garden v6.7  •  RightShift show/hide  •  %d active  •  %s", enabled, os.date("%I:%M:%S %p"))
	refreshFarmStats()
	statusBar.Visible = uiSettings.showStatusBar and not minimized
end)

-- ==HARVEST_AUTOMATION==
-- Auto Harvest scans the local player's own farm (Farm_<UserId>) for ripe fruits of the crops
-- selected in the "Crops" dropdown and triggers their HarvestPrompt (Plants.<Crop>.Fruits.Fruit.HarvestPrompt).
-- Modes: Safe Nearby (range 10), Instant TP (range 10), Tween TP (range 10).
HARVEST_RANGE = 10
-- Harvest tuning: slower/smoother player movement, but a quicker automation loop.
HARVEST_LOOP_DELAY = 0.18
HARVEST_TRIGGER_DELAY = 0.025
HARVEST_TWEEN_SPEED = 16
HARVEST_TWEEN_MIN = 0.10
HARVEST_TWEEN_MAX = 1.00
harvestedTotal = 0

function normCropKey(text)
	return string.gsub(string.lower(tostring(text or "")), "%s", "")
end

function getActiveFarm()
	-- The farm belongs to whoever is using the panel: Farm_<LocalPlayer.UserId>,
	-- but also fall back to the game's own OwnerUserId attribute check (GripoController style).
	local farms = workspace:FindFirstChild("ActiveFarms")
	if not farms then return nil end
	local mine = farms:FindFirstChild("Farm_" .. Players.LocalPlayer.UserId)
	if mine then return mine end
	for _, farm in ipairs(farms:GetChildren()) do
		if farm:GetAttribute("OwnerUserId") == Players.LocalPlayer.UserId then
			return farm
		end
	end
	return nil
end

function currentHarvestMode()
	for name in pairs(harvestTypeSelection) do
		if name == "Instant TP Harvest" then return "instant" end
		if name == "Tween TP Harvest" then return "tween" end
	end
	return "safe"
end

function triggerHarvestPrompt(prompt)
	-- Direct trigger: do not simulate the E-key and do not use InputHoldBegin/End.
	if not (prompt and prompt.Parent and prompt:IsA("ProximityPrompt") and prompt.Enabled) then
		return false
	end
	if type(fireproximityprompt) == "function" then
		local ok = pcall(function()
			fireproximityprompt(prompt)
		end)
		return ok
	end
	return false
end

function findHarvestPrompt(fruit)
	if not fruit then return nil end
	local named = fruit:FindFirstChild("HarvestPrompt", true)
	if named and named:IsA("ProximityPrompt") then return named end
	return fruit:FindFirstChildWhichIsA("ProximityPrompt", true)
end

function tweenCharacterTo(character, targetPosition)
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end
	local startCF = hrp.CFrame
	local offset = targetPosition - startCF.Position
	local dist = offset.Magnitude
	if dist <= 0.05 then return true end

	-- Lower movement speed keeps the path gentle instead of looking like a snap,
	-- while the shorter automation waits make the overall harvest faster.
	local duration = math.clamp(dist / HARVEST_TWEEN_SPEED, HARVEST_TWEEN_MIN, HARVEST_TWEEN_MAX)
	local elapsed = 0
	while elapsed < duration and hrp.Parent and character.Parent do
		elapsed += RunService.Heartbeat:Wait()
		local alpha = math.clamp(elapsed / duration, 0, 1)
		-- Smoothstep easing: gentle start/stop, still quick between fruits.
		local eased = alpha * alpha * (3 - 2 * alpha)
		hrp.CFrame = startCF:Lerp(CFrame.new(targetPosition), eased)
	end
	if hrp.Parent then
		hrp.CFrame = CFrame.new(targetPosition)
	end
	return true
end

function runHarvestCycle()
	local player = Players.LocalPlayer
	local character = player and player.Character
	if not character then return end
	local farm = getActiveFarm()
	if not farm then return end
	local plantsFolder = farm:FindFirstChild("Plants")
	if not plantsFolder then return end

	-- Crops chosen in the "Crops" dropdown; nothing selected = harvest every crop.
	local selectedCrops = {}
	local selectedCount = 0
	for name in pairs(cropSelection) do
		selectedCrops[normCropKey(name)] = true
		selectedCount += 1
	end
	local harvestAll = selectedCount == 0
	local mode = currentHarvestMode()
	local originPivot = character:GetPivot()
	local originPos = originPivot.Position
	local moved = false
	local harvestedNow = 0
	local ripeCount = 0

	for _, plant in ipairs(plantsFolder:GetChildren()) do
		local fruits = plant:FindFirstChild("Fruits")
		if fruits then
			for _, fruit in ipairs(fruits:GetChildren()) do
				local prompt = findHarvestPrompt(fruit)
				if prompt and prompt.Enabled then
					ripeCount += 1
					local cropName = plant:GetAttribute("CropName") or plant.Name
					local cropKey = normCropKey(cropName)
					local promptKey = normCropKey(prompt.ObjectText)
					if harvestAll or selectedCrops[cropKey] or selectedCrops[promptKey] then
						local fruitPosition
						if fruit:IsA("BasePart") then
							fruitPosition = fruit.Position
						else
							fruitPosition = fruit:GetPivot().Position
						end
						local distance = (fruitPosition - originPos).Magnitude

						if mode == "safe" then
							-- Safe Nearby is the only mode restricted to the 10-stud range.
							if distance <= HARVEST_RANGE then
								if triggerHarvestPrompt(prompt) then
									harvestedNow += 1
								end
							end
						else
							-- Instant/Tween modes can reach any fruit in the player's own farm.
							local target = fruitPosition + Vector3.new(0, 3, 0)
							if mode == "instant" then
								character:PivotTo(CFrame.new(target))
								moved = true
							else
								if tweenCharacterTo(character, target) then
									moved = true
								end
							end
							task.wait(HARVEST_TRIGGER_DELAY)
							if triggerHarvestPrompt(prompt) then
								harvestedNow += 1
							end
						end
					end
				end
			end
		end
	end

	-- Safe return: put the player back exactly where they started after TP modes.
	if moved and character.Parent then
		character:PivotTo(originPivot)
	end
	ripeStat.Text = tostring(ripeCount) .. " ripe"
	if harvestedNow > 0 then
		harvestedTotal += harvestedNow
		harvestStat.Text = tostring(harvestedTotal) .. " crops"
	end
end

task.spawn(function()
	while gui.Parent do
		-- Faster scan cadence without increasing character movement speed.
		task.wait(HARVEST_LOOP_DELAY)
		if ToggleState.autoHarvest then
			pcall(runHarvestCycle)
		end
	end
end)

-- ==WATER_AUTOMATION==
-- Inf Water Cup: pins the local CanWater attribute to the cup size so the water bar
-- stays full and local pour checks always pass. Steps aside while Auto Refill Water is
-- active so a genuinely empty cup can still be refilled server-side.
-- Auto Refill Water: saves the player position, teleports safely next to the Gripo
-- (water tap) on the local player's own farm, holds the Water Cup through
-- Remotes.Tools.Held, triggers the Gripo RefillPrompt, and returns the player to
-- their original position once the cup is full (max, not 0).
-- Auto Water Selected Crops / Auto Water All One By One: teleports to each thirsty
-- plant on the local player's own farm, sends Farm.WaterPlant:FireServer(plantPosition),
-- waits 0.5 seconds, then continues to the next plant. The server receives the plant's
-- live world position; no hard-coded crop coordinate is used.

SharedRemotes = ReplicatedStorage:FindFirstChild("Shared")
RemotesFolder = SharedRemotes and SharedRemotes:FindFirstChild("Remotes") or nil
ToolsHeld = nil
WaterPlantRemote = nil
if RemotesFolder then
	local toolsFolder = RemotesFolder:FindFirstChild("Tools")
	ToolsHeld = toolsFolder and toolsFolder:FindFirstChild("Held") or nil
	local farmFolder = RemotesFolder:FindFirstChild("Farm")
	WaterPlantRemote = farmFolder and farmFolder:FindFirstChild("WaterPlant") or nil
end

WATER_POUR_REACH = 30
WATER_POUR_DELAY = 0.5
WATER_HEALTHY_ABOVE = (CropConfig.Water and CropConfig.Water.HealthyAbove) or 0.6
WATER_DURATION = (CropConfig.Water and CropConfig.Water.Duration) or 172800

function getCupLevels()
	local player = Players.LocalPlayer
	local canSize = player:GetAttribute("CanSize") or 5
	local canWater = player:GetAttribute("CanWater")
	if canWater == nil then canWater = canSize end
	return canWater, canSize
end

function findGripoRefillPrompt(farm)
	-- Preferred layout: farm.Decorations.Gripo.<RefillPrompt>
	local decorations = farm:FindFirstChild("Decorations")
	local gripo = decorations and decorations:FindFirstChild("Gripo")
	if not gripo then
		for _, d in ipairs(farm:GetDescendants()) do
			if d:IsA("Model") and d.Name == "Gripo" then
				gripo = d
				break
			end
		end
	end
	if gripo then
		local prompt = gripo:FindFirstChild("RefillPrompt", true)
		if prompt and prompt:IsA("ProximityPrompt") then
			return prompt
		end
	end
	-- Last resort: any RefillPrompt on the own farm.
	for _, d in ipairs(farm:GetDescendants()) do
		if d:IsA("ProximityPrompt") and d.Name == "RefillPrompt" then
			return d
		end
	end
	return nil
end

function findWaterCupTool()
	local player = Players.LocalPlayer
	local character = player.Character
	if not character then return nil end
	local tool = character:FindFirstChild("Water Cup")
	if tool and tool:IsA("Tool") then return tool end
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") and child:GetAttribute("WateringCan") then return child end
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		tool = backpack:FindFirstChild("Water Cup")
		if tool and tool:IsA("Tool") then return tool end
		for _, child in ipairs(backpack:GetChildren()) do
			if child:IsA("Tool") and child:GetAttribute("WateringCan") then return child end
		end
	end
	return nil
end

function holdWaterCup(character, tool)
	if not (character and tool and ToolsHeld) then return false end
	if tool.Parent ~= character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid then return false end
		pcall(function() humanoid:EquipTool(tool) end)
		task.wait(0.25)
		if tool.Parent ~= character then
			task.wait(0.3)
		end
	end
	-- Same call the game's HeldToolController makes whenever the held tool changes.
	ToolsHeld:FireServer(tool)
	return true
end

refillBusy = false
wateringBusy = false

function runRefillCycle()
	if refillBusy or wateringBusy then return end
	local player = Players.LocalPlayer
	local character = player.Character
	if not (character and character.Parent) then return end
	local canWater, canSize = getCupLevels()
	if canWater >= canSize then return end

	local farm = getActiveFarm()
	if not farm then return end
	local prompt = findGripoRefillPrompt(farm)
	if not prompt then
		notify("Gripo (water tap) not found on your farm", C.orange)
		return
	end
	local tool = findWaterCupTool()
	if not tool then
		notify("No Water Cup found in your backpack", C.orange)
		return
	end
	if not ToolsHeld then
		notify("Tools.Held remote missing", C.red)
		return
	end

	refillBusy = true
	local originPivot = character:GetPivot()

	-- Hold the cup, then teleport safely next to the Gripo inside prompt range.
	holdWaterCup(character, tool)
	local anchor = prompt.Parent
	if not (anchor and anchor:IsA("BasePart")) then
		local gripoModel = prompt:FindFirstAncestorOfClass("Model")
		anchor = gripoModel and (gripoModel.PrimaryPart or gripoModel:FindFirstChildWhichIsA("BasePart", true)) or nil
	end
	if not (anchor and anchor:IsA("BasePart")) then
		refillBusy = false
		return
	end
	local promptRange = tonumber(prompt.MaxActivationDistance) or 10
	character:PivotTo(CFrame.new(anchor.Position + Vector3.new(0, 3, math.max(promptRange * 0.5, 4))))
	task.wait(0.2)

	-- Trigger the RefillPrompt directly when the executor exposes fireproximityprompt.
	prompt.Enabled = true
	triggerHarvestPrompt(prompt)

	-- Wait until the cup is actually full (max, not 0), then return to the original position.
	local deadline = os.clock() + 6
	while gui.Parent and os.clock() < deadline do
		task.wait(0.2)
		local water, size = getCupLevels()
		if size > 0 and water >= size then break end
	end
	if character.Parent then
		character:PivotTo(originPivot)
	end
	refillBusy = false
end

function plantNeedsWater(plant, now)
	if plant:GetAttribute("Dead") then return false end
	local dryAt = plant:GetAttribute("DryAt")
	if not dryAt then return false end
	local remaining = dryAt - now
	if remaining <= 0 then return true end
	return remaining / WATER_DURATION < WATER_HEALTHY_ABOVE
end

function collectThirstyPlants(selectedOnly)
	local list = {}
	local farm = getActiveFarm()
	if not farm then return list end
	local plantsFolder = farm:FindFirstChild("Plants")
	if not plantsFolder then return list end
	local now = workspace:GetServerTimeNow()
	local selected = {}
	local anySelected = false
	if selectedOnly then
		for name in pairs(waterCropSelection) do
			selected[normCropKey(name)] = true
			anySelected = true
		end
		if not anySelected then return list end
	end
	for _, plant in ipairs(plantsFolder:GetChildren()) do
		if plant:IsA("Model") and plantNeedsWater(plant, now) then
			if not selectedOnly then
				table.insert(list, plant)
			else
				local cropName = plant:GetAttribute("CropName") or plant.Name
				if selected[normCropKey(cropName)] then
					table.insert(list, plant)
				end
			end
		end
	end
	return list
end

function getPlantWorldPosition(plant)
	if not (plant and plant.Parent) then return nil end
	if plant:IsA("BasePart") then return plant.Position end
	local primary = plant.PrimaryPart or plant:FindFirstChildWhichIsA("BasePart", true)
	if primary then return primary.Position end
	return plant:GetPivot().Position
end

function waterPlantAtPosition(character, plant)
	local target = getPlantWorldPosition(plant)
	if not target then return false end
	if not (WaterPlantRemote and WaterPlantRemote:IsA("RemoteEvent")) then return false end

	-- This is the same local remote path requested: Shared.Remotes.Farm.WaterPlant.
	-- Always send the selected plant's current world position, never a hard-coded point.
	character:PivotTo(CFrame.new(target + Vector3.new(0, 3, 0)))
	task.wait(0.08)
	local ok = pcall(function()
		WaterPlantRemote:FireServer(target)
	end)
	if not ok then return false end
	task.wait(WATER_POUR_DELAY)
	return true
end

function runWaterCycle(mode)
	if wateringBusy or refillBusy then return end
	if not WaterPlantRemote then return end
	local player = Players.LocalPlayer
	local character = player and player.Character
	if not (character and character.Parent) then return end
	local canWater = getCupLevels()
	if canWater <= 0 then return end -- empty cup: Auto Refill Water handles it

	local list = collectThirstyPlants(mode == "selected")
	if #list == 0 then return end

	local tool = findWaterCupTool()
	if not tool then
		notify("No Water Cup found in your backpack", C.orange)
		return
	end

	wateringBusy = true
	local originPivot = character:GetPivot()
	local poured = 0

	holdWaterCup(character, tool)

	for _, plant in ipairs(list) do
		if not (character.Parent and gui.Parent and plant.Parent) then break end
		if waterPlantAtPosition(character, plant) then
			poured += 1
		end
		local water = getCupLevels()
		if water <= 0 then break end
	end

	if character.Parent then
		character:PivotTo(originPivot)
	end
	wateringBusy = false
	return poured
end

-- Inf Water Cup loop.
task.spawn(function()
	while gui.Parent do
		task.wait(0.25)
		if ToggleState.infCup and not ToggleState.autoRefill and not refillBusy then
			local player = Players.LocalPlayer
			local canSize = player:GetAttribute("CanSize") or 5
			local canWater = player:GetAttribute("CanWater")
			if canWater == nil or canWater < canSize then
				player:SetAttribute("CanWater", canSize)
			end
		end
	end
end)

-- Water automation loop: refill first (a real trip to the Gripo), then pour.
task.spawn(function()
	while gui.Parent do
		task.wait(0.5)
		if ToggleState.autoRefill then
			pcall(runRefillCycle)
		end
		if ToggleState.autoWaterSelected then
			pcall(runWaterCycle, "selected")
		elseif ToggleState.autoWaterAll then
			pcall(runWaterCycle, "all")
		end
	end
end)

-- ==SELL_AUTOMATION==
-- "Crops to Sell" dropdown: selected crops stay sellable while every other crop in
-- the backpack is favorited through Inventory.SetFavorite — the exact call the
-- satchel's own favorite button makes: SetFavorite:FireServer(cropIndex, true/false).
-- The game's Sell All keeps favorited crops, so only the selected crops are sold.
-- Auto Sell All / Auto Sell Selected (backpack full): pause all auto harvest and
-- auto water, teleport to the sell stand, fire Economy.SellAll(58), then return
-- the player to their original position and resume the paused toggles.
-- Auto Sell Every X Seconds does the same trip on a timer instead of waiting
-- for a full backpack.
InventoryRemotes = RemotesFolder and RemotesFolder:FindFirstChild("Inventory")
SetFavoriteRemote = InventoryRemotes and InventoryRemotes:FindFirstChild("SetFavorite")
EconomyRemotes = RemotesFolder and RemotesFolder:FindFirstChild("Economy")
SellAllRemote = EconomyRemotes and EconomyRemotes:FindFirstChild("SellAll")

SELL_STAND_POSITION = Vector3.new(-374, 21, 602)
SELL_ALL_ARGUMENT = 58

function collectCropTools()
	-- Crop tools are Tools with a numeric CropId attribute (seeds have CropName only,
-- just like the satchel's own checks).
	local player = Players.LocalPlayer
	local list = {}
	for _, container in ipairs({ player:FindFirstChildOfClass("Backpack"), player.Character }) do
		if container then
			for _, item in ipairs(container:GetChildren()) do
				if item:IsA("Tool") and type(item:GetAttribute("CropId")) == "number" then
					table.insert(list, item)
				end
			end
		end
	end
	return list
end

function cropToolKey(tool)
	return normCropKey(tool:GetAttribute("CropName") or tool:GetAttribute("DisplayName") or tool.Name)
end

applySellFavorites = function(sel)
	-- sel defaults to the live "Crops to Sell" selection.
	if not SetFavoriteRemote then
		notify("Inventory.SetFavorite remote not found", C.red)
		return 0
	end
	local selected = {}
	for name in pairs(sel or sellCropSelection) do
		selected[normCropKey(name)] = true
	end
	local fired = 0
	for _, tool in ipairs(collectCropTools()) do
		local cropId = tool:GetAttribute("CropId")
		local wantFavorite = not selected[cropToolKey(tool)]
		local isFavorite = tool:GetAttribute("Favorite") == true
		if wantFavorite ~= isFavorite then
			SetFavoriteRemote:FireServer(cropId, wantFavorite)
			tool:SetAttribute("Favorite", wantFavorite) -- local mirror until the server syncs
			fired += 1
		end
	end
	return fired
end

function getSellFullAt()
	local box = sellFullAtInput and sellFullAtInput:FindFirstChildWhichIsA("TextBox")
	local n = tonumber(box and box.Text)
	return (n and n > 0) and math.floor(n) or 58
end

function getSellSeconds()
	local box = sellSecondsInput and sellSecondsInput:FindFirstChildWhichIsA("TextBox")
	local n = tonumber(box and box.Text)
	return (n and n >= 1) and n or 25
end

sellBusy = false

AUTOMATION_KEYS = { "autoHarvest", "autoWaterSelected", "autoWaterAll", "autoRefill" }

-- Turn every auto harvest / auto water toggle OFF for the sell trip and remember
-- what was on, so it can be restored once the player is back in place.
function pauseGardenAutomation()
	local saved = {}
	for _, key in ipairs(AUTOMATION_KEYS) do
		saved[key] = ToggleState[key] == true
		if saved[key] and ToggleSetters[key] then
			ToggleSetters[key](false)
		end
	end
	return saved
end

function resumeGardenAutomation(saved)
	if not saved then return end
	for _, key in ipairs(AUTOMATION_KEYS) do
		if saved[key] and not ToggleState[key] and ToggleSetters[key] then
			ToggleSetters[key](true)
		end
	end
end

function runAutoSellCycle(force)
	if sellBusy or wateringBusy or refillBusy then return end
	local player = Players.LocalPlayer
	local character = player and player.Character
	if not (character and character.Parent) then return end
	local cropCount = #collectCropTools()
	if force then
		-- Timed auto sell: sell whatever is in the backpack right now.
		if cropCount == 0 then return end
	else
		if cropCount < getSellFullAt() then return end
	end

	sellBusy = true
	-- 1. Pause all auto harvest and auto water so nothing interrupts the trip.
	local savedAutomation = pauseGardenAutomation()
	local originalPivot = character:GetPivot()
	-- 2. Protect everything except the selected crops (Auto Sell Selected only).
	if ToggleState.autoSellSelected then
		applySellFavorites()
		task.wait(0.4)
	end
	-- 3. Teleport to the sell stand and trigger the game's Sell All remote.
	character:PivotTo(CFrame.new(SELL_STAND_POSITION))
	task.wait(0.4)
	if SellAllRemote then
		SellAllRemote:FireServer(SELL_ALL_ARGUMENT)
	else
		notify("Economy.SellAll remote not found", C.red)
	end
	-- 4. Wait for the sale to register (backpack count drops).
	local deadline = os.clock() + 6
	while gui.Parent and os.clock() < deadline do
		task.wait(0.25)
		if #collectCropTools() < cropCount then break end
	end
	-- 5. Return the player to where they were standing before the trip.
	if character.Parent then
		character:PivotTo(originalPivot)
	end
	-- 6. Resume the auto harvest / auto water toggles that were paused in step 1.
	resumeGardenAutomation(savedAutomation)
	notify("Auto sell finished", C.gold)
	sellBusy = false
end

-- Sell automation loop: keep the backpack counter current, run the sell cycle
-- whenever Auto Sell All / Auto Sell Selected is on and the backpack is full, and
-- run the same trip on a timer when Auto Sell Every X Seconds is on.
task.spawn(function()
	local lastTimedSell = os.clock()
	local timerWasOn = ToggleState.autoSellTimer == true
	while gui.Parent do
		task.wait(0.5)
		local crops = #collectCropTools()
		if sellBackpackStat then
			sellBackpackStat.Text = tostring(crops) .. " / " .. tostring(getSellFullAt())
		end
		if ToggleState.autoSellAll or ToggleState.autoSellSelected then
			pcall(runAutoSellCycle)
		end
		-- Timed auto sell: fire every N seconds regardless of backpack fullness.
		local timerOn = ToggleState.autoSellTimer == true
		if timerOn ~= timerWasOn then
			-- Toggling on/off restarts the countdown.
			timerWasOn = timerOn
			lastTimedSell = os.clock()
		end
		if timerOn and os.clock() - lastTimedSell >= getSellSeconds() then
			if not sellBusy and not wateringBusy and not refillBusy then
				lastTimedSell = os.clock()
				pcall(runAutoSellCycle, true)
			end
		end
	end
end)

-- ==REWARDS_AUTOMATION==
-- Safe Auto Claim Achievements: pull the player's real stats and claimed list from
-- Achievements.GetState, and only fire Achievements.Claim:FireServer(tierId) for tiers
-- whose goal is 100% reached (stats[chain.Stat] >= tier.Goal) and not yet claimed.
-- Safe Auto Claim Index: pull the index state from Index.GetState and only
-- Index.Claim:InvokeServer(pageId, milestoneIndex) for milestones the server itself
-- marked Ready and unclaimed, across every crop rarity page, pet page, and pet form.
AchievementConfig = require(ReplicatedStorage.Shared.Config.AchievementConfig)
IndexConfig = require(ReplicatedStorage.Shared.Config.IndexConfig)
PetConfig = require(ReplicatedStorage.Shared.Config.PetConfig)

AchievementsRemotes = RemotesFolder and RemotesFolder:FindFirstChild("Achievements")
IndexRemotes = RemotesFolder and RemotesFolder:FindFirstChild("Index")
AchievementsGetState = AchievementsRemotes and AchievementsRemotes:FindFirstChild("GetState")
AchievementsClaimRemote = AchievementsRemotes and AchievementsRemotes:FindFirstChild("Claim")
IndexGetState = IndexRemotes and IndexRemotes:FindFirstChild("GetState")
IndexClaimRemote = IndexRemotes and IndexRemotes:FindFirstChild("Claim")

rewardsBusy = false

function claimReadyAchievements()
	-- Only claim when the achievement is actually 100% complete.
	if not (AchievementsGetState and AchievementsClaimRemote) then return 0 end
	if not (AchievementsGetState:IsA("RemoteFunction") and AchievementsClaimRemote:IsA("RemoteEvent")) then return 0 end
	local ok, state = pcall(function()
		return AchievementsGetState:InvokeServer()
	end)
	if not ok or type(state) ~= "table" then return 0 end
	local stats = type(state.Stats) == "table" and state.Stats or {}
	local claimed = type(state.Claimed) == "table" and state.Claimed or {}
	local fired = 0
	for _, chain in ipairs(AchievementConfig.Chains) do
		-- The next unclaimed tier in this chain (nil when everything is claimed).
		local tier = AchievementConfig.Current(chain, claimed)
		while tier do
			local progress = tonumber(stats[chain.Stat]) or 0
			-- Not 100% claimable yet — do NOT claim.
			if progress < tier.Goal then break end
			AchievementsClaimRemote:FireServer(tier.Id)
			claimed[tier.Id] = true -- local mirror so the loop advances
			fired += 1
			task.wait(0.15)
			tier = AchievementConfig.Current(chain, claimed)
		end
	end
	return fired
end

function claimReadyIndexMilestones(pageId, milestones)
	-- milestones[i].Ready / .Claimed come from the server's own state, so only
	-- genuinely claimable milestones are touched (indexes 1, 2, 3, ... per page).
	local fired = 0
	for i in ipairs(IndexConfig.Milestones) do
		local m = milestones and milestones[i]
		if m and m.Ready and not m.Claimed and IndexClaimRemote then
			local ok = pcall(function()
				return IndexClaimRemote:InvokeServer(pageId, i)
			end)
			if ok then
				fired += 1
				m.Claimed = true -- local mirror
			task.wait(0.15)
			end
		end
	end
	return fired
end

function claimReadyIndex()
	-- Check every rarity page (Crops:Common ... Crops:Secret), the Pets pages,
	-- and every pet's form milestones — claim only what the state says is ready.
	if not (IndexGetState and IndexClaimRemote) then return 0 end
	if not (IndexGetState:IsA("RemoteFunction") and IndexClaimRemote:IsA("RemoteFunction")) then return 0 end
	local ok, state = pcall(function()
		return IndexGetState:InvokeServer()
	end)
	if not ok or type(state) ~= "table" then return 0 end
	local pages = type(state.Pages) == "table" and state.Pages or {}
	local petForms = type(state.PetForms) == "table" and state.PetForms or {}
	local fired = 0
	for _, tabName in ipairs({ "Crops", "Pets" }) do
		for _, page in ipairs(IndexConfig.PagesOf(tabName)) do
			if not page.NoRewards then
				local pageState = pages[page.Id]
				fired += claimReadyIndexMilestones(page.Id, pageState and pageState.Milestones)
			end
		end
	end
	for petName in pairs(PetConfig.Pets) do
		local formState = petForms[petName]
		fired += claimReadyIndexMilestones(IndexConfig.FormsId(petName), formState and formState.Milestones)
	end
	return fired
end

-- Rewards automation loop: when the toggles are on, sweep for claimable
-- achievements and index milestones every few seconds (safe — unclaimable
-- entries are never fired).
task.spawn(function()
	while gui.Parent do
		task.wait(5)
		if rewardsBusy then continue end
		local wantsAchievements = ToggleState.claimAchievements == true
		local wantsIndex = ToggleState.claimIndex == true
		if not (wantsAchievements or wantsIndex) then continue end
		rewardsBusy = true
		local achievementsFired = 0
		local indexFired = 0
		if wantsAchievements then
			local ok, result = pcall(claimReadyAchievements)
			if ok then achievementsFired = result or 0 end
		end
		if wantsIndex then
			local ok, result = pcall(claimReadyIndex)
			if ok then indexFired = result or 0 end
		end
		if achievementsFired + indexFired > 0 then
			notify(string.format("Claimed %d achievement(s), %d index reward(s)", achievementsFired, indexFired), C.gold)
		end
		rewardsBusy = false
	end
end)

main.UI.Gui = gui
main.UI.Panel = panel
main.UI.Rail = rail
main.UI.Content = content
main.UI.StatusBar = statusBar
-- ==TEXT_POLISH==
-- Final pass: keep every visible text element readable and vertically centered.
for _, obj in ipairs(gui:GetDescendants()) do
	if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
		if obj.TextXAlignment == nil then obj.TextXAlignment = Enum.TextXAlignment.Left end
		if obj.TextYAlignment == nil then obj.TextYAlignment = Enum.TextYAlignment.Center end
		if obj:IsA("TextLabel") or obj:IsA("TextButton") then
			obj.TextTruncate = obj.TextTruncate or Enum.TextTruncate.AtEnd
		end
	end
end

print("[BahayKuboGarden] Panel loaded — RightShift toggles visibility")