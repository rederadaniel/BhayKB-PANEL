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
RARITY_SORT_ORDER = { Common=1, Uncommon=2, Rare=3, Epic=4, Legendary=5, Mythic=6, Ancient=7, Divine=8, Secret=9, OG=10, Champion=11, Creator=12 }
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
	autoHarvestAllReady=true,
	autoClaimQuests=true,
	autoQuest=true,
	fpsMode=true,
}
function isMasterTarget(key) return not MASTER_IGNORE[key] end

toggleIcons = {
	autoHarvest="rbxassetid://84998465111718", autoHarvestAllReady="🌾", autoRefill="💧", autoSellAll="₱", autoSellSelected="✓",
	autoPayBill="₱", autoBuySeeds="🌱", autoBuyEggs="🥚", autoBuyStore="📦", autoBuyGear="⚙", autoBuyBasics="▣",
	autoBuyDecor="▦", autoBuyMerchant="🛒", autoPlaceAll="🥚", autoPlaceSelected="✓", autoHatchReady="★",
	autoSleep="☾", autoCodes="#", antiAFK="◉", autoBestPets="🐾", farmSetup="⌂",
	notifications="●", showStatusBar="▤", autoCloseDropdowns="⌄", compactMode="≡", showHints="?",
	highContrast="◐", showIconLabels="◆", studIconStyle="●", lockPanelPosition="⌐",
	preferRareMutations="★", ignoreCommonDrops="×", buyNeededSeeds="✓", hatchSelectedEggs="🥚",
	fpsMode="🚀",
	alertRareCrop="!", alertMutation="!", alertRestock="↻", alertEggReady="🥚", alertLowWater="💧", alertLowMoney="₱",
	autoClaimQuests="★",
	autoQuest="★"
}

actionIcons = {
	["Center Panel"]="⌂", ["Reset UI View"]="↺", ["Apply UI Settings"]="✓",
	["🌱 Farming Profile"]="🌱", ["🛒 Shopping Profile"]="🛒", ["💤 Low Activity / Safe UI"]="◉",
	["One-Tap Equip All Pets"]="🐾", ["Unfavorite All Crops"]="☆", ["Unfavorite Selected Crops"]="☆",
	["Favorite All Crops"]="★", ["Favorite Selected Crops"]="★"
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
SeedInfoConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("SeedInfoConfig"))
FarmArea = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utilities"):WaitForChild("FarmArea"))
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
SEEDS = {}
do
	for seedName, desc in pairs(SeedInfoConfig.Seeds) do
		local cropCfg = CropConfig.Crops[seedName]
		table.insert(SEEDS, {
			name = seedName,
			rarity = cropCfg and cropCfg.Rarity or "Common",
			desc = "Seed ₱" .. tostring(cropCfg and cropCfg.SeedPrice or "?") .. "  ·  " .. desc,
		})
	end
	table.sort(SEEDS, function(a, b)
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
EGGS = {}
EGG_ID_MAP = {}
EGG_PRICE_MAP = {}
do
	local ok, pCfg = pcall(function()
		return require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("PetConfig"))
	end)
	if ok and pCfg and pCfg.Eggs then
		for eggId, cfg in pairs(pCfg.Eggs) do
			local displayName = cfg.DisplayName or eggId
			local rarity = "Common"
			if cfg.Exclusive or cfg.Robux then
				rarity = "Mythic"
			elseif cfg.Price then
				if cfg.Price >= 1000000 then rarity = "Legendary"
				elseif cfg.Price >= 100000 then rarity = "Rare"
				elseif cfg.Price >= 10000 then rarity = "Uncommon"
				end
			end
			local desc = "₱" .. tostring(cfg.Price or "?") .. "  ·  Hatch " .. tostring(cfg.HatchTime or "?") .. "s"
			if cfg.Exclusive then desc = desc .. "  ·  Exclusive" end
			if cfg.Robux then desc = desc .. "  ·  Robux" end
			table.insert(EGGS, {
				name = displayName,
				rarity = rarity,
				desc = desc,
				id = eggId,
				price = cfg.Price or 0,
				hatchTime = cfg.HatchTime or 0,
			})
		end
	end
	if #EGGS == 0 then
		EGGS = {
			{ name = "Common Egg", rarity = "Common", desc = "Basic egg", id = "BasicEgg", price = 3000, hatchTime = 300 },
			{ name = "Uncommon Egg", rarity = "Uncommon", desc = "Farm egg", id = "FarmEgg", price = 12000, hatchTime = 900 },
			{ name = "Rare Egg", rarity = "Rare", desc = "Provincial egg", id = "ProvincialEgg", price = 110000, hatchTime = 2400 },
			{ name = "Epic Egg", rarity = "Epic", desc = "Mystic egg", id = "MysticEgg", price = 400000, hatchTime = 5400 },
			{ name = "Legendary Egg", rarity = "Legendary", desc = "Ancient egg", id = "AncientEgg", price = 3500000, hatchTime = 10800 },
		}
	end
	table.sort(EGGS, function(a, b) return (a.price or 0) < (b.price or 0) end)
	for _, egg in ipairs(EGGS) do
		EGG_ID_MAP[egg.name] = egg.id
		EGG_ID_MAP[egg.id] = egg.id
		EGG_PRICE_MAP[egg.id] = egg.price or 0
	end
end

STORE_ITEMS = {}
do
	local ok, sCfg = pcall(function()
		return require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("StoreConfig"))
	end)
	if ok and sCfg then
		if sCfg.Gear then
			for _, cfg in ipairs(sCfg.Gear) do
				if type(cfg) == "table" and cfg.Id then
					table.insert(STORE_ITEMS, {
						name = cfg.Id,
						rarity = cfg.Rarity or "Common",
						desc = (cfg.DisplayName and cfg.DisplayName ~= cfg.Id and (cfg.DisplayName .. "  ·  ₱" .. tostring(cfg.Price or "?")) or ("₱" .. tostring(cfg.Price or "?"))) .. (cfg.Desc and ("  ·  " .. cfg.Desc) or ""),
					})
				end
			end
		end
		if sCfg.GiftCopies then
			for _, cfg in ipairs(sCfg.GiftCopies) do
				if type(cfg) == "table" and cfg.Id then
					table.insert(STORE_ITEMS, {
						name = cfg.Id,
						rarity = cfg.Rarity or "Rare",
						desc = "Gift copy  ·  " .. (cfg.DisplayName or cfg.Id),
					})
				end
			end
		end
	end
	if #STORE_ITEMS == 0 then
		-- Fallback list if StoreConfig is unavailable
		STORE_ITEMS = {
			{ name = "ReviveAll", rarity = "Legendary", desc = "Revive all crops instantly." },
			{ name = "Revive", rarity = "Epic", desc = "Revive a single crop." },
			{ name = "Basket", rarity = "Uncommon", desc = "Adds backpack crop slots." },
			{ name = "BasicFertilizer", rarity = "Common", desc = "Basic growth boost." },
			{ name = "StrongFertilizer", rarity = "Rare", desc = "Stronger growth boost." },
			{ name = "DiwataFertilizer", rarity = "Legendary", desc = "Premium growth boost." },
			{ name = "BasicSprinkler", rarity = "Rare", desc = "Waters nearby plots." },
			{ name = "GoldenSprinkler", rarity = "Epic", desc = "Golden sprinkler." },
			{ name = "RareSprinkler", rarity = "Rare", desc = "Rare-tier sprinkler." },
			{ name = "LegendarySprinkler", rarity = "Legendary", desc = "Legendary sprinkler." },
			{ name = "MythicSprinkler", rarity = "Mythic", desc = "Best sprinkler." },
			{ name = "MalakingTabo", rarity = "Uncommon", desc = "Large watering dipper." },
			{ name = "Timba", rarity = "Common", desc = "Water bucket." },
		}
	end
	table.sort(STORE_ITEMS, function(a, b) return (RARITY_SORT_ORDER[a.rarity] or 99) < (RARITY_SORT_ORDER[b.rarity] or 99) end)
end

DECORATION_ITEMS = {}
do
	local ok, dCat = pcall(function()
		return require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("DecorationCatalog"))
	end)
	if ok and dCat then
		for _, cfg in ipairs(dCat) do
			if type(cfg) == "table" and cfg.Id then
				table.insert(DECORATION_ITEMS, {
					name = cfg.Id,
					rarity = cfg.Rarity or "Common",
					desc = (cfg.DisplayName or cfg.Id) .. "  ·  ₱" .. tostring(cfg.Price or "?") .. (cfg.Desc and ("  ·  " .. cfg.Desc) or ""),
				})
			end
		end
	end
	if #DECORATION_ITEMS == 0 then
		-- Fallback list if DecorationCatalog is unavailable
		DECORATION_ITEMS = {
			{ name = "BambooFence", rarity = "Common", desc = "Bamboo Fence  ·  ₱500" },
			{ name = "FlowerPot", rarity = "Common", desc = "Flower Pot  ·  ₱800" },
			{ name = "LampPost", rarity = "Uncommon", desc = "Lamp Post  ·  ₱1500" },
			{ name = "Parol", rarity = "Uncommon", desc = "Parol  ·  ₱2000" },
		}
	end
	table.sort(DECORATION_ITEMS, function(a, b) return (RARITY_SORT_ORDER[a.rarity] or 99) < (RARITY_SORT_ORDER[b.rarity] or 99) end)
end

MERCHANT_ITEMS = {}
do
	local function addMerchantItem(id, displayName, rarity, kind, desc)
		table.insert(MERCHANT_ITEMS, {
			name = id,
			rarity = rarity or "Common",
			kind = kind or "Others",
			desc = (kind and ("[" .. kind .. "] ") or "") .. (displayName or id) .. (desc and ("  ·  " .. desc) or ""),
		})
	end

	-- Load potions from PotionConfig (7 types x 8 tiers = 56 potions)
	local okP, pCfg = pcall(function()
		return require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("PotionConfig"))
	end)
	if okP and pCfg and pCfg.Types and pCfg.Tiers and pCfg.TypeOrder and pCfg.TierOrder then
		for _, pType in ipairs(pCfg.TypeOrder) do
			local typeInfo = pCfg.Types[pType]
			for _, tier in ipairs(pCfg.TierOrder) do
				local potionId = pType .. "_" .. tier
				local display = (typeInfo and typeInfo.DisplayName or pType) .. " Potion"
				local numeral = pCfg.TierNumerals and pCfg.TierNumerals[tier] or tier
				addMerchantItem(potionId, display .. " " .. numeral, tier, "Potion")
			end
		end
	end

	-- Load seeds from CropConfig.ShopLineup
	local okC, cCfg = pcall(function()
		return require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("CropConfig"))
	end)
	if okC and cCfg and cCfg.ShopLineup then
		for _, cropId in ipairs(cCfg.ShopLineup) do
			local cropInfo = cCfg[cropId]
			if type(cropInfo) == "table" then
				addMerchantItem(cropId, (cropInfo.DisplayName or cropId) .. " Seed", cropInfo.Rarity or "Common", "Seed")
			end
		end
	end

	-- Load gear from StoreConfig.Gear (fertilizers, sprinklers, tabo upgrades, basket, revive)
	local okS, sCfg = pcall(function()
		return require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("StoreConfig"))
	end)
	if okS and sCfg and sCfg.Gear then
		for _, cfg in ipairs(sCfg.Gear) do
			if type(cfg) == "table" and cfg.Id then
				addMerchantItem(cfg.Id, cfg.DisplayName or cfg.Id, cfg.Rarity or "Common", "Gear", cfg.Desc)
			end
		end
	end

	if #MERCHANT_ITEMS == 0 then
		-- Fallback list if configs are unavailable
		MERCHANT_ITEMS = {
			{ name = "Luck_Rare", rarity = "Rare", desc = "[Potion] Luck Potion III" },
			{ name = "Cash_Legendary", rarity = "Legendary", desc = "[Potion] Cash Potion V" },
			{ name = "Growth_Epic", rarity = "Epic", desc = "[Potion] Growth Potion IV" },
			{ name = "Pet_Mythic", rarity = "Mythic", desc = "[Potion] Pet Potion VI" },
			{ name = "Mais", rarity = "Common", desc = "[Seed] Corn Seed" },
			{ name = "Mangosteen", rarity = "Epic", desc = "[Seed] Mangosteen Seed" },
			{ name = "BasicSprinkler", rarity = "Common", desc = "[Gear] Basic Sprinkler" },
			{ name = "BasicFertilizer", rarity = "Uncommon", desc = "[Gear] Basic Fertilizer" },
		}
	end
	table.sort(MERCHANT_ITEMS, function(a, b) return a.name < b.name end)
end

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
statusText = makeText(statusBar, "Bahay Kubo Garden v7.0  •  RightShift show/hide  •  0 active", Color3.fromRGB(188, 194, 200), UDim2.new(0.02, 0, 0.05, 0), UDim2.new(0.96, 0, 0.90, 0), 1.1, 19, "center", 13)
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
	harvest="rbxassetid://84998465111718", water="rbxassetid://84697600263846", sell="₱", rewards="★", seedplant="🌱", mainquest="★", main="🐾",
	seeds="rbxassetid://120628031716892", pets="🐾", store="▣", merchant="🛒", upgrades="⬆", eggs="🥚", other="⋯",
	uiSettings="⚙", filters="⌕", aboutSettings="ⓘ",
	update="📋",
	about="?"
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
makeRailBtn("Update", "📋")

currentTopTab = "Dashboard"
currentSubTab = "overview"

function showTop(tab)
	currentTopTab = tab
	toolbarTitle.Text = tab .. "  /  " .. ((tab == "Dashboard" and "Overview") or (tab == "Main" and "Harvest") or (tab == "Stocks" and "Seeds") or (tab == "Settings" and "UI Settings") or (tab == "Update" and "Guide & Updates") or (tab == "About" and "Welcome") or "About")
	for _, c in pairs(subRow:GetChildren()) do
		if c:IsA("TextButton") then c:Destroy() end
	end
	local subs = {}
	if tab == "Dashboard" then subs = { "overview", "activity", "profiles", "alerts", "index" } end
	if tab == "Main" then subs = { "harvest", "water", "sell", "rewards", "seedplant", "mainquest", "main" } end
	if tab == "Stocks" then subs = { "seeds", "pets", "store", "merchant", "upgrades", "eggs", "other" } end
	if tab == "Settings" then subs = { "uiSettings", "filters", "aboutSettings" } end
	if tab == "Update" then subs = { "update" } end
	if tab == "About" then subs = { "about" } end
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
subTitles.seedplant = "Seed"
subTitles.mainquest = "Main Quest"
subTitles.main = "Main Controls"
subTitles.update = "Guide & Updates"

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

-- Dashboard formatting helpers
sessionStartTime = os.time()
function formatMoney(n)
	local s = tostring(math.floor(tonumber(n) or 0))
	local result = ""
	while #s > 3 do
		result = "," .. s:sub(-3) .. result
		s = s:sub(1, -4)
	end
	return s .. result
end
function formatDuration(seconds)
	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	local s = math.floor(seconds % 60)
	if h > 0 then return string.format("%dh %dm", h, m) end
	if m > 0 then return string.format("%dm %ds", m, s) end
	return string.format("%ds", s)
end

-- ==DASHBOARD_PAGES==
overview = newPage("overview")
makeHeader(overview, "Garden Dashboard", C.leaf, "rbxassetid://101953044632807")

