local toolbar = plugin:CreateToolbar("Tech Tree Tools")
local button  = toolbar:CreateButton("OpenEditor", "Open Tech Tree Editor", "")

-- Forward declarations used across the file
local handleTypeChanged
local handleFunctionChanged

-- Global editor state
local isLoading = false
local nodes = {}
local nodeId = 0
local unsavedChanges = false
local pendingAction = nil
local currentLevel = 1
local currentNode = nil
-- Track where the current unsaved edits belong (node + level)
local dirtyNode = nil
local dirtyLevel = nil  -- 0 for Onetime, N for Repeatable level

--
-- Utility: simple dropdowns
-- Returns: get(), set(value[, suppressEvent]), button
local function createDropdown(labelText, options, parent, onChanged)
	local container = Instance.new("Frame")
	container.Size = UDim2.new(0, 230, 0, 60)
	container.BackgroundTransparency = 1
	container.Parent = parent

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 20)
	label.BackgroundTransparency = 1
	label.Text = labelText
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.SourceSans
	label.TextSize = 16
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = container

	local button = Instance.new("TextButton")
	button.Size = UDim2.new(1, 0, 0, 25)
	button.Position = UDim2.new(0, 0, 0, 25)
	button.BackgroundColor3 = Color3.fromRGB(240, 240, 240)
	button.Font = Enum.Font.SourceSans
	button.TextSize = 16
	button.TextColor3 = Color3.new(0, 0, 0)
	button.Parent = container

	local current = options[1]
	button.Text = current

	local function set(val, suppressEvent)
		if not table.find(options, val) then return end
		current = val
		button.Text = current
		if onChanged and not suppressEvent then onChanged(current) end
	end

	button.MouseButton1Click:Connect(function()
		local index = table.find(options, current) or 1
		local nextOpt = options[(index % #options) + 1]
		set(nextOpt)
	end)

	return function() return current end, set, button
end

-- Plugin dock widget
local widgetInfo = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Right,
	true,
	true,
	500, 400,
	300, 300
)
local widget = plugin:CreateDockWidgetPluginGui("TechTreeEditorWidget", widgetInfo)
widget.Title = "Tech Tree Editor"

-- Root containers
local frame = Instance.new("Frame")
frame.Size = UDim2.new(1, 0, 1, 0)
frame.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
frame.Parent = widget

local canvas = Instance.new("ScrollingFrame")
canvas.Size = UDim2.new(1, 0, 1, -50)
canvas.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
canvas.CanvasSize = UDim2.new(2, 0, 2, 0)
canvas.ScrollBarThickness = 6
canvas.Parent = frame

local addButton = Instance.new("TextButton")
addButton.Size = UDim2.new(1, 0, 0, 50)
addButton.Position = UDim2.new(0, 0, 1, -50)
addButton.BackgroundColor3 = Color3.fromRGB(0, 170, 255)
addButton.Font = Enum.Font.SourceSansBold
addButton.TextSize = 22
addButton.TextColor3 = Color3.new(1,1,1)
addButton.Text = "➕ Add Node"
addButton.Parent = frame

-- Properties panel
local propertiesPanel = Instance.new("ScrollingFrame")
propertiesPanel.Size = UDim2.new(0, 250, 1, 0)
propertiesPanel.Position = UDim2.new(1, -250, 0, 0)
propertiesPanel.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
propertiesPanel.ScrollBarThickness = 6
propertiesPanel.CanvasSize = UDim2.new(0, 0, 2, 0)
propertiesPanel.AutomaticCanvasSize = Enum.AutomaticSize.Y
propertiesPanel.Visible = false
propertiesPanel.Parent = frame

local panelPadding = Instance.new("UIPadding")
panelPadding.PaddingLeft = UDim.new(0,10)
panelPadding.PaddingTop = UDim.new(0,10)
panelPadding.Parent = propertiesPanel

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, 0, 0, 40)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "Node Properties"
titleLabel.TextColor3 = Color3.new(1, 1, 1)
titleLabel.Font = Enum.Font.SourceSansBold
titleLabel.TextSize = 22
titleLabel.Parent = propertiesPanel

-- Text fields
local function mkLabel(text, y)
        local l = Instance.new("TextLabel")
        l.Position = UDim2.new(0, 0, 0, y)
        l.Size = UDim2.new(0, 230, 0, 20)
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextColor3 = Color3.new(1,1,1)
	l.Font = Enum.Font.SourceSans
	l.TextSize = 16
	l.Parent = propertiesPanel
	return l
end
local function mkBox(y)
        local b = Instance.new("TextBox")
        b.Position = UDim2.new(0, 0, 0, y)
        b.Size = UDim2.new(0, 230, 0, 25)
	b.Font = Enum.Font.SourceSans
	b.TextSize = 16
	b.TextColor3 = Color3.new(0,0,0)
	b.BackgroundColor3 = Color3.fromRGB(240,240,240)
	b.Parent = propertiesPanel
	return b
end

mkLabel("Name:", 60)
local nameBox = mkBox(80)
mkLabel("Description:", 115)
local descBox = Instance.new("TextBox")
descBox.Position = UDim2.new(0,0,0,135)
descBox.Size = UDim2.new(0,230,0,45)
descBox.Font = Enum.Font.SourceSans
descBox.TextSize = 14
descBox.TextWrapped = true
descBox.ClearTextOnFocus = false
descBox.MultiLine = true
descBox.TextColor3 = Color3.new(0,0,0)
descBox.BackgroundColor3 = Color3.fromRGB(240,240,240)
descBox.Parent = propertiesPanel

-- Dropdowns (wired via proxies until handlers exist)
local function proxyTypeChanged(v) if handleTypeChanged then handleTypeChanged(v) end end
local function proxyFunctionChanged(v) if handleFunctionChanged then handleFunctionChanged(v) end end

local getType, setType, typeDropdown = createDropdown("Type:", {"Onetime","Repeatable"}, propertiesPanel, proxyTypeChanged)
typeDropdown.Parent.Position = UDim2.new(0,0,0,190)

local getFunction, setFunction, functionDropdown = createDropdown("Function:", {"Moneyboost","Custom"}, propertiesPanel, proxyFunctionChanged)
functionDropdown.Parent.Position = UDim2.new(0,0,0,250)

-- moneyBoost fields
local blockLabel = mkLabel("Block Name:", 310)
local blockBox   = mkBox(330)
local boostLabel = mkLabel("Boosted Income:", 365)
local boostBox   = mkBox(385)

-- custom fields
local eventLabel = mkLabel("RemoteEvent Name:", 310)
eventLabel.Visible = false
local eventBox   = mkBox(330)
eventBox.Visible = false

-- repeatable controls
local upgradeCountLabel = mkLabel("Levels:", 420)
upgradeCountLabel.Visible = false
local upgradeCountBox = mkBox(440)
upgradeCountBox.Text = "1"
upgradeCountBox.Visible = false

local levelSelectLabel = mkLabel("Edit Level:", 470)
levelSelectLabel.Visible = false

local function isCurrentDirty(levelOverride)
        if not currentNode then return false end
        local tVal = getType()
        local level = levelOverride or ((tVal == "Repeatable") and (tonumber((function() return select(1, getLevel()) end)()) or 1) or 0)
        local data = currentNode.data
        local function tostr(v) return v and tostring(v) or "" end
        if tVal == "Repeatable" then
                data.Upgrades = data.Upgrades or {}
                local up = data.Upgrades[level] or {}
                if nameBox.Text ~= (up.Name or data.Name or "") then return true end
                if descBox.Text ~= (up.Description or data.Description or "") then return true end
                if blockBox.Text ~= (up.Block or data.Block or "") then return true end
                if getFunction() == "Moneyboost" then
                        if boostBox.Text ~= tostr(up.BoostedIncome or data.BoostedIncome) then return true end
                else
                        if eventBox.Text ~= (up.RemoteEventName or data.RemoteEventName or "") then return true end
                end
                local levelsNum = tonumber(upgradeCountBox.Text)
                if levelsNum and levelsNum ~= (data.Levels or 1) then return true end
        else
                if nameBox.Text ~= (data.Name or "") then return true end
                if descBox.Text ~= (data.Description or "") then return true end
                if blockBox.Text ~= (data.Block or "") then return true end
                if getFunction() == "Moneyboost" then
                        if boostBox.Text ~= tostr(data.BoostedIncome) then return true end
                else
                        if eventBox.Text ~= (data.RemoteEventName or "") then return true end
                end
        end
        return false