-- Status ribbon: compact, live info bar showing real game time and garden status.
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
rbRight = makeText(statusRibbon, "READY  •  LIVE  •  v7.1", Color3.fromRGB(204, 210, 218), UDim2.new(0.98, 0, 0.08, 0), UDim2.new(0.66, 0, 0.84, 0), 1.2, 6, "right")

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
dashMoney = rightValueLabel(makeStat(overview, "Money", "₱0", C.gold, "rbxassetid://84697600263846"))
dashPlants = rightValueLabel(makeStat(overview, "Plants", "0", C.leaf))
dashRipe = rightValueLabel(makeStat(overview, "Ripe Fruits", "0", C.green))
dashEggs = rightValueLabel(makeStat(overview, "Placed Eggs", "0", C.pink))
dashHarvested = rightValueLabel(makeStat(overview, "Total Harvested", "0", C.leaf))
dashSession = rightValueLabel(makeStat(overview, "Session Time", "0s", C.sky))
dashAutoBuy = rightValueLabel(makeStat(overview, "Auto-Buy Active", "0/5", C.orange))
rightValueLabel(makeStat(overview, "Tip", "Use Profiles for one-tap presets", C.gold))
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
	local targets = { autoBuySeeds=true, autoBuyEggs=true, autoBuyStore=true, autoBuyDecor=true, autoBuyMerchant=true }
	for key, setter in pairs(ToggleSetters) do if isMasterTarget(key) then setter(targets[key] == true) end end
	uiSettings.silent = false
	notify("Shopping profile applied", C.orange)