end

local function checkUnsaved(levelOverride)
        if isLoading or not currentNode then
                unsavedChanges = false
                dirtyNode, dirtyLevel = nil, nil
                return false
        end
        if isCurrentDirty(levelOverride) then
                unsavedChanges = true
                dirtyNode = currentNode
                dirtyLevel = levelOverride or ((getType() == "Repeatable") and (tonumber((function() return select(1, getLevel()) end)()) or 1) or 0)
                return true
        else
                unsavedChanges = false
                dirtyNode, dirtyLevel = nil, nil
                return false
        end
end

-- Immediate dirty marking (captures keystrokes)
local function markDirtyImmediate()
        checkUnsaved()
end

nameBox:GetPropertyChangedSignal("Text"):Connect(markDirtyImmediate)
descBox:GetPropertyChangedSignal("Text"):Connect(markDirtyImmediate)
blockBox:GetPropertyChangedSignal("Text"):Connect(markDirtyImmediate)
boostBox:GetPropertyChangedSignal("Text"):Connect(markDirtyImmediate)
eventBox:GetPropertyChangedSignal("Text"):Connect(markDirtyImmediate)

local function onLevelChanged(txt)
	if not currentNode then return end
        local n = tonumber(txt) or 1
        if n == currentLevel then return end
        local prevLevel = currentLevel
        local function doSwitch()
                currentLevel = n
                loadLevel(currentNode, currentLevel)
        end
        requestSaveIfNeeded(doSwitch, prevLevel)
end

local getLevel, setLevel, levelDropdown = createDropdown("1", {"1"}, propertiesPanel, onLevelChanged)
levelDropdown.Parent.Position = UDim2.new(0,0,0,490)
levelDropdown.Parent.Visible = false

-- Save + popup
local saveButton = Instance.new("TextButton")
saveButton.Size = UDim2.new(0, 120, 0, 30)
saveButton.Position = UDim2.new(0, 0, 0, 530)
saveButton.Text = "Save"
saveButton.TextColor3 = Color3.new(1,1,1)
saveButton.BackgroundColor3 = Color3.fromRGB(0,200,0)
saveButton.Parent = propertiesPanel

local saveNotice = Instance.new("TextLabel")
saveNotice.Size = UDim2.new(0, 120, 0, 20)
saveNotice.Position = UDim2.new(0, 0, 0, 565)
saveNotice.BackgroundTransparency = 1
saveNotice.TextColor3 = Color3.fromRGB(0,255,0)
saveNotice.Font = Enum.Font.SourceSans
saveNotice.TextSize = 16
saveNotice.Visible = false
saveNotice.Text = "Saved!"
saveNotice.Parent = propertiesPanel

local function flashSaved()
        saveNotice.Visible = true
        task.delay(2, function()
                saveNotice.Visible = false
        end)
end

local popupOverlay = Instance.new("Frame")
popupOverlay.Size = UDim2.new(1,0,1,0)
popupOverlay.BackgroundColor3 = Color3.new(0,0,0)
popupOverlay.BackgroundTransparency = 0.5
popupOverlay.Visible = false
popupOverlay.ZIndex = 100
popupOverlay.Parent = frame

local popupBox = Instance.new("Frame")
popupBox.Size = UDim2.new(0, 240, 0, 140)
popupBox.Position = UDim2.new(0.5, -120, 0.5, -70)
popupBox.BackgroundColor3 = Color3.fromRGB(240,240,240)
popupBox.BorderSizePixel = 0
popupBox.ZIndex = 101
popupBox.Visible = false
popupBox.Parent = popupOverlay

local popupMsg = Instance.new("TextLabel")
popupMsg.Size = UDim2.new(1, -20, 0, 40)
popupMsg.Position = UDim2.new(0, 10, 0, 10)
popupMsg.Text = "Unsaved changes!"
popupMsg.TextColor3 = Color3.new(0, 0, 0)
popupMsg.BackgroundTransparency = 1
popupMsg.Font = Enum.Font.SourceSansBold
popupMsg.TextSize = 16
popupMsg.ZIndex = 102
popupMsg.Parent = popupBox

local savePopupButton = Instance.new("TextButton")
savePopupButton.Size = UDim2.new(0, 70, 0, 30)
savePopupButton.Position = UDim2.new(0, 10, 0, 90)
savePopupButton.Text = "Save"
savePopupButton.BackgroundColor3 = Color3.fromRGB(0,200,0)
savePopupButton.TextColor3 = Color3.new(1,1,1)
savePopupButton.ZIndex = 103
savePopupButton.Parent = popupBox

local discardPopupButton = Instance.new("TextButton")
discardPopupButton.Size = UDim2.new(0, 80, 0, 30)
discardPopupButton.Position = UDim2.new(0, 90, 0, 90)
discardPopupButton.Text = "Discard"
discardPopupButton.BackgroundColor3 = Color3.fromRGB(200,0,0)
discardPopupButton.TextColor3 = Color3.new(1,1,1)
discardPopupButton.ZIndex = 103
discardPopupButton.Parent = popupBox

local cancelPopupButton = Instance.new("TextButton")
cancelPopupButton.Size = UDim2.new(0, 70, 0, 30)
cancelPopupButton.Position = UDim2.new(0, 180, 0, 90)
cancelPopupButton.Text = "Cancel"
cancelPopupButton.BackgroundColor3 = Color3.fromRGB(0,0,200)
cancelPopupButton.TextColor3 = Color3.new(1,1,1)
cancelPopupButton.ZIndex = 103
cancelPopupButton.Parent = popupBox

-- Data helpers
local function ensureUpgradesSize(nodeData, n)
	nodeData.Upgrades = nodeData.Upgrades or {}
	for i = 1, n do
		nodeData.Upgrades[i] = nodeData.Upgrades[i] or {Name="",Description="",Block="",BoostedIncome=nil,RemoteEventName=""}
	end
	for i = n + 1, #nodeData.Upgrades do nodeData.Upgrades[i] = nil end
end

-- Save current UI into node data — commits to the level that was edited (dirtyLevel)
local function saveCurrentLevelData(nodeEntry)
	if not nodeEntry then return end
	-- Use the level that was actually edited; fallback to current UI level
	local level = (dirtyNode == nodeEntry and dirtyLevel) or (tonumber(getLevel()) or 1)
	local tVal = getType()
	nodeEntry.data.Type = tVal
	nodeEntry.data.Function = getFunction()
	if tVal == "Repeatable" then
		nodeEntry.data.Upgrades = nodeEntry.data.Upgrades or {}
		nodeEntry.data.Upgrades[level] = nodeEntry.data.Upgrades[level] or {}
		local up = nodeEntry.data.Upgrades[level]
		up.Name = nameBox.Text
		up.Description = descBox.Text
		up.Block = blockBox.Text
		up.BoostedIncome = tonumber(boostBox.Text)
		up.RemoteEventName = eventBox.Text
		local levelsNum = tonumber(upgradeCountBox.Text)
		if levelsNum then nodeEntry.data.Levels = levelsNum; ensureUpgradesSize(nodeEntry.data, levelsNum) end
	else
		nodeEntry.data.Name = nameBox.Text
		nodeEntry.data.Description = descBox.Text
		nodeEntry.data.Block = blockBox.Text
		nodeEntry.data.BoostedIncome = tonumber(boostBox.Text)
		nodeEntry.data.RemoteEventName = eventBox.Text
	end
	nodeEntry.label.Text = (nameBox.Text ~= "" and nameBox.Text) or nodeEntry.ui.Name
	unsavedChanges = false
	dirtyNode, dirtyLevel = nil, nil
end

-- Toggle fields for function type
local function setFunctionFieldsVisible(funcVal)
	local isMoney = (funcVal == "Moneyboost")
	blockLabel.Visible = isMoney; blockBox.Visible = isMoney
	boostLabel.Visible = isMoney; boostBox.Visible = isMoney
	eventLabel.Visible = not isMoney; eventBox.Visible = not isMoney
end