end)
makeActionButton(overview, "🛒 Enable All Auto-Buy", C.blue, function()
	uiSettings.silent = true
	local buyKeys = { autoBuySeeds=true, autoBuyEggs=true, autoBuyStore=true, autoBuyDecor=true, autoBuyMerchant=true }
	for key, setter in pairs(ToggleSetters) do if buyKeys[key] then setter(true) end end
	uiSettings.silent = false
	notify("All auto-buy toggles enabled", C.blue)
end)
makeActionButton(overview, "⛔ Everything Off", C.red, function()
	uiSettings.silent = true
	for key, setter in pairs(ToggleSetters) do if isMasterTarget(key) then setter(false) end end
	uiSettings.silent = false
	notify("Automation switches cleared", C.red)
end)
makeActionButton(overview, "↻ Refresh Farm Stats", C.sky, function()
	refreshFarmStats()
	notify("Farm stats refreshed", C.sky)
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
for _, pair in { {"autoHarvest","Auto Harvest"}, {"autoHarvestAllReady","Auto Harvest All Ready"}, {"autoRefill","Auto Refill Water"}, {"autoPayBill","Auto Pay Bill"}, {"autoSellAll","Auto Sell All"}, {"autoSellSelected","Auto Sell Selected"}, {"autoSellTimer","Auto Sell Timer"}, {"autoBuySeeds","Auto Buy Seeds"}, {"autoBuyEggs","Auto Buy Eggs"}, {"autoBuyStore","Auto Buy Store"}, {"autoBuyDecor","Auto Buy Decor"}, {"autoBuyMerchant","Auto Buy Merchant"}, {"autoPlaceAll","Auto Place Eggs"}, {"autoHatchReady","Auto Hatch Eggs"}, {"autoCodes","Auto Codes"}, {"autoBestPets","Auto Best Pets"}, {"autoClaimQuests","Auto Claim Quests"}, {"autoQuest","Auto Quest"}, {"claimAchievements","Claim Achievements"}, {"claimIndex","Claim Index"}, {"claimPass","Claim Pass"}, {"antiAFK","Anti-AFK"} } do
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
	local t={autoBuySeeds=true,autoBuyEggs=true,autoBuyStore=true,autoBuyDecor=true,autoBuyMerchant=true}
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
makeActionButton(profiles, "🌙 Sleep Mode", C.purple, function()
	uiSettings.silent = true
	local t={autoHarvest=false,autoRefill=false,autoSellAll=false,autoSellSelected=false,autoPayBill=false,autoBuySeeds=false,autoBuyEggs=false,autoBuyStore=false,autoBuyDecor=false,autoBuyMerchant=false,autoPlaceAll=false,autoHatchReady=false,autoCodes=false,autoSleep=true}
	for k,sr in pairs(ToggleSetters) do if isMasterTarget(k) then sr(t[k] == true) end end
	uiSettings.silent=false
	notify("Sleep mode applied — only auto sleep enabled", C.purple)
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
makeToggle(uiSettingsPage, "Silent Mode (no toast popups)", false, "silent")
makeToggle(uiSettingsPage, "FPS Mode (hide decorations & effects)", false, "fpsMode")
section(uiSettingsPage, "Sliders", 10)
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
section(uiSettingsPage, "Bulk Actions", 30)
makeActionButton(uiSettingsPage, "Reset All Toggles", C.red, function()
	uiSettings.silent = true
	for key, setter in pairs(ToggleSetters) do if isMasterTarget(key) then setter(false) end end
	uiSettings.silent = false
	notify("All toggles reset to OFF", C.red)
end)
makeActionButton(uiSettingsPage, "Enable All Auto-Buy", C.blue, function()
	uiSettings.silent = true
	local buyKeys = { autoBuySeeds=true, autoBuyEggs=true, autoBuyStore=true, autoBuyDecor=true, autoBuyMerchant=true }
	for key, setter in pairs(ToggleSetters) do if buyKeys[key] then setter(true) end end
	uiSettings.silent = false
	notify("All auto-buy toggles enabled", C.blue)
end)
makeActionButton(uiSettingsPage, "Enable All Automation", C.green, function()
	uiSettings.silent = true
	local autoKeys = { autoHarvest=true, autoHarvestAllReady=true, autoRefill=true, autoSellAll=true, autoBuySeeds=true, autoBuyEggs=true, autoBuyStore=true, autoBuyDecor=true, autoBuyMerchant=true, autoPlaceAll=true, autoHatchReady=true, autoCodes=true, autoClaimQuests=true, autoQuest=true }
	for key, setter in pairs(ToggleSetters) do if autoKeys[key] then setter(true) end end
	uiSettings.silent = false
	notify("All automation toggles enabled", C.green)
end)
makeActionButton(uiSettingsPage, "Disable All Automation", C.red, function()
	uiSettings.silent = true
	local autoKeys = { "autoHarvest","autoHarvestAllReady","autoRefill","autoSellAll","autoSellSelected","autoSellTimer","autoBuySeeds","autoBuyEggs","autoBuyStore","autoBuyDecor","autoBuyMerchant","autoPlaceAll","autoHatchReady","autoCodes","autoBestPets","autoSleep","autoUpgradePlot","autoUpgradeHouse","autoClaimQuests","autoQuest" }
	for _, key in autoKeys do if ToggleSetters[key] then ToggleSetters[key](false) end end
	uiSettings.silent = false
	notify("All automation toggles disabled", C.red)
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
makeStat(aboutSettings, "Version", "7.2 Update Tab + Live Stats", C.gold)
makeStat(aboutSettings, "Panel Type", "Client UI / controls", C.sky)
makeStat(aboutSettings, "Hotkey", "RightShift", C.green)
makeStat(aboutSettings, "Window", "— minimize  |  × hide", C.orange)
makeStat(aboutSettings, "Theme", "Studded Blocky Cartoon", C.leaf)
makeStat(aboutSettings, "Pages", "Dashboard · About · Main · Stocks · Settings · Update", C.purple)
para(aboutSettings, "Version 7.2 adds the Update tab with comprehensive guide, refill threshold input field, live stats on all pages, and updated About page. v7.1 added formatted money display, session timer, auto-buy counter, keyboard shortcuts, changelog, sleep mode profile, and improved status bar.", 5, 100)

-- ==ABOUT_PAGE==
about = newPage("about")
section(about, "Welcome", 1)
para(about, "Bahay Kubo Garden is a comprehensive farming control center with auto harvest, auto water, auto sell, auto buy (seeds, eggs, store, decorations, merchant), auto egg placement, auto hatch, auto codes, auto claim rewards, and anti-AFK — all in one studded blocky panel.", 2, 86)
makeStat(about, "Version", "7.2 Update Tab + Live Stats", C.gold)
makeStat(about, "Theme", "Studded Blocky Cartoon", C.green)
makeStat(about, "Interaction", "Static, compact, scroll-safe UI", C.sky)

section(about, "Navigation", 3)
para(about, "Dashboard shows live garden stats and quick actions. About (this tab) has full panel documentation, navigation, and changelog. Main has Harvest, Water, Sell, and Rewards. Stocks has Seeds, Pets, Store, Merchant, Upgrades, Eggs, and Other. Settings has UI controls, filters, and panel info. Update has a comprehensive guide explaining every tab, toggle, input, dropdown, and automation logic.", 4, 86)

section(about, "Window Controls", 5)
makeStat(about, "—", "Minimize the panel to title bar", C.orange)
makeStat(about, "×", "Hide the panel (RightShift to show)", C.red)
makeStat(about, "RightShift", "Show / hide the panel", C.green)

section(about, "Automation Features", 7)
makeStat(about, "Auto Harvest", "Safe / Instant TP / Tween TP modes", C.leaf)
makeStat(about, "Auto Water", "TP + Farm.WaterPlant remote, 0.5s cycle", C.sky)
makeStat(about, "Auto Sell", "Sell All / Selected / Timer with favorites", C.gold)
makeStat(about, "Auto Buy Seeds", "Shop.BuySeed, 0.5s per seed", C.green)
makeStat(about, "Auto Buy Eggs", "Pets.BuyEgg, 0.5s per egg", C.pink)
makeStat(about, "Auto Buy Store", "Store.Buy for gear + decorations", C.brown)
makeStat(about, "Auto Buy Merchant", "Merchant.Buy for potions + gear", C.purple)
makeStat(about, "Auto Place Eggs", "Pets.PlaceEgg at available soil spots", C.pink)
makeStat(about, "Auto Hatch", "fireproximityprompt on ready eggs", C.green)
makeStat(about, "Auto Codes", "Codes.Redeem:InvokeServer for known codes", C.gold)
makeStat(about, "Auto Claim", "Achievements + Index + Season Pass", C.orange)
makeStat(about, "Anti-AFK", "Locked ON — prevents idle disconnect", C.blue)
makeStat(about, "Auto Sleep", "Auto sleep at the farm house", C.purple)
makeStat(about, "Auto Best Pets", "Equip all best pets automatically", C.pink)

section(about, "Live Stats", 9)
para(about, "The dashboard shows live game stats: money from leaderstats, plant count, ripe fruit count, and placed egg count. v7.2 extends live stats to all pages — water bill, water cup level, backpack crop count, auto-buy status, and egg counts (unplaced, ready, placed). All stats update every 0.5 seconds.", 10, 76)

section(about, "Quick Actions", 11)
para(about, "Farming Profile enables harvest, water, sell, and best pets. Shopping Profile enables all auto-buy toggles. Enable All Auto-Buy does the same independently. Everything Off resets all automation toggles. Refresh Farm Stats pulls the latest plant and ripe counts.", 12, 76)

section(about, "Settings", 13)
para(about, "Settings includes: notifications toggle, status bar, auto-close dropdowns, compact layout, helper text, high contrast, icon visibility, stud icon style, lock panel position, silent mode, panel opacity slider, toast duration slider, dropdown height slider, center panel, reset UI view, reset all toggles, and enable all auto-buy.", 14, 86)

section(about, "Scrolling", 15)
para(about, "Long pages use a dedicated ScrollingFrame. TOP resets to the first position. Home, End, PageUp, and PageDown work when the scroll area has focus.", 16, 60)

section(about, "What's New in v7.2", 17)
para(about, "New Update tab with comprehensive guide explaining every tab, toggle, input, dropdown, and automation logic. Refill threshold input field on Water page. Live stats extended to all pages (money, plants, ripe fruits, eggs, bill, backpack, auto-buy status). Updated About page with v7.2 info and Update tab in navigation. Updated aboutSettings panel info to v7.2.", 18, 100)

section(about, "Important Notes", 19)
para(about, "All automation uses pcall for safety. Remote calls are validated before firing. The panel checks for farm ownership using Farm_<UserId>. Game-specific actions depend on the underlying game logic and available remotes.", 20, 76)

section(about, "Keyboard Shortcuts", 21)
makeStat(about, "RightShift", "Show / hide the panel", C.green)
makeStat(about, "Home", "Jump to top of scroll area", C.sky)
makeStat(about, "End", "Jump to bottom of scroll area", C.orange)
makeStat(about, "PageUp / PageDown", "Scroll up / down by one page", C.purple)
makeStat(about, "Left / Right", "Fine-tune slider values", C.gold)

section(about, "Changelog", 22)
makeStat(about, "v7.2", "Added Update tab with full guide, refill threshold input, live stats on all pages, updated About page", C.gold)
makeStat(about, "v7.1", "Dashboard formatting, session timer, auto-buy counter, changelog, keyboard shortcuts", C.green)
makeStat(about, "v7.0", "Live dashboard stats, more quick actions, silent mode, reset toggles, consolidated about", C.green)
makeStat(about, "v6.0", "Auto egg placement, auto hatch, auto codes, auto claim rewards, anti-AFK lock", C.sky)
makeStat(about, "v5.0", "Auto buy store + decorations + merchant with dynamic config loading", C.orange)
makeStat(about, "v4.0", "Auto harvest with Safe/Instant/Tween TP modes, auto water with Gripo refill", C.purple)
makeStat(about, "v3.0", "Auto sell with favorites protection, timed auto sell, backpack tracking", C.pink)
makeStat(about, "v2.0", "Dropdown system with search, select all, deselect all, rarity coloring", C.blue)
makeStat(about, "v1.0", "Initial studded blocky cartoon panel with rail navigation", C.gray)

section(about, "Credits", 23)
para(about, "Bahay Kubo Garden Control Center. Built with studded blocky cartoon UI. All remote interactions use pcall for safety. Farm detection uses Farm_<UserId> with OwnerUserId fallback. Config modules loaded dynamically from ReplicatedStorage.Shared.Config.", 24, 70)

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

harvestMoneyStat = rightValueLabel(makeStat(harvest, "Money", "₱0", C.gold, "rbxassetid://84697600263846"))
farmStat = rightValueLabel(makeStat(harvest, "Player Plot", "Checking...", C.green))
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
makeToggle(harvest, "Auto Harvest All Ready Ripe Crops", false, "autoHarvestAllReady")
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
waterBillStat = rightValueLabel(makeStat(water, "Bill", "₱0", C.gold, "rbxassetid://84697600263846"))
waterCupStat = rightValueLabel(makeStat(water, "Water Cup", "0/5", Color3.new(1, 1, 1)))
makeToggle(water, "Auto Pay Bill", false, "autoPayBill")
makeToggle(water, "Auto Refill Water", false, "autoRefill")
refillThresholdInput = makeInput(water, "Refill at level (0 = only when empty)", "0")
makeToggle(water, "Inf Water Cup", false, "infCup")
makeToggle(water, "Auto Water Selected Crops", false, "autoWaterSelected")
waterTypeBase, waterTypeBody, waterTypeSelection = makeDropdown(water, "Water Type", {
	{ name = "Nearby Planting", rarity = "Common", desc = "Stay in place. Water plants within 10 studs, no teleport." },
	{ name = "Instant TP Planting", rarity = "Rare", desc = "Instantly teleport to each plant, water it, then return." },
	{ name = "Tween TP Planting", rarity = "Epic", desc = "Tween smoothly to each plant, water it, then return." },
}, { single = true })
makeToggle(water, "Auto Water All One By One", false, "autoWaterAll")
makeStat(water, "Water Logic", "Mode-based → live plant position → Farm.WaterPlant:FireServer(position)", C.green)
makeStat(water, "Cycle", "Sequential by crop type  |  auto-refill when cup empty  |  returns to start", C.sky)
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

seedplant = newPage("seedplant")
makeHeader(seedplant, "Seed Planting", C.green, "rbxassetid://120628031716892")
makeToggle(seedplant, "Auto Planting Seeds", false, "autoPlantSeeds")
makeStat(seedplant, "Trigger", "Finds empty soil spots on your farm and plants selected seeds", C.green)
makeStat(seedplant, "Range", "Nearby = 10 studs  |  TP modes = full own-farm reach", C.sky)
seedTypeBase, seedTypeBody, seedTypeSelection = makeDropdown(seedplant, "Seeds Type", {
	{ name = "Nearby Planting (Range 10)", rarity = "Common", desc = "Stay in place. Plant seeds in empty soil spots within 10 studs, no teleport." },
	{ name = "Instant TP Planting", rarity = "Rare", desc = "Instantly teleport to empty soil spots anywhere on your own farm, plant, then return." },
	{ name = "Tween TP Planting", rarity = "Epic", desc = "Tween smoothly to empty soil spots anywhere on your own farm, plant, then return." },
}, { single = true })
plantPatternBase, plantPatternBody, plantPatternSelection = makeDropdown(seedplant, "Planting Pattern", {
	{ name = "Row by Row", rarity = "Common", desc = "Plant in a left-to-right, top-to-bottom row pattern across the farm." },
	{ name = "Grid Spiral", rarity = "Rare", desc = "Plant in a spiral pattern starting from the center of the farm outward." },
	{ name = "Nearest First", rarity = "Epic", desc = "Plant at the closest available empty soil spot to your current position." },
	{ name = "Random", rarity = "Legendary", desc = "Plant at random available empty soil spots for unpredictable coverage." },
}, { single = true })
plantSeedsBase, plantSeedsBody, plantSeedsSelection = makeDropdown(seedplant, "Seeds to Plant", SEEDS)
makeStat(seedplant, "Planting Logic", "Scan farm for empty soil → TP to spot (if needed) → trigger plant action → next spot", C.green)
makeStat(seedplant, "Cycle", "0.5s between plantings  |  returns to your starting position", C.sky)
plantCountInput = makeInput(seedplant, "How Many to Plant (empty = no limit)", "")

-- Reset planting counter when the toggle is turned on
local _origPlantSetter = ToggleSetters.autoPlantSeeds
ToggleSetters.autoPlantSeeds = function(val)
	if val then totalPlantedCount = 0 end
	_origPlantSetter(val)
end

mainquest = newPage("mainquest")
makeHeader(mainquest, "Main Quest", C.gold, "rbxassetid://77830885604568")
makeToggle(mainquest, "Auto Claim Only Claimable Quest", false, "autoClaimQuests")
makeStat(mainquest, "Logic", "Checks Daily & Weekly quests via Quests.GetState, claims only ready ones via Quests.Deliver", C.green)
makeStat(mainquest, "Cycle", "Scans every 3s  |  claims claimable Daily and Weekly quests automatically", C.sky)
makeToggle(mainquest, "Auto Quest", false, "autoQuest")
questTypeBase, questTypeBody, questTypeSelection = makeDropdown(mainquest, "Quest Type", {
	{ name = "Instant TP", rarity = "Rare", desc = "Instantly teleport to Mr. Nonoy, deliver all ready quests, then return to your position." },
	{ name = "Tween TP", rarity = "Epic", desc = "Tween smoothly to Mr. Nonoy, deliver all ready quests, then return to your position." },
}, { single = true })
makeStat(mainquest, "Auto Quest Logic", "Scans Daily & Weekly quests → TP to Mr. Nonoy → delivers all quests with items in bag → returns to start", C.green)
makeStat(mainquest, "Auto Quest Cycle", "Scans every 5s  |  delivers all ready quests in one trip", C.sky)

mainPage = newPage("main")
makeHeader(mainPage, "Main Controls", C.gold, "rbxassetid://77830885604568")
para(mainPage, "One-tap controls for pet equipping and crop favorites. Select crops in the dropdown below, then use the buttons.", 1, 56)
mainCropBase, mainCropBody, mainCropSelection = makeDropdown(mainPage, "Crops", CROPS)
makeActionButton(mainPage, "One-Tap Equip All Pets", C.pink, function()
	local player = Players.LocalPlayer
	local character = player and player.Character
	if not character then return end
	local unequipped = 0
	for _, child in ipairs(character:GetChildren()) do
		if isPetInstance(child, character) then
			if UnequipPetRemote and UnequipPetRemote:IsA("RemoteEvent") then
				pcall(function() UnequipPetRemote:FireServer(child.Name) end)
			end
			unequipped += 1
		end
	end
	task.wait(0.5)
	pcall(runBestPetsCycle)
	notify("One-tap equip: unequipped " .. unequipped .. " pet(s), equipping best pets", C.pink)
end)
makeActionButton(mainPage, "Unfavorite All Crops", C.red, function()
	if not SetFavoriteRemote then notify("SetFavorite remote not found", C.red) return end
	local fired = 0
	for _, tool in ipairs(collectCropTools()) do
		local cropId = tool:GetAttribute("CropId")
		if cropId then
			pcall(function() SetFavoriteRemote:FireServer(cropId, false) end)
			tool:SetAttribute("Favorite", false)
			fired += 1
		end
	end
	notify("Unfavorited " .. fired .. " crop(s)", C.red)
end)
makeActionButton(mainPage, "Unfavorite Selected Crops", C.orange, function()
	if not SetFavoriteRemote then notify("SetFavorite remote not found", C.red) return end
	local selected = {}
	for name in pairs(mainCropSelection) do
		selected[normCropKey(name)] = true
	end
	local fired = 0
	for _, tool in ipairs(collectCropTools()) do
		local cropId = tool:GetAttribute("CropId")
		if cropId and selected[cropToolKey(tool)] then
			pcall(function() SetFavoriteRemote:FireServer(cropId, false) end)
			tool:SetAttribute("Favorite", false)
			fired += 1
		end
	end
	notify("Unfavorited " .. fired .. " selected crop(s)", C.orange)
end)
makeActionButton(mainPage, "Favorite All Crops", C.green, function()
	if not SetFavoriteRemote then notify("SetFavorite remote not found", C.red) return end
	local fired = 0
	for _, tool in ipairs(collectCropTools()) do
		local cropId = tool:GetAttribute("CropId")
		if cropId then
			pcall(function() SetFavoriteRemote:FireServer(cropId, true) end)
			tool:SetAttribute("Favorite", true)
			fired += 1
		end
	end
	notify("Favorited " .. fired .. " crop(s)", C.green)
end)
makeActionButton(mainPage, "Favorite Selected Crops", C.blue, function()
	if not SetFavoriteRemote then notify("SetFavorite remote not found", C.red) return end
	local selected = {}
	for name in pairs(mainCropSelection) do
		selected[normCropKey(name)] = true
	end
	local fired = 0
	for _, tool in ipairs(collectCropTools()) do
		local cropId = tool:GetAttribute("CropId")
		if cropId and selected[cropToolKey(tool)] then
			pcall(function() SetFavoriteRemote:FireServer(cropId, true) end)
			tool:SetAttribute("Favorite", true)
			fired += 1
		end
	end
	notify("Favorited " .. fired .. " selected crop(s)", C.blue)
end)

-- ==STOCK_PAGES==
seeds = newPage("seeds")
makeHeader(seeds, "Seeds", C.green, "rbxassetid://120628031716892")
seedsStatusStat = rightValueLabel(makeStat(seeds, "Auto-Buy Status", "OFF", C.gray))
seedsSelectedStat = rightValueLabel(makeStat(seeds, "Selected Seeds", "0", C.sky))
for i = 1, 6 do
	local cropId = CropConfig.ShopLineup[i]
	if cropId then makeStockRow(seeds, cropId .. " Seed") end
end
seedsBuyBase, seedsBuyBody, seedsBuySelection = makeDropdown(seeds, "Seeds to Buy", SEEDS)
makeToggle(seeds, "Auto Buy Seeds", false, "autoBuySeeds")

pets = newPage("pets")
makeHeader(pets, "Pet Eggs", C.pink, "rbxassetid://113316632422703")
petsStatusStat = rightValueLabel(makeStat(pets, "Auto-Buy Status", "OFF", C.gray))
petsSelectedStat = rightValueLabel(makeStat(pets, "Selected Eggs", "0", C.sky))
for _, egg in ipairs(EGGS) do
	makeStockRow(pets, egg.name)
end
eggsBuyBase, eggsBuyBody, eggsBuySelection = makeDropdown(pets, "Eggs to Buy", EGGS)
makeToggle(pets, "Auto Buy Eggs", false, "autoBuyEggs")

store = newPage("store")
makeHeader(store, "Supply Store", C.brown)
storeStatusStat = rightValueLabel(makeStat(store, "Auto-Buy Status", "OFF", C.gray))
storeSelectedStat = rightValueLabel(makeStat(store, "Selected Items", "0", C.sky))
storeBuyBase, storeBuyBody, storeBuySelection = makeDropdown(store, "Decorations to Buy", STORE_ITEMS)
makeToggle(store, "Store Auto Buy", false, "autoBuyStore")
decorBuyBase, decorBuyBody, decorBuySelection = makeDropdown(store, "Decoration Catalog", DECORATION_ITEMS)
makeToggle(store, "Auto Buy Decorations", false, "autoBuyDecor")


merchant = newPage("merchant")
makeHeader(merchant, "Trade", C.purple)
merchantStatusStat = rightValueLabel(makeStat(merchant, "Auto-Buy Status", "OFF", C.gray))
merchantSelectedStat = rightValueLabel(makeStat(merchant, "Selected Items", "0", C.sky))
local _merchantFilter
merchantSortBase, merchantSortBody, merchantSortSelection = makeDropdown(merchant, "Sort", {
	{ name = "All", rarity = "Common", desc = "Show all items (default)" },
	{ name = "Potion", rarity = "Rare", desc = "Show potions only" },
	{ name = "Gear", rarity = "Epic", desc = "Show gear only" },
	{ name = "Others", rarity = "Uncommon", desc = "Show seeds and other items" },
}, { single = true, onChange = function(sel) if _merchantFilter then _merchantFilter(sel) end end })
merchantBuyBase, merchantBuyBody, merchantBuySelection = makeDropdown(merchant, "Merchant Items", MERCHANT_ITEMS)
_merchantFilter = function(sel)
	local sortType = nil
	for k in pairs(sel) do sortType = k end
	local itemList = merchantBuyBody and merchantBuyBody:FindFirstChild("ItemList")
	if not itemList then return end
	for _, row in ipairs(itemList:GetChildren()) do
		if row:IsA("Frame") then
			local itemIdx = tonumber(row.Name:match("^Item_(%d+)$"))
			if itemIdx then
				local item = MERCHANT_ITEMS[itemIdx]
				if item then
					if not sortType or sortType == "All" then
						row.Visible = true
					elseif sortType == "Potion" then
						row.Visible = item.kind == "Potion"
					elseif sortType == "Gear" then
						row.Visible = item.kind == "Gear"
					elseif sortType == "Others" then
						row.Visible = item.kind ~= "Potion" and item.kind ~= "Gear"
					end
				end
			end
		end
	end
end
makeToggle(merchant, "Auto Buy Merchant", false, "autoBuyMerchant")

upgrades = newPage("upgrades")
makeHeader(upgrades, "Farm Upgrades", C.orange, "rbxassetid://124300905660565")
makeToggle(upgrades, "Auto Upgrade Plot (if affordable)", false, "autoUpgradePlot")
makeToggle(upgrades, "Auto Upgrade House (if affordable)", false, "autoUpgradeHouse")

eggs = newPage("eggs")
makeHeader(eggs, "Eggs", C.pink, "rbxassetid://113316632422703")
eggsBackpackStat = rightValueLabel(makeStat(eggs, "Unplaced (backpack)", "0", C.sky))
eggsReadyStat = rightValueLabel(makeStat(eggs, "Ready to hatch", "0", C.green))
eggsPlacedStat = rightValueLabel(makeStat(eggs, "Placed on farm", "0", C.gold))
makeDropdown(eggs, "Egg to Place", EGGS)
makeToggle(eggs, "Auto Place All Eggs", false, "autoPlaceAll")
makeToggle(eggs, "Auto Place Selected Eggs", false, "autoPlaceSelected")
makeToggle(eggs, "Auto Hatch All Ready Eggs", false, "autoHatchReady")

other = newPage("other")
makeHeader(other, "Other Features", C.gray)
makeToggle(other, "Auto Sleep", false, "autoSleep")
makeToggle(other, "Auto Codes (BAHAYKUBO, RELEASE + live codes)", false, "autoCodes")
makeToggle(other, "Anti-AFK", true, "antiAFK")
makeToggle(other, "Auto Equip All Best Pets", false, "autoBestPets")
makeToggle(other, "Farm Setup (claim free plot, skip tutorial)", false, "farmSetup")
-- ==UPDATE_PAGE==
update = newPage("update")
makeHeader(update, "Guide & Updates", C.gold, "rbxassetid://101953044632807")
makeStat(update, "Version", "7.2 Update Tab + Live Stats", C.gold)
makeStat(update, "Panel", "Bahay Kubo Garden Control Center", C.green)
makeStat(update, "Type", "Client-side LocalScript automation tool", C.sky)
makeStat(update, "Location", "StarterPlayerScripts.BahayKubo panel", C.purple)
makeStat(update, "Hotkey", "RightShift to show / hide", C.orange)

section(update, "Tab Guide — All Tabs Explained", 1)
para(update, "Dashboard: Shows live garden stats (money, plants, ripe fruits, eggs, session timer, auto-buy counter) and quick action buttons for farming/shopping profiles. Sub-tabs: Overview, Activity, Profiles, Alerts, Garden Index.", 2, 80)
para(update, "Main: The core automation hub. Sub-tabs: Harvest, Water, Sell, Rewards, Seed. Each sub-tab has toggles, dropdowns, and inputs for controlling that specific automation.", 3, 80)
para(update, "Stocks: Auto-buy configuration for all shop categories. Sub-tabs: Seeds, Pets (eggs), Store, Trade (merchant), Upgrades, Eggs, Other. Each has item dropdowns and auto-buy toggles.", 4, 80)
para(update, "Settings: UI customization and panel configuration. Sub-tabs: UI Settings (toggles + sliders), Defaults (filter settings), Panel Info (version + changelog).", 5, 80)
para(update, "About: Full documentation of the panel — features, navigation, keyboard shortcuts, and version changelog.", 6, 80)
para(update, "Update (this tab): Comprehensive guide explaining every tab, toggle, input, dropdown, and automation logic in the panel.", 7, 80)

section(update, "All Toggles Explained", 8)
makeStat(update, "Auto Planting Seeds", "Plants seeds in empty soil spots on your farm. Modes: Nearby (10 studs), Instant TP, Tween TP. Patterns: Row by Row, Grid Spiral, Nearest First.", C.leaf)
makeStat(update, "Auto Harvest Crops", "Harvests ripe fruits on your farm. Modes: Safe (10-stud range), Instant TP, Tween TP.", C.leaf)
makeStat(update, "Auto Harvest All Ready Ripe Crops", "Harvests ALL ripe fruits on your farm regardless of crop selection. Uses same Harvest Type mode.", C.leaf)
makeStat(update, "Auto Pay Bill", "Automatically pays the water bill at the Water Tap when owed.", C.gold)
makeStat(update, "Auto Refill Water", "Refills the water cup at the Water Tap when it drops to the refill threshold.", C.sky)
makeStat(update, "Inf Water Cup", "Keeps the water cup infinitely full (client-side).", C.blue)
makeStat(update, "Auto Water Selected Crops", "Waters only crops selected in the dropdown, sequentially by crop type (e.g. all mangga first, then all langka, then repeat). Uses Water Type mode. Auto-refills when cup is empty.", C.sky)
makeStat(update, "Auto Water All One By One", "Waters every plant on your farm sequentially, using Water Type mode.", C.sky)
makeStat(update, "Auto Sell All", "Sells all non-favorite backpack crops when backpack is full.", C.gold)
makeStat(update, "Auto Sell Selected", "Sells only selected crop types (uses favorite marking system).", C.gold)
makeStat(update, "Auto Sell Timer", "Sells automatically every X seconds (configurable input).", C.orange)
makeStat(update, "Auto Buy Seeds", "Buys selected seeds from the shop every 0.5s.", C.green)
makeStat(update, "Auto Buy Eggs", "Buys selected pet eggs from the shop every 0.5s.", C.pink)
makeStat(update, "Store Auto Buy", "Buys selected store items (gear, tools).", C.brown)
makeStat(update, "Auto Buy Decorations", "Buys selected decoration items from the store.", C.brown)
makeStat(update, "Auto Buy Merchant", "Buys selected items from the traveling merchant.", C.purple)
makeStat(update, "Auto Place All Eggs", "Places unplaced eggs on available soil spots.", C.pink)
makeStat(update, "Auto Place Selected Eggs", "Places only eggs selected in the dropdown.", C.pink)
makeStat(update, "Auto Hatch All Ready Eggs", "Hatches eggs that are ready via ProximityPrompt.", C.green)
makeStat(update, "Auto Upgrade Plot", "Upgrades the farm plot if affordable.", C.orange)
makeStat(update, "Auto Upgrade House", "Upgrades the farm house if affordable.", C.orange)
makeStat(update, "Auto Sleep", "Sleeps at the farm house automatically.", C.purple)
makeStat(update, "Auto Codes", "Redeems known codes (BAHAYKUBO, RELEASE, etc.) via Codes.Redeem.", C.gold)
makeStat(update, "Anti-AFK", "Prevents idle disconnect. Locked ON by default.", C.blue)
makeStat(update, "Auto Equip All Best Pets", "Equips all best pets automatically.", C.pink)
makeStat(update, "Auto Claim Achievements", "Claims achievement rewards automatically.", C.orange)
makeStat(update, "Auto Claim Index", "Claims index collection rewards automatically.", C.orange)
makeStat(update, "Auto Claim Pass", "Claims season pass rewards automatically.", C.orange)
makeStat(update, "Farm Setup", "Claims a free plot and skips the tutorial.", C.green)
makeStat(update, "Notifications", "Shows toast popup notifications for actions.", C.gray)
makeStat(update, "Show Status Bar", "Displays the bottom status bar with live info.", C.gray)
makeStat(update, "Auto Close Dropdowns", "Closes other dropdowns when opening a new one.", C.gray)
makeStat(update, "Compact Layout", "Reduces toggle and button heights.", C.gray)
makeStat(update, "Show Helper Text", "Shows contextual hints and tips.", C.gray)
makeStat(update, "High Contrast Text", "Increases text contrast for readability.", C.gray)
makeStat(update, "Show Icons", "Toggles stud icon visibility on buttons.", C.gray)
makeStat(update, "Stud Icon Style", "Switches between stud-style icon display.", C.gray)
makeStat(update, "Lock Panel Position", "Prevents dragging the panel.", C.gray)
makeStat(update, "Silent Mode", "Suppresses all toast popup notifications.", C.gray)
makeStat(update, "Prefer Rare Mutations", "Prioritizes rare mutations in harvest filter.", C.purple)
makeStat(update, "Ignore Common Drops", "Skips common crop drops during harvest.", C.gray)
makeStat(update, "Only Buy Needed Seeds", "Only buys seeds you don't already have.", C.green)
makeStat(update, "Only Hatch Selected Eggs", "Only hatches eggs selected in the dropdown.", C.pink)

section(update, "All Inputs Explained", 9)
makeStat(update, "Refill at level (0 = only when empty)", "Water page. Sets the threshold for auto-refill. 0 means refill only when cup is empty. Higher values trigger refill earlier.", C.sky)
makeStat(update, "Min kg to harvest", "Harvest page. Only harvests fruits weighing at least this many kg. Default: 1.15.", C.leaf)
makeStat(update, "Backpack Full At (crops)", "Sell page. Threshold for Auto Sell All. When backpack reaches this count, sells. Default: 58.", C.gold)
makeStat(update, "Auto Sell Every (seconds)", "Sell page. Interval for Auto Sell Timer. Sells every X seconds. Default: 25.", C.orange)
makeStat(update, "Minimum Crop Weight", "Defaults page. Global minimum weight filter. Default: 1.15.", C.blue)

section(update, "All Dropdowns Explained", 10)
makeStat(update, "Harvest Type", "Safe Nearby (10 studs, no TP) / Instant TP (teleport to fruit) / Tween TP (smooth move to fruit).", C.leaf)
makeStat(update, "Harvest Filter", "Whitelist (only selected crops) / Blocklist (everything except selected).", C.leaf)
makeStat(update, "Crops (Harvest)", "Select which crops to harvest based on filter mode.", C.leaf)
makeStat(update, "Mutation", "Filter harvest by mutation type (Normal, Wet, Frozen, etc.).", C.purple)
makeStat(update, "Water Type", "Nearby Planting (10 studs, no TP) / Instant TP Planting (teleport to plant) / Tween TP Planting (smooth move to plant). Controls how the player reaches each plant during watering.", C.sky)
makeStat(update, "Crops (Water)", "Select which crops to water when Auto Water Selected is on. Plants are watered sequentially by crop type.", C.sky)
makeStat(update, "Crops to Sell", "Select which crop types to sell. Uses favorite-marking system.", C.gold)
makeStat(update, "Seeds to Buy", "Select which seeds to auto-buy from the shop.", C.green)
makeStat(update, "Eggs to Buy", "Select which pet eggs to auto-buy.", C.pink)
makeStat(update, "Store to Buy", "Select store items (gear, tools) to auto-buy.", C.brown)
makeStat(update, "Decorations to Buy", "Select decoration items to auto-buy.", C.brown)
makeStat(update, "Merchant Items", "Select merchant items to auto-buy.", C.purple)
makeStat(update, "Egg to Place", "Select which egg type to place on soil.", C.pink)
makeStat(update, "Crop / Mutation / Egg Catalog", "Dashboard Garden Index. Browse all registered crops, mutations, and eggs.", C.green)

section(update, "Automation Logic Explained", 11)
para(update, "Harvest Logic: The panel scans your farm (Farm_<UserId>) for plants with ripe fruits. Safe mode triggers ProximityPrompt within 10 studs. Instant/Tween modes teleport or tween to each fruit, trigger the prompt, then return to start. All triggers use direct ProximityPrompt activation — no key simulation.", 12, 76)
para(update, "Water Logic: Uses the selected Water Type mode (Nearby, Instant TP, or Tween TP) to reach each thirsty plant, then calls Farm.WaterPlant:FireServer(position). Plants are watered sequentially by crop type (e.g. all mangga first, then all langka, then repeat). When the water cup reaches 0, auto-refill is triggered automatically and the cycle continues. Refill also triggers when cup water drops to the threshold set in the input field.", 13, 86)
para(update, "Sell Logic: Auto Sell All fires when backpack count reaches the threshold. Auto Sell Selected marks non-selected crops as favorites (the game keeps favorites), then sells. Auto Sell Timer fires on a configurable interval.", 14, 76)
para(update, "Buy Logic: Auto-buy fires Shop.BuySeed, Pets.BuyEgg, Store.Buy, or Merchant.Buy remotes every 0.5s for each selected item. All calls use pcall for safety.", 15, 76)
para(update, "Egg Logic: Auto Place scans for unplaced eggs in backpack and available soil spots, then calls Pets.PlaceEgg. Auto Hatch scans for ready eggs and fires their ProximityPrompt.", 16, 76)
para(update, "Codes Logic: Iterates through known codes and calls Codes.Redeem:InvokeServer for each. Includes BAHAYKUBO, RELEASE, and other live codes.", 17, 76)
para(update, "Claim Logic: Auto Claims fire Achievements.Claim, Index.Claim, and Pass.Claim remotes for available rewards.", 18, 76)
para(update, "Anti-AFK: Sends periodic input to prevent idle disconnect. Locked ON by default for safety.", 19, 76)
para(update, "Farm Detection: Uses Farm_<UserId> in workspace.ActiveFarms. Falls back to OwnerUserId attribute check. All farm-specific actions verify ownership first.", 20, 76)

section(update, "Live Stats Explained", 21)
makeStat(update, "Harvest > Money", "Live money from leaderstats, updates every 0.5s.", C.gold)
makeStat(update, "Harvest > Player Plot", "Shows farm name or 'No farm found'.", C.green)
makeStat(update, "Harvest > Plants", "Total plant count on your farm.", C.sky)
makeStat(update, "Harvest > Harvested", "Total crops harvested this session.", C.leaf)
makeStat(update, "Harvest > Ripe Fruits", "Current count of ripe fruits ready to pick.", C.green)
makeStat(update, "Water > Bill", "Live water bill amount from game attributes.", C.gold)
makeStat(update, "Water > Water Cup", "Current water level vs cup capacity.", C.sky)
makeStat(update, "Sell > Backpack Crops", "Number of crops currently in backpack.", C.sky)
makeStat(update, "Stocks > Auto-Buy Status", "Shows ON/OFF for each auto-buy category.", C.gray)
makeStat(update, "Stocks > Selected Count", "Number of items selected in each dropdown.", C.sky)
makeStat(update, "Eggs > Unplaced/Ready/Placed", "Live egg counts from backpack and farm.", C.pink)

section(update, "Sliders Explained", 22)
makeStat(update, "Panel Opacity", "Controls panel background transparency. 0% = solid, 60% = very transparent. Default: 40%.", C.gray)
makeStat(update, "Toast Duration", "How long toast notifications stay visible. 1–5 seconds. Default: 2.5s.", C.gray)
makeStat(update, "Dropdown Height", "Height of dropdown list panels. 220–520px. Default: 330px.", C.gray)

section(update, "Bulk Actions Explained", 23)
makeStat(update, "Farming Profile", "Enables Auto Harvest, Auto Refill, Auto Sell All, Auto Best Pets.", C.leaf)
makeStat(update, "Shopping Profile", "Enables all auto-buy toggles (seeds, eggs, store, decor, merchant).", C.green)
makeStat(update, "Enable All Auto-Buy", "Turns on all 5 auto-buy toggles independently.", C.blue)
makeStat(update, "Enable All Automation", "Turns on all automation toggles at once.", C.green)
makeStat(update, "Disable All Automation", "Turns off every automation toggle.", C.red)
makeStat(update, "Reset All Toggles", "Resets all master-target toggles to OFF.", C.red)
makeStat(update, "Center Panel", "Moves panel to center of screen.", C.blue)
makeStat(update, "Reset UI View", "Resets panel position, minimization, and scroll.", C.orange)
makeStat(update, "Apply UI Settings", "Applies all UI settings (opacity, compact, contrast, etc.).", C.green)
makeStat(update, "Apply Sell Favorites", "Manually applies favorite-marking for selected sell crops.", C.gold)

section(update, "Keyboard Shortcuts", 24)
makeStat(update, "RightShift", "Show / hide the panel.", C.green)
makeStat(update, "Home", "Jump to top of scroll area.", C.sky)
makeStat(update, "End", "Jump to bottom of scroll area.", C.orange)
makeStat(update, "PageUp / PageDown", "Scroll up / down by one page.", C.purple)
makeStat(update, "Left / Right arrows", "Fine-tune slider values when a slider is focused.", C.gold)

section(update, "Version History", 25)
makeStat(update, "v7.2", "Added Update tab with full guide. Refill threshold input field. Live stats on all pages.", C.gold)
makeStat(update, "v7.1", "Dashboard formatting, session timer, auto-buy counter, changelog, keyboard shortcuts.", C.green)
makeStat(update, "v7.0", "Live dashboard stats, more quick actions, silent mode, reset toggles, consolidated about.", C.sky)
makeStat(update, "v6.0", "Auto egg placement, auto hatch, auto codes, auto claim rewards, anti-AFK lock.", C.orange)
makeStat(update, "v5.0", "Auto buy store + decorations + merchant with dynamic config loading.", C.purple)
makeStat(update, "v4.0", "Auto harvest with Safe/Instant/Tween TP modes, auto water with Gripo refill.", C.pink)
makeStat(update, "v3.0", "Auto sell with favorites protection, timed auto sell, backpack tracking.", C.blue)
makeStat(update, "v2.0", "Dropdown system with search, select all, deselect all, rarity coloring.", C.gray)
makeStat(update, "v1.0", "Initial studded blocky cartoon panel with rail navigation.", C.gray)

section(update, "Safety Notes", 26)
para(update, "All automation uses pcall for error safety. Remote calls are validated before firing. Farm ownership is checked using Farm_<UserId> with OwnerUserId fallback. Config modules are loaded dynamically from ReplicatedStorage.Shared.Config. The panel is a client-side tool and does not modify server-side game state directly.", 27, 76)

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
notify("Bahay Kubo Garden v7.1 loaded", C.green)

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
	-- Live dashboard stats: money from leaderstats, plant/ripe/egg counts from farm
	local lp = Players.LocalPlayer
	local leaderstats = lp:FindFirstChild("leaderstats")
	local money
	if leaderstats then
		money = leaderstats:FindFirstChild("Pesos") or leaderstats:FindFirstChild("Money") or leaderstats:FindFirstChild("Coins") or leaderstats:FindFirstChild("Cash")
		if not money then
			local currency = leaderstats:FindFirstChild("Currency")
			if currency then
				money = currency:FindFirstChild("Pesos") or currency:FindFirstChild("Cash") or currency:FindFirstChild("Value")
			end
		end
	end
	if money then
		dashMoney.Text = "₱" .. formatMoney(tonumber(money.Value) or 0)
	end
	local farm = getMyFarm()
	if farm then
		local plants = farm:FindFirstChild("Plants")
		local pCount, rCount = 0, 0
		if plants then
			local now = os.time()
			for _, plant in plants:GetChildren() do
				pCount += 1
				local fruits = plant:FindFirstChild("Fruits")
				if fruits then
					for _, fruit in fruits:GetChildren() do
						local ripeAt = fruit:GetAttribute("RipeAt")
						if not ripeAt or ripeAt <= now then rCount += 1 end
					end
				end
			end
		end
		dashPlants.Text = tostring(pCount)
		dashRipe.Text = tostring(rCount)
		local eggsFolder = farm:FindFirstChild("Eggs")
		dashEggs.Text = eggsFolder and tostring(#eggsFolder:GetChildren()) or "0"
	else
		dashPlants.Text = "No farm"
		dashRipe.Text = "0"
		dashEggs.Text = "0"
	end
	dashHarvested.Text = tostring(harvestedTotal or 0)
	dashSession.Text = formatDuration(os.time() - sessionStartTime)
	local autoBuyCount = 0
	for _, k in {"autoBuySeeds","autoBuyEggs","autoBuyStore","autoBuyDecor","autoBuyMerchant"} do
		if ToggleState[k] then autoBuyCount += 1 end
	end
	dashAutoBuy.Text = tostring(autoBuyCount) .. "/5"
	liveDot.BackgroundColor3 = minimized and C.orange or C.green
	local moneyStr = "₱0"
	if money and money.Value then moneyStr = "₱" .. formatMoney(money.Value) end
	rbRight.Text = string.format("LIVE  •  %s  •  %s", moneyStr, os.date("%I:%M %p"))
	statusText.Text = string.format("BahayKubo v7.1  •  %s  •  %d active  •  %s", moneyStr, enabled, os.date("%I:%M:%S %p"))
	-- Water page live stats
	local cw, cs = getCupLevels()
	if waterCupStat then waterCupStat.Text = tostring(cw) .. "/" .. tostring(cs) end
	local billAmt = 0
	if farm then
		billAmt = farm:GetAttribute("BillAmount") or farm:GetAttribute("WaterBill") or 0
		local billObj = farm:FindFirstChild("Bill")
		if billObj then
			if billObj:IsA("IntValue") or billObj:IsA("NumberValue") then
				billAmt = billObj.Value
			elseif billObj:IsA("Model") or billObj:IsA("Folder") then
				local amt = billObj:FindFirstChild("Amount") or billObj:FindFirstChild("Value")
				if amt and (amt:IsA("IntValue") or amt:IsA("NumberValue")) then
					billAmt = amt.Value
				end
			end
		end
	end
	if waterBillStat then waterBillStat.Text = "₱" .. formatMoney(billAmt) end
	if harvestMoneyStat and money then harvestMoneyStat.Text = "₱" .. formatMoney(money.Value) end

	-- Stocks page live status displays
	if seedsStatusStat then
		seedsStatusStat.Text = ToggleState.autoBuySeeds and "ON" or "OFF"
		seedsStatusStat.TextColor3 = ToggleState.autoBuySeeds and C.green or C.gray
	end
	if seedsSelectedStat then
		local sn = 0; for _ in pairs(seedsBuySelection) do sn += 1 end
		seedsSelectedStat.Text = tostring(sn)
	end
	if petsStatusStat then
		petsStatusStat.Text = ToggleState.autoBuyEggs and "ON" or "OFF"
		petsStatusStat.TextColor3 = ToggleState.autoBuyEggs and C.green or C.gray
	end
	if petsSelectedStat then
		local pn = 0; for _ in pairs(eggsBuySelection) do pn += 1 end
		petsSelectedStat.Text = tostring(pn)
	end
	if storeStatusStat then
		local stOn = ToggleState.autoBuyStore or ToggleState.autoBuyDecor
		storeStatusStat.Text = stOn and "ON" or "OFF"
		storeStatusStat.TextColor3 = stOn and C.green or C.gray
	end
	if storeSelectedStat then
		local stn = 0; for _ in pairs(storeBuySelection) do stn += 1 end; for _ in pairs(decorBuySelection) do stn += 1 end
		storeSelectedStat.Text = tostring(stn)
	end
	if merchantStatusStat then
		merchantStatusStat.Text = ToggleState.autoBuyMerchant and "ON" or "OFF"
		merchantStatusStat.TextColor3 = ToggleState.autoBuyMerchant and C.green or C.gray
	end
	if merchantSelectedStat then
		local mn = 0; for _ in pairs(merchantBuySelection) do mn += 1 end
		merchantSelectedStat.Text = tostring(mn)
	end
	-- Eggs page live counts
	local eggBackpack = 0
	for _, container in ipairs({ lp:FindFirstChildOfClass("Backpack"), lp.Character }) do
		if container then
			for _, item in ipairs(container:GetChildren()) do
				if item:IsA("Tool") and EGG_ID_MAP[item.Name] then eggBackpack += 1 end
			end
		end
	end
	if eggsBackpackStat then eggsBackpackStat.Text = tostring(eggBackpack) end
	if farm then
		local eggsFolder = farm:FindFirstChild("Eggs")
		local placedCount = 0
		local readyCount = 0
		if eggsFolder then
			placedCount = #eggsFolder:GetChildren()
			for _, egg in ipairs(eggsFolder:GetChildren()) do
				local root = egg:FindFirstChild("Root", true)
				if root then
					local hatchPrompt = root:FindFirstChild("HatchPrompt")
					if hatchPrompt and hatchPrompt:IsA("ProximityPrompt") and hatchPrompt.Enabled then
						readyCount += 1
					end
				end
			end
		end
		if eggsPlacedStat then eggsPlacedStat.Text = tostring(placedCount) end
		if eggsReadyStat then eggsReadyStat.Text = tostring(readyCount) end
	else
		if eggsPlacedStat then eggsPlacedStat.Text = "No farm" end
		if eggsReadyStat then eggsReadyStat.Text = "0" end
	end

	refreshFarmStats()
	statusBar.Visible = uiSettings.showStatusBar and not minimized
end)

-- ==HARVEST_AUTOMATION==
-- Auto Harvest scans the local player's own farm (Farm_<UserId>) for ripe fruits of the crops
-- selected in the "Crops" dropdown and triggers their HarvestPrompt (Plants.<Crop>.Fruits.Fruit.HarvestPrompt).
-- Modes: Safe Nearby (range 10), Instant TP (range 10), Tween TP (range 10).
HARVEST_RANGE = 10
-- Harvest tuning: slower main loop cadence, faster per-fruit trigger and tween teleport.
HARVEST_LOOP_DELAY = 0.65
HARVEST_TRIGGER_DELAY = 0.4
HARVEST_TWEEN_SPEED = 32
HARVEST_TWEEN_MIN = 0.05
HARVEST_TWEEN_MAX = 0.50
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

WATER_NEARBY_RANGE = 10
WATER_TWEEN_SPEED = 16
WATER_TWEEN_MIN = 0.10
WATER_TWEEN_MAX = 1.00

function currentWaterMode()
	for name in pairs(waterTypeSelection) do
		if name == "Instant TP Planting" then return "instant" end
		if name == "Tween TP Planting" then return "tween" end
	end
	return "nearby"
end

function currentSeedType()
	for name in pairs(seedTypeSelection) do
		if name == "Instant TP Planting" then return "instant" end
		if name == "Tween TP Planting" then return "tween" end
	end
	return "nearby"
end

function currentPlantPattern()
	for name in pairs(plantPatternSelection) do
		if name == "Grid Spiral" then return "spiral" end
		if name == "Nearest First" then return "nearest" end
		if name == "Random" then return "random" end
	end
	return "row"
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
	while elapsed < duration and hrp.Parent and character.Parent and (ToggleState.autoHarvest or ToggleState.autoHarvestAllReady) do
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
		if not ToggleState.autoHarvest then break end
		local fruits = plant:FindFirstChild("Fruits")
		if fruits then
			for _, fruit in ipairs(fruits:GetChildren()) do
				if not ToggleState.autoHarvest then break end
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

-- Auto Harvest All Ready Ripe Crops: harvests every ripe fruit on the farm
-- regardless of crop selection filter, using the same Harvest Type mode.
function runHarvestAllReadyCycle()
	local player = Players.LocalPlayer
	local character = player and player.Character
	if not character then return end
	local farm = getActiveFarm()
	if not farm then return end
	local plantsFolder = farm:FindFirstChild("Plants")
	if not plantsFolder then return end

	local mode = currentHarvestMode()
	local originPivot = character:GetPivot()
	local originPos = originPivot.Position
	local moved = false
	local harvestedNow = 0
	local ripeCount = 0

	for _, plant in ipairs(plantsFolder:GetChildren()) do
		if not ToggleState.autoHarvestAllReady then break end
		local fruits = plant:FindFirstChild("Fruits")
		if fruits then
			for _, fruit in ipairs(fruits:GetChildren()) do
				if not ToggleState.autoHarvestAllReady then break end
				local prompt = findHarvestPrompt(fruit)
				if prompt and prompt.Enabled then
					ripeCount += 1
					local fruitPosition
					if fruit:IsA("BasePart") then
						fruitPosition = fruit.Position
					else
						fruitPosition = fruit:GetPivot().Position
					end
					local distance = (fruitPosition - originPos).Magnitude

					if mode == "safe" then
						if distance <= HARVEST_RANGE then
							if triggerHarvestPrompt(prompt) then
								harvestedNow += 1
							end
						end
					else
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
		task.wait(HARVEST_LOOP_DELAY)
		if ToggleState.autoHarvestAllReady then
			pcall(runHarvestAllReadyCycle)
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
	FarmPlantSeedRemote = farmFolder and farmFolder:FindFirstChild("PlantSeed") or nil
	FarmGetOccupiedRemote = farmFolder and farmFolder:FindFirstChild("GetOccupied") or nil
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

function getRefillThreshold()
	local box = refillThresholdInput and refillThresholdInput:FindFirstChildWhichIsA("TextBox")
	local n = tonumber(box and box.Text)
	return (n and n >= 0) and n or 0
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
	if refillBusy or wateringBusy or plantingBusy then return end
	local player = Players.LocalPlayer
	local character = player.Character
	if not (character and character.Parent) then return end
	local canWater, canSize = getCupLevels()
	local threshold = getRefillThreshold()
	if canWater > threshold then return end

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
	if selectedOnly then
		-- Sort by crop name so plants of the same type are grouped together
		-- for sequential watering (e.g. all mangga first, then all langka, then repeat).
		table.sort(list, function(a, b)
			local ca = normCropKey(a:GetAttribute("CropName") or a.Name)
			local cb = normCropKey(b:GetAttribute("CropName") or b.Name)
			return ca < cb
		end)
	else
		-- "All" mode: shuffle for random watering order
		for i = #list, 2, -1 do
			local j = math.random(i)
			list[i], list[j] = list[j], list[i]
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

function getPlantBasePosition(plant)
	-- The server maps the position sent to WaterPlant back onto the soil spot
	-- (the game's own WateringController raycasts onto the spot surface and fires
	-- that hit point). Plants carry their exact base point in the BaseX/BaseY/
	-- BaseZ attributes, which is the same coordinate the spot raycast produces.
	-- Always prefer that over the model's live pivot, which floats above the
	-- soil and can be offset by animation/scale.
	if not (plant and plant.Parent) then return nil end
	local baseX = plant:GetAttribute("BaseX")
	local baseY = plant:GetAttribute("BaseY")
	local baseZ = plant:GetAttribute("BaseZ")
	if typeof(baseX) == "number" and typeof(baseY) == "number" and typeof(baseZ) == "number" then
		return Vector3.new(baseX, baseY, baseZ)
	end
	-- Fallback for plants without base attributes: project the model pivot
	-- down to the soil level recorded on the farm's spots.
	local pos = getPlantWorldPosition(plant)
	if pos then
		return Vector3.new(pos.X, baseY or pos.Y, pos.Z)
	end
	return nil
end

function waterPlantAtPosition(character, plant, mode)
	-- Send the plant's base position (BaseX/BaseY/BaseZ), the same coordinate the
	-- game's WateringController raycast produces on the soil spot, so the server
	-- resolves it to the correct plant. Never a hard-coded point.
	local target = getPlantBasePosition(plant)
	if not target then return false end
	if not (WaterPlantRemote and WaterPlantRemote:IsA("RemoteEvent")) then return false end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	local originPos = hrp and hrp.Position or character:GetPivot().Position
	local distance = (target - originPos).Magnitude
	mode = mode or "nearby"

	if mode == "nearby" then
		-- Nearby: only water if within range, no teleport
		if distance > WATER_NEARBY_RANGE then return false end
	elseif mode == "instant" then
		-- Instant TP: teleport directly to the plant
		character:PivotTo(CFrame.new(target + Vector3.new(0, 3, 0)))
		task.wait(0.08)
	elseif mode == "tween" then
		-- Tween TP: smoothly move to the plant
		if distance > 0.5 then
			tweenCharacterTo(character, target + Vector3.new(0, 3, 0))
		end
		task.wait(0.05)
	end

	-- Always send the selected plant's current world position, never a hard-coded point.
	local ok = pcall(function()
		WaterPlantRemote:FireServer(target)
	end)
	if not ok then return false end
	task.wait(WATER_POUR_DELAY)
	return true
end

function runWaterCycle(mode)
	if wateringBusy or refillBusy or plantingBusy then return end
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

	local waterMode = currentWaterMode()
	wateringBusy = true
	local originPivot = character:GetPivot()
	local poured = 0

	holdWaterCup(character, tool)

	for _, plant in ipairs(list) do
		if not (character.Parent and gui.Parent and plant.Parent) then break end
		if waterPlantAtPosition(character, plant, waterMode) then
			poured += 1
		end
		local water = getCupLevels()
		if water <= 0 then break end
	end

	-- Only return to origin for TP modes (nearby mode never moved)
	if character.Parent and (waterMode == "instant" or waterMode == "tween") then
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
-- When auto-water is active and the cup is empty, auto-refill is triggered
-- automatically so the watering cycle can continue without manual intervention.
task.spawn(function()
	while gui.Parent do
		task.wait(0.5)
		if ToggleState.autoRefill then
			pcall(runRefillCycle)
		end
		if ToggleState.autoWaterSelected then
			local canWater = getCupLevels()
			if canWater <= 0 then
				pcall(runRefillCycle)
			end
			pcall(runWaterCycle, "selected")
		elseif ToggleState.autoWaterAll then
			local canWater = getCupLevels()
			if canWater <= 0 then
				pcall(runRefillCycle)
			end
			pcall(runWaterCycle, "all")
		end
	end
end)

-- Auto Plant Seeds automation: finds empty soil spots on the farm and plants
-- the selected seeds using the chosen planting type (nearby/instant/tween) and
-- planting pattern (row by row / grid spiral / nearest first).
plantingBusy = false
totalPlantedCount = 0

function getPlantCount()
	local box = plantCountInput and plantCountInput:FindFirstChildWhichIsA("TextBox")
	local n = tonumber(box and box.Text)
	return (n and n > 0) and math.floor(n) or nil
end

function runPlantSeedsCycle()
	if plantingBusy or wateringBusy or refillBusy then return end
	if not FarmPlantSeedRemote or not FarmPlantSeedRemote:IsA("RemoteEvent") then return end
	local player = Players.LocalPlayer
	local character = player and player.Character
	if not (character and character.Parent) then return end
	local farm = getActiveFarm()
	if not farm then return end

	-- Collect selected seeds
	local selectedSeeds = {}
	for seedName in pairs(plantSeedsSelection) do
		table.insert(selectedSeeds, seedName)
	end
	if #selectedSeeds == 0 then return end

	-- Check if we've already reached the planting limit
	local plantLimit = getPlantCount()
	if plantLimit and totalPlantedCount >= plantLimit then
		if ToggleSetters.autoPlantSeeds then
			ToggleSetters.autoPlantSeeds(false)
			notify("Planting limit reached (" .. plantLimit .. " seeds planted)", C.gold)
		end
		return
	end

	local spots = getAvailablePlantSpots(farm)
	if #spots == 0 then return end

	-- Sort spots based on planting pattern
	local pattern = currentPlantPattern()
	if pattern == "row" then
		table.sort(spots, function(a, b)
			if a.localX == b.localX then return a.localZ < b.localZ end
			return a.localX < b.localX
		end)
	elseif pattern == "spiral" then
		local cx, cz = 0, 0
		for _, s in ipairs(spots) do
			cx += s.localX
			cz += s.localZ
		end
		cx /= #spots
		cz /= #spots
		table.sort(spots, function(a, b)
			local da = (a.localX - cx)^2 + (a.localZ - cz)^2
			local db = (b.localX - cx)^2 + (b.localZ - cz)^2
			return da < db
		end)
	elseif pattern == "nearest" then
		local hrp = character:FindFirstChild("HumanoidRootPart")
		local charPos = hrp and hrp.Position or character:GetPivot().Position
		table.sort(spots, function(a, b)
			local da = (a.worldPos - charPos).Magnitude
			local db = (b.worldPos - charPos).Magnitude
			return da < db
		end)
	elseif pattern == "random" then
		for i = #spots, 2, -1 do
			local j = math.random(1, i)
			spots[i], spots[j] = spots[j], spots[i]
		end
	end

	local seedMode = currentSeedType()
	plantingBusy = true
	local originPivot = character:GetPivot()
	local planted = 0

	-- Wrap the planting loop in pcall so plantingBusy is always reset
	local ok, err = pcall(function()
		for i, spotInfo in ipairs(spots) do
			if not (character.Parent and gui.Parent and ToggleState.autoPlantSeeds) then break end
			-- Check planting limit
			if plantLimit and totalPlantedCount + planted >= plantLimit then break end
			-- Pick a seed (cycle through selected seeds in order)
			local seedName = selectedSeeds[(i - 1) % #selectedSeeds + 1]
			local target = spotInfo.worldPos
			local hrp = character:FindFirstChild("HumanoidRootPart")
			local originPos = hrp and hrp.Position or character:GetPivot().Position
			local distance = (target - originPos).Magnitude

			if seedMode == "nearby" then
				if distance > 10 then continue end
			elseif seedMode == "instant" then
				character:PivotTo(CFrame.new(target))
				task.wait(0.2)
			elseif seedMode == "tween" then
				if distance > 0.5 then
					tweenCharacterTo(character, target)
				end
				task.wait(0.15)
			end

			-- Pass the world position as the second argument, matching the game's
			-- PlantingController which calls FireServer(seedName, worldPosition).
			local plantOk = pcall(function()
				FarmPlantSeedRemote:FireServer(seedName, target)
			end)
			if plantOk then
				planted += 1
			end
			task.wait(0.5)
		end
	end)

	if not ok then
		warn("[BahayKuboGarden] runPlantSeedsCycle error: " .. tostring(err))
	end

	totalPlantedCount = totalPlantedCount + planted

	-- Return to origin for TP modes
	if character and character.Parent and (seedMode == "instant" or seedMode == "tween") then
		character:PivotTo(originPivot)
	end
	plantingBusy = false

	-- Check if we've reached the planting limit after this cycle
	if plantLimit and totalPlantedCount >= plantLimit then
		if ToggleSetters.autoPlantSeeds then
			ToggleSetters.autoPlantSeeds(false)
			notify("Planting limit reached (" .. plantLimit .. " seeds planted)", C.gold)
		end
	end

	return planted
end

-- Auto Plant Seeds loop
task.spawn(function()
	while gui.Parent do
		task.wait(0.5)
		if ToggleState.autoPlantSeeds then
			pcall(runPlantSeedsCycle)
		end
	end
end)

-- ==BILL_AUTOMATION==
-- Auto Pay Bill: fires Farm.PayBill:FireServer() whenever the player has an
-- outstanding water bill. Checks the Bill attribute on the farm and only fires
-- when a bill is actually due, avoiding unnecessary remote calls.
FarmPayBillRemote = RemotesFolder and RemotesFolder:FindFirstChild("Farm") and RemotesFolder.Farm:FindFirstChild("PayBill") or nil

function runPayBillCycle()
	if not FarmPayBillRemote or not FarmPayBillRemote:IsA("RemoteEvent") then return end
	local farm = getActiveFarm()
	if not farm then return end
	-- Check for outstanding bill via farm attributes
	local billAmount = farm:GetAttribute("BillAmount") or farm:GetAttribute("WaterBill") or 0
	if billAmount <= 0 then
		-- Also check if there's a Bill folder or object on the farm
		local billObj = farm:FindFirstChild("Bill")
		if billObj then
			if billObj:IsA("IntValue") or billObj:IsA("NumberValue") then
				billAmount = billObj.Value
			elseif billObj:IsA("Model") or billObj:IsA("Folder") then
				local amount = billObj:FindFirstChild("Amount") or billObj:FindFirstChild("Value")
				if amount and (amount:IsA("IntValue") or amount:IsA("NumberValue")) then
					billAmount = amount.Value
				end
			end
		end
	end
	if billAmount <= 0 then return end
	-- Check if player can afford the bill
	local money = getLeaderstatMoney()
	if money < billAmount then return end
	pcall(function() FarmPayBillRemote:FireServer() end)
	notify("Water bill paid: ₱" .. formatMoney(billAmount), C.sky)
end

task.spawn(function()
	while gui.Parent do
		task.wait(3)
		if ToggleState.autoPayBill then
			pcall(runPayBillCycle)
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

AUTOMATION_KEYS = { "autoHarvest", "autoHarvestAllReady", "autoWaterSelected", "autoWaterAll", "autoRefill", "autoPlantSeeds" }

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

-- ==SHOP_AUTOMATION==
-- Auto Buy Seeds: cycle through the selected seeds in the "Seeds to Buy" dropdown
-- at 0.5s per seed using Shop.BuySeed:FireServer(seedName). If the player selected
-- Kalamansi and Saging, the loop fires Kalamansi → 0.5s → Saging → 0.5s → repeat.
ShopRemotes = RemotesFolder and RemotesFolder:FindFirstChild("Shop")
BuySeedRemote = ShopRemotes and ShopRemotes:FindFirstChild("BuySeed")

task.spawn(function()
	while gui.Parent do
		if ToggleState.autoBuySeeds and BuySeedRemote and BuySeedRemote:IsA("RemoteEvent") then
			local selected = {}
			for name in pairs(seedsBuySelection) do
				table.insert(selected, name)
			end
			if #selected > 0 then
				for _, seedName in ipairs(selected) do
					if not (gui.Parent and ToggleState.autoBuySeeds) then break end
					pcall(function()
						BuySeedRemote:FireServer(seedName)
					end)
					task.wait(0.5)
				end
			else
				-- No seeds selected: buy the first shop seed as a safe default.
				local firstSeed = CropConfig.ShopLineup and CropConfig.ShopLineup[1]
				if firstSeed then
					pcall(function()
						BuySeedRemote:FireServer(firstSeed)
					end)
				end
				task.wait(0.5)
			end
		else
			task.wait(0.5)
		end
	end
end)

-- ==EGG_BUY_AUTOMATION==
-- Auto Buy Eggs: cycle through the selected eggs in the "Eggs to Buy" dropdown
-- at 0.5s per egg type using Pets.BuyEgg:FireServer(eggId). If the player selected
-- AncientEgg and BasicEgg, the loop fires AncientEgg -> 0.5s -> BasicEgg -> 0.5s -> repeat.
PetsRemotes = RemotesFolder and RemotesFolder:FindFirstChild("Pets")
BuyEggRemote = PetsRemotes and PetsRemotes:FindFirstChild("BuyEgg")
PlaceEggRemote = PetsRemotes and PetsRemotes:FindFirstChild("PlaceEgg")
UnequipPetRemote = PetsRemotes and PetsRemotes:FindFirstChild("UnequipPet")

task.spawn(function()
	while gui.Parent do
		if ToggleState.autoBuyEggs and BuyEggRemote and BuyEggRemote:IsA("RemoteEvent") then
			local selected = {}
			for name in pairs(eggsBuySelection) do
				table.insert(selected, name)
			end
			if #selected > 0 then
				for _, eggName in ipairs(selected) do
					if not (gui.Parent and ToggleState.autoBuyEggs) then break end
					local eggId = EGG_ID_MAP[eggName]
					if eggId then
						pcall(function()
							BuyEggRemote:FireServer(eggId)
						end)
					end
					task.wait(0.5)
				end
			else
				task.wait(0.5)
			end
		else
			task.wait(0.5)
		end
	end
end)

-- ==EGG_PLACE_AUTOMATION==
-- Auto Place All Eggs: check the player's best eggs in inventory (character + backpack),
-- hold each egg tool via Tools.Held:FireServer(tool), then place it on an available soil spot
-- using Pets.PlaceEgg:FireServer(spotIndex, localX, localZ). Best eggs (highest price)
-- are placed first. Local coordinates come from FarmArea.FromWorld(farm, spot.Position).

function collectEggTools()
	local player = Players.LocalPlayer
	local list = {}
	for _, container in ipairs({ player:FindFirstChildOfClass("Backpack"), player.Character }) do
		if container then
			for _, item in ipairs(container:GetChildren()) do
				if item:IsA("Tool") then
					local eggId = EGG_ID_MAP[item.Name]
					if eggId then
						table.insert(list, { tool = item, eggId = eggId, price = EGG_PRICE_MAP[eggId] or 0 })
					end
				end
			end
		end
	end
	table.sort(list, function(a, b) return a.price > b.price end)
	return list
end

function getAvailableSoilSpots(farm)
	local spots = FarmArea.GetSpots(farm)
	if #spots == 0 then return {} end
	local eggsFolder = farm:FindFirstChild("Eggs")
	local usedIndices = {}
	if eggsFolder then
		for _, egg in ipairs(eggsFolder:GetChildren()) do
			local spotIdx = egg:GetAttribute("SpotIndex")
			if spotIdx then usedIndices[spotIdx] = true end
			local spotAttr = egg:GetAttribute("Spot")
			if spotAttr then usedIndices[spotAttr] = true end
		end
	end
	local available = {}
	for i, spot in ipairs(spots) do
		if not usedIndices[i] then
			local lx, lz = FarmArea.FromWorld(farm, spot.Position)
			table.insert(available, { index = i, spot = spot, localX = lx, localZ = lz })
		end
	end
	return available
end

function getAvailablePlantSpots(farm)
	local spots = FarmArea.GetSpots(farm)
	if #spots == 0 then return {} end
	-- Get occupied positions from server
	local occupied = {}
	if FarmGetOccupiedRemote and FarmGetOccupiedRemote:IsA("RemoteFunction") then
		local ok, result = pcall(function() return FarmGetOccupiedRemote:InvokeServer() end)
		if ok and type(result) == "table" then occupied = result end
	end
	-- Also check existing plants in the Plants folder
	local plantsFolder = farm:FindFirstChild("Plants")
	local plantPositions = {}
	if plantsFolder then
		for _, plant in ipairs(plantsFolder:GetChildren()) do
			if plant:IsA("Model") then
				local pos = getPlantWorldPosition(plant)
				if pos then
					table.insert(plantPositions, pos)
				end
			end
		end
	end
	local available = {}
	for i, spot in ipairs(spots) do
		local lx, lz = FarmArea.FromWorld(farm, spot.Position)
		-- Check if this spot overlaps with any occupied position
		local isOccupied = false
		if FarmArea.Overlaps(occupied, lx, lz) then
			isOccupied = true
		end
		-- Also check if a plant is already very close to this spot
		if not isOccupied then
			for _, pp in ipairs(plantPositions) do
				if (pp - spot.Position).Magnitude < 1.5 then
					isOccupied = true
					break
				end
			end
		end
		if not isOccupied then
			table.insert(available, { index = i, spot = spot, localX = lx, localZ = lz, worldPos = spot.Position })
		end
	end
	return available
end

eggPlaceBusy = false

function runEggPlaceCycle()
	if eggPlaceBusy then return end
	local player = Players.LocalPlayer
	local character = player and player.Character
	if not (character and character.Parent) then return end
	local farm = getActiveFarm()
	if not farm then return end
	if not (ToolsHeld and PlaceEggRemote) then return end

	local eggTools = collectEggTools()
	if #eggTools == 0 then return end

	local spots = getAvailableSoilSpots(farm)
	if #spots == 0 then return end

	eggPlaceBusy = true
	local placed = 0
	for i, eggInfo in ipairs(eggTools) do
		if not (gui.Parent and ToggleState.autoPlaceAll) then break end
		if i > #spots then break end
		local spotInfo = spots[i]
		local tool = eggInfo.tool
		if tool.Parent ~= character then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				pcall(function() humanoid:EquipTool(tool) end)
				task.wait(0.25)
			end
		end
		pcall(function() ToolsHeld:FireServer(tool) end)
		task.wait(0.15)
		pcall(function() PlaceEggRemote:FireServer(spotInfo.index, spotInfo.localX, spotInfo.localZ) end)
		placed += 1
		task.wait(0.5)
	end
	if placed > 0 then
		notify("Placed " .. placed .. " egg(s)", C.pink)
	end
	eggPlaceBusy = false
end

task.spawn(function()
	while gui.Parent do
		task.wait(0.5)
		if ToggleState.autoPlaceAll then
			pcall(runEggPlaceCycle)
		end
	end
end)

-- ==EGG_HATCH_AUTOMATION==
-- Auto Hatch All Ready Eggs: teleport to each ready egg on the local player's farm
-- and trigger its HatchPrompt via fireproximityprompt. An egg is ready when its
-- HatchPrompt is enabled (the hatching timer has completed).
function runEggHatchCycle()
	local player = Players.LocalPlayer
	local character = player and player.Character
	if not (character and character.Parent) then return end
	local farm = getActiveFarm()
	if not farm then return end
	local eggsFolder = farm:FindFirstChild("Eggs")
	if not eggsFolder then return end

	local originPivot = character:GetPivot()
	local hatched = 0
	for _, egg in ipairs(eggsFolder:GetChildren()) do
		if not (gui.Parent and ToggleState.autoHatchReady) then break end
		local root = egg:FindFirstChild("Root", true)
		if root then
			local hatchPrompt = root:FindFirstChild("HatchPrompt")
			if hatchPrompt and hatchPrompt:IsA("ProximityPrompt") and hatchPrompt.Enabled then
				local eggPos
				if root:IsA("BasePart") then
					eggPos = root.Position
				else
					eggPos = root:GetPivot().Position
				end
				character:PivotTo(CFrame.new(eggPos + Vector3.new(0, 3, 0)))
				task.wait(0.15)
				if type(fireproximityprompt) == "function" then
					pcall(function() fireproximityprompt(hatchPrompt) end)
					hatched += 1
					task.wait(0.5)
				end
			end
		end
	end
	if character.Parent then
		character:PivotTo(originPivot)
	end
	if hatched > 0 then
		notify("Hatched " .. hatched .. " egg(s)", C.green)
	end
end

task.spawn(function()
	while gui.Parent do
		task.wait(0.5)
		if ToggleState.autoHatchReady then
			pcall(runEggHatchCycle)
		end
	end
end)

-- ==STORE_AUTOMATION==
-- Auto Buy Store: cycle through the selected store items in the "Store to Buy"
-- dropdown at 0.5s per item using Store.Buy:FireServer(itemId). If the player
-- selected ReviveAll and Basket, the loop fires ReviveAll -> 0.5s -> Basket -> 0.5s -> repeat.
-- Auto Buy Decorations: same Store.Buy remote, same 0.5s cycling, for decoration items
-- selected in the "Decorations to Buy" dropdown (loaded from DecorationCatalog).
StoreRemotes = RemotesFolder and RemotesFolder:FindFirstChild("Store")
StoreBuyRemote = StoreRemotes and StoreRemotes:FindFirstChild("Buy")

task.spawn(function()
	while gui.Parent do
		if ToggleState.autoBuyStore and StoreBuyRemote and StoreBuyRemote:IsA("RemoteEvent") then
			local selected = {}
			for name in pairs(storeBuySelection) do
				table.insert(selected, name)
			end
			if #selected > 0 then
				for _, itemId in ipairs(selected) do
					if not (gui.Parent and ToggleState.autoBuyStore) then break end
					pcall(function()
						StoreBuyRemote:FireServer(itemId)
					end)
					task.wait(0.5)
				end
			else
				task.wait(0.5)
			end
		else
			task.wait(0.5)
		end
	end
end)

-- Decoration auto buy loop: same Store.Buy remote, 0.5s cycling through selected decorations.
task.spawn(function()
	while gui.Parent do
		if ToggleState.autoBuyDecor and StoreBuyRemote and StoreBuyRemote:IsA("RemoteEvent") then
			local selected = {}
			for name in pairs(decorBuySelection) do
				table.insert(selected, name)
			end
			if #selected > 0 then
				for _, itemId in ipairs(selected) do
					if not (gui.Parent and ToggleState.autoBuyDecor) then break end
					pcall(function()
						StoreBuyRemote:FireServer(itemId)
					end)
					task.wait(0.5)
				end
			else
				task.wait(0.5)
			end
		else
			task.wait(0.5)
		end
	end
end)

-- ==MERCHANT_AUTOMATION==
-- Auto Buy Merchant: checks Merchant.GetState to see if the traveling merchant is
-- present (Here = true), gets current stock, TPs to the merchant NPC, then fires
-- Merchant.Buy:FireServer(itemId) only for selected items that are in stock.
-- Returns player to original position after buying.
MerchantRemotes = RemotesFolder and RemotesFolder:FindFirstChild("Merchant")
MerchantBuyRemote = MerchantRemotes and MerchantRemotes:FindFirstChild("Buy")
MerchantGetStateRemote = MerchantRemotes and MerchantRemotes:FindFirstChild("GetState")

-- Build a map from the plain MERCHANT_ITEMS name to the merchant ID format.
-- The merchant server expects: "Gear:Basket", "Seed:Mais", or raw potion IDs like "Luck_Rare".
-- MERCHANT_ITEMS store the kind ("Potion", "Seed", "Gear", "Others") separately.
MERCHANT_ID_MAP = {}
for _, item in ipairs(MERCHANT_ITEMS) do
	local merchantId = item.name
	if item.kind == "Seed" then
		merchantId = "Seed:" .. item.name
	elseif item.kind == "Gear" then
		merchantId = "Gear:" .. item.name
	end
	MERCHANT_ID_MAP[item.name] = merchantId
end

local MERCHANT_POSITION = Vector3.new(-347.8, 21.5, 607.8)

function runMerchantBuyCycle()
	if not (MerchantBuyRemote and MerchantBuyRemote:IsA("RemoteEvent")) then return 0 end
	if not (MerchantGetStateRemote and MerchantGetStateRemote:IsA("RemoteFunction")) then return 0 end

	-- Check if merchant is present
	local ok, state = pcall(function() return MerchantGetStateRemote:InvokeServer() end)
	if not ok or type(state) ~= "table" then return 0 end
	if not state.Here then return 0 end

	-- Build a set of in-stock item IDs
	local inStock = {}
	if type(state.Stock) == "table" then
		for _, item in ipairs(state.Stock) do
			if type(item) == "table" and item.Id and (item.Left or 0) > 0 then
				inStock[item.Id] = true
			end
		end
	end

	-- Collect selected items that are also in stock.
	-- Convert plain names to merchant ID format before checking stock and buying.
	local toBuy = {}
	for name in pairs(merchantBuySelection) do
		local merchantId = MERCHANT_ID_MAP[name] or name
		if inStock[merchantId] then
			table.insert(toBuy, merchantId)
		end
	end
	if #toBuy == 0 then
		-- Fallback: buy Gear:Basket as default when nothing selected or nothing in stock.
		if inStock["Gear:Basket"] then
			table.insert(toBuy, "Gear:Basket")
		else
			return 0
		end
	end

	-- TP to merchant NPC
	local player = Players.LocalPlayer
	local character = player and player.Character
	if not character then return 0 end
	local originPivot = character:GetPivot()
	character:PivotTo(CFrame.new(MERCHANT_POSITION))
	task.wait(0.3)

	-- Buy all selected in-stock items (merchant IDs already have the correct prefix)
	local bought = 0
	for _, merchantId in ipairs(toBuy) do
		if not (gui.Parent and ToggleState.autoBuyMerchant) then break end
		pcall(function()
			MerchantBuyRemote:FireServer(merchantId)
		end)
		bought += 1
		task.wait(0.5)
	end

	-- Return to original position
	task.wait(0.3)
	if character and character.Parent then
		character:PivotTo(originPivot)
	end

	return bought
end

task.spawn(function()
	while gui.Parent do
		if ToggleState.autoBuyMerchant then
			local ok, bought = pcall(runMerchantBuyCycle)
			if ok and bought and bought > 0 then
				notify("Merchant: bought " .. bought .. " item(s)", C.purple)
				task.wait(2)
			else
				task.wait(2)
			end
		else
			task.wait(1)
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
FarmConfig = require(ReplicatedStorage.Shared.Config.FarmConfig)

AchievementsRemotes = RemotesFolder and RemotesFolder:FindFirstChild("Achievements")
IndexRemotes = RemotesFolder and RemotesFolder:FindFirstChild("Index")
AchievementsGetState = AchievementsRemotes and AchievementsRemotes:FindFirstChild("GetState")
AchievementsClaimRemote = AchievementsRemotes and AchievementsRemotes:FindFirstChild("Claim")
IndexGetState = IndexRemotes and IndexRemotes:FindFirstChild("GetState")
IndexClaimRemote = IndexRemotes and IndexRemotes:FindFirstChild("Claim")
SeasonPassRemotes = RemotesFolder and RemotesFolder:FindFirstChild("SeasonPass")
SeasonPassGetState = SeasonPassRemotes and SeasonPassRemotes:FindFirstChild("GetState")
SeasonPassClaimRemote = SeasonPassRemotes and SeasonPassRemotes:FindFirstChild("Claim")

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

function claimReadyPass()
	-- SeasonPass.Claim:InvokeServer() claims ALL ready rewards at once.
	-- The server sets SeasonReady on the player when rewards are pending.
	if not (SeasonPassClaimRemote and SeasonPassClaimRemote:IsA("RemoteFunction")) then return 0 end
	local player = Players.LocalPlayer
	local ready = player:GetAttribute("SeasonReady") or 0
	if ready <= 0 then return 0 end
	local ok, success = pcall(function()
		return SeasonPassClaimRemote:InvokeServer()
	end)
	if ok and success then
		return ready
	end
	return 0
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
		local wantsPass = ToggleState.claimPass == true
		if not (wantsAchievements or wantsIndex or wantsPass) then continue end
		rewardsBusy = true
		local achievementsFired = 0
		local indexFired = 0
		local passFired = 0
		if wantsAchievements then
			local ok, result = pcall(claimReadyAchievements)
			if ok then achievementsFired = result or 0 end
		end
		if wantsIndex then
			local ok, result = pcall(claimReadyIndex)
			if ok then indexFired = result or 0 end
		end
		if wantsPass then
			local ok, result = pcall(claimReadyPass)
			if ok then passFired = result or 0 end
		end
		if achievementsFired + indexFired + passFired > 0 then
			notify(string.format("Claimed %d achievement(s), %d index reward(s), %d pass reward(s)", achievementsFired, indexFired, passFired), C.gold)
		end
		rewardsBusy = false
	end
end)

-- ==CODES_AUTOMATION==
-- Auto Codes: safely redeems all known live codes through Codes.Redeem:InvokeServer(code).
-- Uses a RemoteFunction (InvokeServer) wrapped in pcall. Codes are attempted once per
-- session; already-redeemed or invalid codes simply return an error string and are
-- skipped silently. The list below covers all currently available codes.
CodesRemotes = RemotesFolder and RemotesFolder:FindFirstChild("Codes")
CodesRedeemRemote = CodesRemotes and CodesRemotes:FindFirstChild("Redeem")

KNOWN_CODES = {
	"FIRSTDAYOGPACK",
	"BAHAYKUBO",
	"RELEASE",
}
codesRedeemedLog = {}
codesAlreadyTried = false

function runCodesRedeemCycle()
	if codesAlreadyTried then return end
	if not (CodesRedeemRemote and CodesRedeemRemote:IsA("RemoteFunction")) then return end
	codesAlreadyTried = true
	local redeemed = 0
	for _, code in ipairs(KNOWN_CODES) do
		if not (gui.Parent and ToggleState.autoCodes) then break end
		local ok, result = pcall(function()
			return CodesRedeemRemote:InvokeServer(code)
		end)
		if ok then
			-- Server returns a success indicator or an error string.
			-- Treat non-string or truthy results as success.
			if type(result) == "string" then
				-- Check if it looks like an error message ("not found", "already", "invalid", "expired")
				local lower = string.lower(result)
				if string.find(lower, "already") or string.find(lower, "invalid")
					or string.find(lower, "not found") or string.find(lower, "expired")
					or string.find(lower, "error") then
					codesRedeemedLog[code] = "already/error"
				else
					codesRedeemedLog[code] = "redeemed"
					redeemed += 1
				end
			elseif result == true or result == nil then
				codesRedeemedLog[code] = "redeemed"
				redeemed += 1
			else
				codesRedeemedLog[code] = "redeemed"
				redeemed += 1
			end
		else
			codesRedeemedLog[code] = "pcall failed"
		end
		task.wait(0.5)
	end
	if redeemed > 0 then
		notify("Redeemed " .. redeemed .. " code(s)", C.gold)
	else
		notify("Codes already redeemed or unavailable", C.gray)
	end
end

task.spawn(function()
	while gui.Parent do
		task.wait(1)
		if ToggleState.autoCodes then
			pcall(runCodesRedeemCycle)
			-- After the first sweep, wait 30s before retrying (in case new codes are added).
			while gui.Parent and ToggleState.autoCodes do
				task.wait(30)
				-- Reset the try flag so it can sweep again for newly available codes.
				codesAlreadyTried = false
				pcall(runCodesRedeemCycle)
			end
		end
	end
end)

-- ==SLEEP_AUTOMATION==
-- Auto Sleep: find the bed on the local player's farm (FarmConfig.BedFolder/BedPart/BedProx),
-- teleport next to it, and trigger Farm.StartSleep:FireServer(). When the toggle is turned off,
-- Farm.StopSleep:FireServer() is fired to wake up.
FarmStartSleepRemote = RemotesFolder and RemotesFolder:FindFirstChild("Farm") and RemotesFolder.Farm:FindFirstChild("StartSleep") or nil
FarmStopSleepRemote = RemotesFolder and RemotesFolder:FindFirstChild("Farm") and RemotesFolder.Farm:FindFirstChild("StopSleep") or nil

function findBedPrompt(farm)
	local bedFolder = farm:FindFirstChild("Bed")
	if bedFolder then
		local bedPart = bedFolder:FindFirstChild("BedPart")
		if bedPart then
			local prompt = bedPart:FindFirstChild("Prox") or bedPart:FindFirstChildWhichIsA("ProximityPrompt")
			if prompt and prompt:IsA("ProximityPrompt") then
				return prompt, bedPart
			end
		end
	end
	-- Fallback: search for any bed-related proximity prompt
	for _, d in ipairs(farm:GetDescendants()) do
		if d:IsA("ProximityPrompt") and (d.Name == "Prox" or d.ObjectText and string.find(string.lower(d.ObjectText), "sleep")) then
			return d, d.Parent
		end
	end
	return nil, nil
end

sleepBusy = false
function runSleepCycle()
	if sleepBusy then return end
	local player = Players.LocalPlayer
	local character = player and player.Character
	if not (character and character.Parent) then return end
	if not FarmStartSleepRemote then return end
	local farm = getActiveFarm()
	if not farm then return end
	local prompt, bedPart = findBedPrompt(farm)
	if not prompt then return end
	sleepBusy = true
	local originPivot = character:GetPivot()
	-- Teleport next to the bed
	local targetPos = bedPart.Position + Vector3.new(0, 3, 6)
	character:PivotTo(CFrame.new(targetPos))
	task.wait(0.3)
	-- Fire the sleep remote
	pcall(function() FarmStartSleepRemote:FireServer() end)
	-- Also try the proximity prompt directly
	if prompt.Enabled and type(fireproximityprompt) == "function" then
		pcall(function() fireproximityprompt(prompt) end)
	end
	notify("Auto sleep started", C.purple)
	sleepBusy = false
end

task.spawn(function()
	while gui.Parent do
		task.wait(2)
		if ToggleState.autoSleep then
			pcall(runSleepCycle)
		end
	end
end)

-- ==BEST_PETS_AUTOMATION==
-- Auto Best Pets: call Pets.GetState:InvokeServer() to get the player's pet inventory,
-- then equip the highest-value pets (by rarity order and stat bonuses) using
-- Pets.EquipPet:FireServer(petId). Only equips pets that are not already equipped,
-- up to the free slot count from PetConfig.FreeSlots + MaxBoughtSlots.
PetsEquipRemote = PetsRemotes and PetsRemotes:FindFirstChild("EquipPet") or nil
PetsGetStateRemote = PetsRemotes and PetsRemotes:FindFirstChild("GetState") or nil

PET_RARITY_ORDER = { Common=1, Uncommon=2, Rare=3, Epic=4, Legendary=5, Mythic=6, Divine=7, Secret=8, OG=9, Champion=10, Creator=11 }

function getPetRarityScore(petId)
	if not PetConfig or not PetConfig.Pets then return 0 end
	local pet = PetConfig.Pets[petId]
	if not pet then return 0 end
	local rarity = pet.Rarity or "Common"
	return PET_RARITY_ORDER[rarity] or 0
end

function isPetInstance(child, container)
	if not child then return false end
	local name = child.Name
	-- Skip known non-pet tools
	if name == "Water Cup" or child:GetAttribute("WateringCan") == true then return false end
	if EGG_ID_MAP[name] ~= nil then return false end
	if child:IsA("Tool") and type(child:GetAttribute("CropId")) == "number" then return false end
	-- Check if it's a pet: has PetId attribute, or exists in PetConfig
	if child:GetAttribute("PetId") then return true end
	if PetConfig and PetConfig.Pets and PetConfig.Pets[name] then return true end
	return false
end

function runBestPetsCycle()
	if not ToolsHeld then return end
	local player = Players.LocalPlayer
	local character = player and player.Character
	if not (character and character.Parent) then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	local backpack = player:FindFirstChildOfClass("Backpack")

	-- Count pets already equipped in the character.
	local equippedCount = 0
	for _, child in ipairs(character:GetChildren()) do
		if isPetInstance(child, character) then
			equippedCount += 1
		end
	end

	-- Get max slots from PetConfig or Pets.GetState.
	local maxSlots = (PetConfig and PetConfig.FreeSlots or 3) + (PetConfig and PetConfig.MaxBoughtSlots or 2)
	if PetsGetStateRemote and PetsGetStateRemote:IsA("RemoteFunction") then
		local ok, state = pcall(function() return PetsGetStateRemote:InvokeServer() end)
		if ok and type(state) == "table" then
			maxSlots = state.Slots or state.MaxSlots or maxSlots
			local equipped = type(state.Equipped) == "table" and state.Equipped or {}
			if #equipped > equippedCount then equippedCount = #equipped end
		end
	end

	-- Stop if already at max pet equip capacity.
	if equippedCount >= maxSlots then return end

	-- Collect pet tools from the BACKPACK ONLY (pets in the character are already equipped).
	local petCandidates = {}
	if backpack then
		for _, child in ipairs(backpack:GetChildren()) do
			if isPetInstance(child, backpack) then
				local score = getPetRarityScore(child.Name)
				-- Bonus scores from PetConfig effects
				local petCfg = PetConfig and PetConfig.Pets and PetConfig.Pets[child.Name]
				if petCfg and petCfg.Effects then
					if petCfg.Effects.GrowthSpeed then score += 0.5 end
					if petCfg.Effects.SellValue then score += 0.3 end
					if petCfg.Effects.MutationChance then score += 0.4 end
					if petCfg.Effects.GoldenChance then score += 0.2 end
				end
				table.insert(petCandidates, { name = child.Name, instance = child, score = score })
			end
		end
	end

	-- No more pets to equip.
	if #petCandidates == 0 then return end

	-- Sort by rarity score descending (best pets first).
	table.sort(petCandidates, function(a, b) return a.score > b.score end)

	-- Equip up to (maxSlots - equippedCount) pets.
	local available = maxSlots - equippedCount
	local equippedNow = 0

	for i, cand in ipairs(petCandidates) do
		if i > available then break end
		if not (gui.Parent and ToggleState.autoBestPets) then break end

		local petInstance = cand.instance

		-- Equip the pet Tool to the character.
		if petInstance:IsA("Tool") and petInstance.Parent ~= character then
			pcall(function() humanoid:EquipTool(petInstance) end)
			-- Fallback: if EquipTool didn't move it, parent directly.
			if petInstance.Parent ~= character then
				pcall(function() petInstance.Parent = character end)
			end
		end

		-- Hold the best pet for 0.5s.
		task.wait(0.5)

		-- Fire Tools.Held remote with the pet from the character.
		local heldPet = character:FindFirstChild(cand.name)
		if heldPet then
			pcall(function() ToolsHeld:FireServer(heldPet) end)
			equippedNow += 1
		end
	end

	if equippedNow > 0 then
		notify("Equipped " .. equippedNow .. " best pet(s)", C.pink)
	end
end

task.spawn(function()
	while gui.Parent do
		task.wait(5)
		if ToggleState.autoBestPets then
			pcall(runBestPetsCycle)
		end
	end
end)

-- ==UPGRADE_AUTOMATION==
-- Auto Upgrade Plot / House: call Farm.GetUpgrade:InvokeServer() to check the
-- current upgrade level and cost, then fire Farm.UpgradeFarm:FireServer("Plot" or "House")
-- only when the player can afford the next upgrade.
FarmUpgradeFarmRemote = RemotesFolder and RemotesFolder:FindFirstChild("Farm") and RemotesFolder.Farm:FindFirstChild("UpgradeFarm") or nil
FarmGetUpgradeRemote = RemotesFolder and RemotesFolder:FindFirstChild("Farm") and RemotesFolder.Farm:FindFirstChild("GetUpgrade") or nil

function getLeaderstatMoney()
	local lp = Players.LocalPlayer
	local ls = lp:FindFirstChild("leaderstats")
	if not ls then return 0 end
	local money = ls:FindFirstChild("Pesos") or ls:FindFirstChild("Money") or ls:FindFirstChild("Coins") or ls:FindFirstChild("Cash")
	if not money then
		local currency = ls:FindFirstChild("Currency")
		if currency then
			money = currency:FindFirstChild("Pesos") or currency:FindFirstChild("Cash") or currency:FindFirstChild("Value")
		end
	end
	if not money then return 0 end
	return tonumber(money.Value) or 0
end

function runUpgradeCycle(kind)
	if not (FarmUpgradeFarmRemote and FarmGetUpgradeRemote) then return end
	if not (FarmUpgradeFarmRemote:IsA("RemoteEvent") and FarmGetUpgradeRemote:IsA("RemoteFunction")) then return end
	-- Get current upgrade state from the server
	local ok, state = pcall(function() return FarmGetUpgradeRemote:InvokeServer() end)
	if not ok or type(state) ~= "table" then return end
	-- Determine current level and next cost
	local progression
	if kind == "Plot" and FarmConfig and FarmConfig.PlotProgression then
		progression = FarmConfig.PlotProgression
	elseif kind == "House" and FarmConfig and FarmConfig.HouseProgression then
		progression = FarmConfig.HouseProgression
	end
	if not progression then return end
	local currentLevel = 0
	if kind == "Plot" then
		currentLevel = type(state.PlotLevel) == "number" and state.PlotLevel or 0
	elseif kind == "House" then
		currentLevel = type(state.HouseLevel) == "number" and state.HouseLevel or 0
	end
	local nextLevel = currentLevel + 1
	if nextLevel > #progression then return end -- already max
	local nextCost = progression[nextLevel] and progression[nextLevel].Cost or 0
	if nextCost <= 0 then return end
	local money = getLeaderstatMoney()
	if money < nextCost then return end -- cannot afford
	-- Fire the upgrade
	pcall(function() FarmUpgradeFarmRemote:FireServer(kind) end)
	notify(kind .. " upgrade purchased for ₱" .. formatMoney(nextCost), C.orange)
end

task.spawn(function()
	while gui.Parent do
		task.wait(5)
		if ToggleState.autoUpgradePlot then
			pcall(runUpgradeCycle, "Plot")
		end
		if ToggleState.autoUpgradeHouse then
			pcall(runUpgradeCycle, "House")
		end
	end
end)

-- ==FARM_SETUP_AUTOMATION==
-- Farm Setup: claim a free plot using Farm.ClaimPlot:InvokeServer(), then skip the
-- tutorial by firing Tutorial.Save:FireServer() with a completed tutorial state.
FarmClaimPlotRemote = RemotesFolder and RemotesFolder:FindFirstChild("Farm") and RemotesFolder.Farm:FindFirstChild("ClaimPlot") or nil
TutorialRemotes = RemotesFolder and RemotesFolder:FindFirstChild("Tutorial") or nil
TutorialSaveRemote = TutorialRemotes and TutorialRemotes:FindFirstChild("Save") or nil

farmSetupDone = false
function runFarmSetupCycle()
	if farmSetupDone then return end
	local player = Players.LocalPlayer
	-- Check if we already have a farm
	local farm = getActiveFarm()
	if farm then
		farmSetupDone = true
		return
	end
	-- Try to claim a plot
	if FarmClaimPlotRemote and FarmClaimPlotRemote:IsA("RemoteFunction") then
		local ok, result = pcall(function() return FarmClaimPlotRemote:InvokeServer() end)
		if ok then
			notify("Farm plot claimed", C.green)
		end
	end
	-- Skip tutorial
	if TutorialSaveRemote and TutorialSaveRemote:IsA("RemoteEvent") then
		pcall(function() TutorialSaveRemote:FireServer({ Step = 999, Completed = true }) end)
		notify("Tutorial skipped", C.sky)
	end
	farmSetupDone = true
end

task.spawn(function()
	while gui.Parent do
		task.wait(2)
		if ToggleState.farmSetup then
			pcall(runFarmSetupCycle)
		end
	end
end)

-- ==QUEST_AUTOMATION==
-- Auto Claim Only Claimable Quest: polls Quests.GetState for Daily and Weekly quest
-- progress, then calls Quests.Deliver:InvokeServer(questType, claimableId) for any quest
-- the server has marked as claimable. Only claimable quests are sent — the server is the
-- sole authority on what's ready.
QuestsRemotes = RemotesFolder and RemotesFolder:FindFirstChild("Quests") or nil
QuestsGetStateRemote = QuestsRemotes and QuestsRemotes:FindFirstChild("GetState") or nil
QuestsDeliverRemote = QuestsRemotes and QuestsRemotes:FindFirstChild("Deliver") or nil

function runClaimQuestsCycle()
	if not (QuestsGetStateRemote and QuestsDeliverRemote) then return 0 end
	if not (QuestsGetStateRemote:IsA("RemoteFunction") and QuestsDeliverRemote:IsA("RemoteFunction")) then return 0 end
	local ok, state = pcall(function() return QuestsGetStateRemote:InvokeServer() end)
	if not ok or type(state) ~= "table" then return 0 end
	local claimed = 0
	-- Check both Daily and Weekly quest categories
	for _, questType in ipairs({ "Daily", "Weekly" }) do
		local category = state[questType]
		if type(category) == "table" then
			-- category may be an array of quest objects or a dict
			local quests = category
			-- Some servers nest quests under a Quests sub-table
			if type(category.Quests) == "table" then quests = category.Quests end
			for id, quest in pairs(quests) do
				if type(quest) == "table" then
					local isClaimable = quest.Claimable == true or quest.CanClaim == true or quest.Ready == true
					local isClaimed = quest.Claimed == true
					if isClaimable and not isClaimed then
						local claimId = tonumber(id) or tonumber(quest.Id) or tonumber(quest.ClaimableId)
						if claimId then
							local ok2 = pcall(function() QuestsDeliverRemote:InvokeServer(questType, claimId) end)
							if ok2 then
								claimed += 1
								task.wait(0.3)
							end
						end
					end
				end
			end
		end
	end
	return claimed
end

task.spawn(function()
	while gui.Parent do
		task.wait(3)
		if ToggleState.autoClaimQuests then
			local ok, claimed = pcall(runClaimQuestsCycle)
			if ok and claimed and claimed > 0 then
				notify("Claimed " .. claimed .. " quest reward(s)", C.gold)
			end
		end
	end
end)

-- ==AUTO_QUEST==
-- Auto Quest: polls Quests.GetState for quests that have items ready to deliver
-- (Carrying > 0, not Done), then TP's to Mr. Nonoy (Kapitan NPC) and delivers all
-- ready quests via Quests.Deliver:InvokeServer(questType, questIndex).
-- Uses Instant TP or Tween TP based on the Quest Type dropdown selection.

local KAPITAN_POSITION = Vector3.new(-416, 22.5, 607)

function getQuestTPMode()
	if not questTypeSelection then return "instant" end
	for _, item in questTypeSelection do
		if type(item) == "table" and item.name then
			local n = string.lower(item.name)
			if string.find(n, "tween") then return "tween" end
			if string.find(n, "instant") then return "instant" end
		end
	end
	return "instant"
end

function runAutoQuestCycle()
	if not (QuestsGetStateRemote and QuestsDeliverRemote) then return 0 end
	if not (QuestsGetStateRemote:IsA("RemoteFunction") and QuestsDeliverRemote:IsA("RemoteFunction")) then return 0 end
	local ok, state = pcall(function() return QuestsGetStateRemote:InvokeServer() end)
	if not ok or type(state) ~= "table" then return 0 end

	-- Collect all quests that have items ready to deliver (Carrying > 0, not Done)
	local readyQuests = {}
	for _, questType in ipairs({ "Daily", "Weekly" }) do
		local category = state[questType]
		if type(category) == "table" then
			local quests = category
			if type(category.Quests) == "table" then quests = category.Quests end
			for id, quest in pairs(quests) do
				if type(quest) == "table" and not quest.Done then
					local carrying = tonumber(quest.Carrying) or 0
					if carrying > 0 then
						local questIndex = tonumber(id) or tonumber(quest.Id) or 0
						if questIndex > 0 then
							table.insert(readyQuests, { type = questType, index = questIndex })
						end
					end
				end
			end
		end
	end

	if #readyQuests == 0 then return 0 end

	local player = Players.LocalPlayer
	local character = player and player.Character
	if not character then return 0 end
	local originPivot = character:GetPivot()
	local tpMode = getQuestTPMode()

	-- TP to Kapitan NPC
	if tpMode == "tween" then
		tweenCharacterTo(character, KAPITAN_POSITION)
	else
		character:PivotTo(CFrame.new(KAPITAN_POSITION))
	end
	task.wait(0.3)

	-- Deliver all ready quests
	local delivered = 0
	for _, q in readyQuests do
		local ok2 = pcall(function() QuestsDeliverRemote:InvokeServer(q.type, q.index) end)
		if ok2 then
			delivered += 1
			task.wait(0.3)
		end
	end

	-- Return to original position
	task.wait(0.3)
	if character and character.Parent then
		if tpMode == "tween" then
			tweenCharacterTo(character, originPivot.Position)
		else
			character:PivotTo(originPivot)
		end
	end

	return delivered
end

task.spawn(function()
	while gui.Parent do
		task.wait(5)
		if ToggleState.autoQuest then
			local ok, delivered = pcall(runAutoQuestCycle)
			if ok and delivered and delivered > 0 then
				notify("Auto Quest: delivered " .. delivered .. " quest(s) to Mr. Nonoy", C.gold)
			end
		end
	end
end)

-- ==ANTI_AFK==
-- Anti-AFK is locked ON: uses VirtualInputManager to send a minor input every 30s
-- so the player never gets disconnected for inactivity.
task.spawn(function()
	local virtualInput = game:GetService("VirtualInputManager")
	while gui.Parent do
		task.wait(30)
		if ToggleState.antiAFK ~= false then
			pcall(function()
				virtualInput:SendKeyEvent(true, Enum.KeyCode.Unknown, false, game)
				task.wait(0.05)
				virtualInput:SendKeyEvent(false, Enum.KeyCode.Unknown, false, game)
			end)
		end
	end
end)

-- ==FPS_MODE==
-- FPS Mode: hides map decorations, animal decorations, barriers, rain, VFX,
-- particles, and other visual effects to improve frame rate on lower-end devices.
local fpsModeActive = false
local fpsHiddenObjects = {}

local FPS_HIDE_PATHS = {
	"Map.mapdecorations",
	"Map.animal decoration",
	"Map.BARRIERS",
	"Map.islanddecorations",
	"rksRain",
}

local function findByPath(path)
	local parts = string.split(path, ".")
	local current = workspace
	for _, part in ipairs(parts) do
		current = current:FindFirstChild(part)
		if not current then return nil end
	end
	return current
end

local function applyFPSMode(on)
	if on then
		for _, path in ipairs(FPS_HIDE_PATHS) do
			local obj = findByPath(path)
			if obj and obj.Parent then
				fpsHiddenObjects[obj] = obj.Parent
				obj.Parent = nil
			end
		end
		for _, d in ipairs(workspace:GetDescendants()) do
			if d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Beam") then
				d.Enabled = false
			end
		end
	else
		for obj, parent in pairs(fpsHiddenObjects) do
			if obj and not obj.Parent then
				obj.Parent = parent
			end
		end
		fpsHiddenObjects = {}
		for _, d in ipairs(workspace:GetDescendants()) do
			if d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Beam") then
				d.Enabled = true
			end
		end
	end
end

task.spawn(function()
	while gui.Parent do
		task.wait(1)
		local wantFPS = ToggleState.fpsMode == true
		if wantFPS ~= fpsModeActive then
			fpsModeActive = wantFPS
			pcall(applyFPSMode, wantFPS)
			if not uiSettings.silent then
				notify(wantFPS and "FPS mode enabled — decorations & effects hidden" or "FPS mode disabled — decorations & effects restored", wantFPS and C.green or C.gray)
			end
		elseif wantFPS then
			for _, path in ipairs(FPS_HIDE_PATHS) do
				local obj = findByPath(path)
				if obj and obj.Parent then
					fpsHiddenObjects[obj] = obj.Parent
					obj.Parent = nil
				end
			end
			for _, d in ipairs(workspace:GetDescendants()) do
				if (d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Beam")) and d.Enabled then
					d.Enabled = false
				end
			end
		end
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