-- Load a specific level into UI
function loadLevel(nodeEntry, level)
	if not nodeEntry then return end
	isLoading = true
	unsavedChanges = false
	dirtyNode, dirtyLevel = nil, nil
	local tVal = getType()
	local fVal = getFunction()
	setFunctionFieldsVisible(fVal)
	if tVal == "Repeatable" then
		local up = nodeEntry.data.Upgrades and nodeEntry.data.Upgrades[level] or {}
		nameBox.Text  = up.Name or nodeEntry.data.Name or nodeEntry.ui.Name
		descBox.Text  = up.Description or nodeEntry.data.Description or ""
		blockBox.Text = up.Block or nodeEntry.data.Block or ""
		if fVal == "Moneyboost" then
			boostBox.Text = up.BoostedIncome and tostring(up.BoostedIncome) or (nodeEntry.data.BoostedIncome and tostring(nodeEntry.data.BoostedIncome) or "")
		else
			eventBox.Text = up.RemoteEventName or nodeEntry.data.RemoteEventName or ""
		end
	else
		nameBox.Text  = nodeEntry.data.Name or nodeEntry.ui.Name
		descBox.Text  = nodeEntry.data.Description or ""
		blockBox.Text = nodeEntry.data.Block or ""
		if fVal == "Moneyboost" then
			boostBox.Text = nodeEntry.data.BoostedIncome and tostring(nodeEntry.data.BoostedIncome) or ""
		else
			eventBox.Text = nodeEntry.data.RemoteEventName or ""
		end
	end
	isLoading = false
	unsavedChanges = false
end

-- Load entire node into UI
local function loadNode(nodeEntry)
	if not nodeEntry then return end
	currentNode = nodeEntry
	isLoading = true
	unsavedChanges = false
	dirtyNode, dirtyLevel = nil, nil
	local tVal = nodeEntry.data.Type or "Onetime"
	local fVal = nodeEntry.data.Function or "Moneyboost"
	setType(tVal, true); setFunction(fVal, true)
	-- Call handlers while loading (won't dirty)
	handleTypeChanged(tVal)
	handleFunctionChanged(fVal)
	local isRepeat = (tVal == "Repeatable")
	upgradeCountLabel.Visible  = isRepeat
	upgradeCountBox.Visible    = isRepeat
	levelSelectLabel.Visible   = isRepeat
	levelDropdown.Parent.Visible = isRepeat
	local maxLevel = tonumber(nodeEntry.data.Levels) or 1
	if nodeEntry.data.Upgrades then
		for k,_ in pairs(nodeEntry.data.Upgrades) do if type(k)=="number" and k>maxLevel then maxLevel=k end end
	end
	if maxLevel < 1 then maxLevel = 1 end
	upgradeCountBox.Text = tostring(maxLevel)
	for _, child in ipairs(levelDropdown.Parent:GetChildren()) do if child:IsA("TextButton") then child:Destroy() end end
	local opts = {}; for i=1,maxLevel do opts[#opts+1]=tostring(i) end
	getLevel, setLevel, levelDropdown = createDropdown("", opts, propertiesPanel, onLevelChanged)
        levelDropdown.Parent.Position = UDim2.new(0,0,0,490)
	levelDropdown.Parent.Visible = isRepeat
	currentLevel = 1
	setLevel(opts[1] or "1", true)
	loadLevel(currentNode, currentLevel)
	isLoading = false
	unsavedChanges = false
	propertiesPanel.Visible = true
end

-- Save prompt
local function requestSaveIfNeeded(proceed, levelOverride)
        if not checkUnsaved(levelOverride) then proceed(); return end
        popupOverlay.Visible = true
        popupBox.Visible = true
        pendingAction = proceed
end

-- Popup buttons
savePopupButton.MouseButton1Click:Connect(function()
        if dirtyNode or currentNode then saveCurrentLevelData(dirtyNode or currentNode) end
        flashSaved()
        popupBox.Visible = false
        popupOverlay.Visible = false
        local action = pendingAction; pendingAction = nil
        if action then action() end
end)

discardPopupButton.MouseButton1Click:Connect(function()
        unsavedChanges = false
        dirtyNode, dirtyLevel = nil, nil
        if currentNode then loadLevel(currentNode, tonumber((function() return select(1, getLevel()) end)()) or 1) end
        popupBox.Visible = false
        popupOverlay.Visible = false
        local action = pendingAction; pendingAction = nil
        if action then action() end
end)

cancelPopupButton.MouseButton1Click:Connect(function()
        popupBox.Visible = false
        popupOverlay.Visible = false
        pendingAction = nil
        setLevel(tostring(currentLevel), true)
end)

-- Count change => rebuild level dropdown and mark unsaved
upgradeCountBox.FocusLost:Connect(function()
	if isLoading or not currentNode then return end
	local n = tonumber(upgradeCountBox.Text) or 1
	n = math.clamp(n, 1, 99)
	local data = currentNode.data
	local prev = tonumber(data.Levels) or (#(data.Upgrades or {}) > 0 and #data.Upgrades or 1)
	if prev ~= n then
		data.Levels = n
		ensureUpgradesSize(data, n)
		for _, child in ipairs(levelDropdown.Parent:GetChildren()) do if child:IsA("TextButton") then child:Destroy() end end
		local opts = {}; for i=1,n do opts[i]=tostring(i) end
		getLevel, setLevel, levelDropdown = createDropdown("", opts, propertiesPanel, onLevelChanged)
                levelDropdown.Parent.Position = UDim2.new(0,0,0,490)
		levelDropdown.Parent.Visible = true
		if currentLevel > n then currentLevel = n end
                setLevel(tostring(currentLevel), true)
                loadLevel(currentNode, currentLevel)
                checkUnsaved()
        end
end)

-- Dropdown handlers (dirty only when actual change and not loading)
handleTypeChanged = function(newVal)
	if not currentNode then return end
	local prev = currentNode.data.Type
	currentNode.data.Type = newVal
	local isRepeat = (newVal == "Repeatable")
	upgradeCountLabel.Visible  = isRepeat
	upgradeCountBox.Visible    = isRepeat
	levelSelectLabel.Visible   = isRepeat
	levelDropdown.Parent.Visible = isRepeat
        if not isLoading and prev ~= newVal then
                checkUnsaved()
        end
end

handleFunctionChanged = function(newVal)
	if not currentNode then return end
	local prev = currentNode.data.Function
	currentNode.data.Function = newVal
        setFunctionFieldsVisible(newVal)
        if not isLoading and prev ~= newVal then
                checkUnsaved()
        end
end

-- Save button
saveButton.MouseButton1Click:Connect(function()
        if currentNode then saveCurrentLevelData(currentNode) end
        flashSaved()
end)

-- Node creation
local function createNode()
	nodeId += 1
	local node = Instance.new("Frame")
	node.Size = UDim2.new(0, 150, 0, 100)
	node.Position = UDim2.new(0, 80 * nodeId, 0, 80 * nodeId)
        node.BackgroundColor3 = Color3.fromRGB(80, 120, 180)
	node.BorderSizePixel = 1
	node.Active = true
	node.Name = "Node_" .. nodeId

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 25)
	label.BackgroundTransparency = 1
	label.Text = "Node " .. nodeId
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.SourceSansBold
	label.TextSize = 18
	label.Parent = node

	node.Parent = canvas

	nodes[node.Name] = { ui = node, label = label, data = {} }

	-- Dragging (show SizeAll cursor while hovering)
	local dragging = false
	local dragStart, startPos
	node.MouseEnter:Connect(function()
		game:GetService("UserInputService").MouseIcon = "rbxasset://SystemCursors/SizeAll"
	end)
	node.MouseLeave:Connect(function()
		game:GetService("UserInputService").MouseIcon = ""
	end)
	node.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			dragStart = input.Position
			startPos = node.Position
		end
	end)
	node.InputChanged:Connect(function(input)
		if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			local delta = input.Position - dragStart
			node.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
		end
	end)
	node.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
	end)

	-- Selection (prompt only if truly dirty)
	node.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			local function go()
				propertiesPanel.Visible = true
				loadNode(nodes[node.Name])
			end
                        requestSaveIfNeeded(go)
		end
	end)
end

-- Add node
addButton.MouseButton1Click:Connect(function() createNode() end)

-- Toggle widget
button.Click:Connect(function() widget.Enabled = not widget.Enabled end)

-- Start with one node
createNode()

-- ===== Notes on default icons =====
-- Drag cursor (4 arrows): use the system cursor
--   UserInputService.MouseIcon = "rbxasset://SystemCursors/SizeAll"
-- Graphic drag handle (dots):
--   ImageLabel.Image = "rbxasset://textures/ui/DragHandle.png"
-- You can also use many built-ins under rbxasset://textures/ui/
