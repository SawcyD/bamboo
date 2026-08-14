--!strict
--[[
	PerformanceDebug: in-game performance + network profiler (toggle with L by default).

	Cards: FPS / ping / memory / instance count. Table: every network bridge with
	sent/recv rates and bandwidth, sorted by current volume, plus server-reported
	rows (replica writes) and Roblox's total data-receive stat with an estimated
	"untracked gap" row — if the gap is big, something outside Relay is eating
	bandwidth.

	Availability: always in Studio; in live servers only for DebugConfig.DeveloperIds.
	Telemetry costs nothing until the UI is opened (Channel.Telemetry.Enabled and the
	server publisher both switch on/off with the panel).
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Stats = game:GetService("Stats")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Core = require(ReplicatedStorage:WaitForChild("Core"))
local Relay = Core:GetShared("Network")
local Channel = Relay.Channel
local DebugConfig = require(script.Parent.Parent:WaitForChild("Configs"):WaitForChild("DebugConfig"))

local PerformanceDebug = {}

local _screenGui: ScreenGui? = nil
local _localPlayer: Player? = nil
local _mainFrame: CanvasGroup? = nil
local _fpsLabel: TextLabel? = nil
local _pingLabel: TextLabel? = nil
local _memLabel: TextLabel? = nil
local _instancesLabel: TextLabel? = nil
local _scrollFrame: ScrollingFrame? = nil

local _fpsValues: { number } = {}
local _lastTelemetry = { Sent = {} :: { [string]: any }, Received = {} :: { [string]: any } }
local _externalTelemetryRows: { [string]: { recvRate: number, recvKbps: number, expiresAt: number } } = {}
local _activeRowInstances: { [string]: Frame } = {}
local _lastRateSnapshot: { any } = {}

local _fpsConnection: RBXScriptConnection? = nil
local _inputConnection: RBXScriptConnection? = nil
local _isLoopRunning = false

local FADE_INFO = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local BG_COLOR = Color3.fromRGB(15, 18, 25)
local CARD_COLOR = Color3.fromRGB(22, 27, 38)
local BORDER_COLOR = Color3.fromRGB(45, 55, 75)
local INNER_BORDER_COLOR = Color3.fromRGB(38, 48, 66)
local ACCENT_COLOR = Color3.fromRGB(0, 180, 255)
local WHITE = Color3.fromRGB(240, 244, 255)
local MUTED = Color3.fromRGB(140, 150, 175)

local ALERT_GREEN = Color3.fromRGB(100, 220, 140)
local ALERT_YELLOW = Color3.fromRGB(240, 200, 80)
local ALERT_RED = Color3.fromRGB(255, 90, 90)

local function formatNumber(n: number): string
	local s = tostring(math.floor(n))
	local formatted = s
	while true do
		local k
		formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
		if k == 0 then
			break
		end
	end
	return formatted
end

-- profiler telemetry on/off follows the panel so it costs nothing while closed
local function setTelemetryActive(active: boolean)
	Channel.Telemetry.Enabled = active
	if not active then
		table.clear(Channel.Telemetry.Sent)
		table.clear(Channel.Telemetry.Received)
		table.clear(_lastTelemetry.Sent)
		table.clear(_lastTelemetry.Received)
	end
	task.spawn(function()
		Relay.Debug.SetTelemetry.send({ enabled = active })
	end)
end

local function createCard(parent: Instance, title: string)
	local card = Instance.new("Frame")
	card.BackgroundColor3 = CARD_COLOR
	card.BorderSizePixel = 0
	card.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = card

	local stroke = Instance.new("UIStroke")
	stroke.Color = INNER_BORDER_COLOR
	stroke.Thickness = 1
	stroke.Parent = card

	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.Position = UDim2.fromOffset(12, 10)
	titleLabel.Size = UDim2.new(1, -24, 0, 14)
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.Text = title:upper()
	titleLabel.TextColor3 = MUTED
	titleLabel.TextSize = 10
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Parent = card

	local valLabel = Instance.new("TextLabel")
	valLabel.BackgroundTransparency = 1
	valLabel.Position = UDim2.fromOffset(12, 28)
	valLabel.Size = UDim2.new(1, -24, 0, 36)
	valLabel.Font = Enum.Font.GothamBold
	valLabel.Text = "--"
	valLabel.TextColor3 = WHITE
	valLabel.TextSize = 20
	valLabel.TextXAlignment = Enum.TextXAlignment.Left
	valLabel.Parent = card

	return card, valLabel
end

local function getOrCreateRow(parent: Instance, name: string): Frame
	local existing = _activeRowInstances[name]
	if existing then
		return existing
	end

	local row = Instance.new("Frame")
	row.Name = name
	row.BorderSizePixel = 0
	row.Size = UDim2.new(1, -8, 0, 32)
	row.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = row

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "EventName"
	nameLabel.BackgroundTransparency = 1
	nameLabel.Position = UDim2.fromOffset(12, 0)
	nameLabel.Size = UDim2.new(0.4, -12, 1, 0)
	nameLabel.Font = Enum.Font.GothamMedium
	nameLabel.Text = name
	nameLabel.TextColor3 = ACCENT_COLOR
	nameLabel.TextSize = 12
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Parent = row

	local sentRate = Instance.new("TextLabel")
	sentRate.Name = "SentRate"
	sentRate.BackgroundTransparency = 1
	sentRate.Position = UDim2.fromScale(0.4, 0)
	sentRate.Size = UDim2.fromScale(0.12, 1)
	sentRate.Font = Enum.Font.Gotham
	sentRate.Text = "0.0 Hz"
	sentRate.TextColor3 = WHITE
	sentRate.TextSize = 12
	sentRate.TextXAlignment = Enum.TextXAlignment.Center
	sentRate.Parent = row

	local recvRate = Instance.new("TextLabel")
	recvRate.Name = "RecvRate"
	recvRate.BackgroundTransparency = 1
	recvRate.Position = UDim2.fromScale(0.52, 0)
	recvRate.Size = UDim2.fromScale(0.12, 1)
	recvRate.Font = Enum.Font.Gotham
	recvRate.Text = "0.0 Hz"
	recvRate.TextColor3 = WHITE
	recvRate.TextSize = 12
	recvRate.TextXAlignment = Enum.TextXAlignment.Center
	recvRate.Parent = row

	local sentBandwidth = Instance.new("TextLabel")
	sentBandwidth.Name = "SentBandwidth"
	sentBandwidth.BackgroundTransparency = 1
	sentBandwidth.Position = UDim2.fromScale(0.64, 0)
	sentBandwidth.Size = UDim2.new(0.14, -8, 1, 0)
	sentBandwidth.Font = Enum.Font.GothamMedium
	sentBandwidth.Text = "0.00 KB/s"
	sentBandwidth.TextColor3 = MUTED
	sentBandwidth.TextSize = 12
	sentBandwidth.TextXAlignment = Enum.TextXAlignment.Right
	sentBandwidth.Parent = row

	local recvBandwidth = Instance.new("TextLabel")
	recvBandwidth.Name = "RecvBandwidth"
	recvBandwidth.BackgroundTransparency = 1
	recvBandwidth.Position = UDim2.fromScale(0.78, 0)
	recvBandwidth.Size = UDim2.new(0.14, -8, 1, 0)
	recvBandwidth.Font = Enum.Font.GothamMedium
	recvBandwidth.Text = "0.00 KB/s"
	recvBandwidth.TextColor3 = MUTED
	recvBandwidth.TextSize = 12
	recvBandwidth.TextXAlignment = Enum.TextXAlignment.Right
	recvBandwidth.Parent = row

	_activeRowInstances[name] = row
	return row
end

local function readStatsItemContains(nameParts: { string }): number?
	local descendants = Stats:GetDescendants()
	for _, descendant in descendants do
		local lowerName = string.lower(descendant.Name)
		local matches = true
		for _, part in nameParts do
			if not string.find(lowerName, part, 1, true) then
				matches = false
				break
			end
		end
		if matches then
			local success, value = pcall(function()
				return (descendant :: any):GetValue()
			end)
			if success and type(value) == "number" then
				return value
			end
		end
	end
	return nil
end

local function toggleUI()
	if not _screenGui or not _mainFrame then
		return
	end

	if _screenGui.Enabled then
		setTelemetryActive(false)
		local tw = TweenService:Create(_mainFrame, FADE_INFO, {
			GroupTransparency = 1,
			Size = UDim2.fromOffset(720, 420),
		})
		tw.Completed:Connect(function()
			if _mainFrame and _mainFrame.GroupTransparency >= 0.99 then
				if _screenGui then
					_screenGui.Enabled = false
				end
			end
		end)
		tw:Play()
	else
		setTelemetryActive(true)
		_mainFrame.GroupTransparency = 1
		_mainFrame.Size = UDim2.fromOffset(720, 420)
		_screenGui.Enabled = true
		local tw = TweenService:Create(_mainFrame, FADE_INFO, {
			GroupTransparency = 0,
			Size = UDim2.fromOffset(720, 480),
		})
		tw:Play()
	end
end

local function printSnapshot()
	local lines = {
		"=== Network Profiler Snapshot ===",
		string.format("time=%.2f", os.clock()),
	}

	if #_lastRateSnapshot == 0 then
		table.insert(lines, "No profiler rows captured yet. Open the profiler and wait one refresh.")
	else
		for _, row in _lastRateSnapshot do
			table.insert(
				lines,
				string.format(
					"%s | sentHz=%.1f recvHz=%.1f sentKBs=%.2f recvKBs=%.2f",
					tostring(row.name),
					row.sentRate or 0,
					row.recvRate or 0,
					row.sentKbps or 0,
					row.recvKbps or 0
				)
			)
		end
	end

	print(table.concat(lines, "\n"))
end

local function updateProfiler(elapsed: number)
	if not _screenGui or not _screenGui.Enabled or not _scrollFrame then
		return
	end

	-- 1. frame-average FPS
	local totalTime = 0
	for _, val in _fpsValues do
		totalTime += val
	end
	local fps = if totalTime > 0 then #_fpsValues / totalTime else 60
	if _fpsLabel then
		_fpsLabel.Text = string.format("%.1f FPS", fps)
		if fps >= 55 then
			_fpsLabel.TextColor3 = ALERT_GREEN
		elseif fps >= 30 then
			_fpsLabel.TextColor3 = ALERT_YELLOW
		else
			_fpsLabel.TextColor3 = ALERT_RED
		end
	end

	-- 2. stat cards
	local ping = 0
	if _localPlayer then
		local success, val = pcall(function()
			return (_localPlayer :: Player):GetNetworkPing() * 1000
		end)
		if success and val then
			ping = val
		end
	end
	if _pingLabel then
		_pingLabel.Text = string.format("%.0f ms", ping)
		if ping < 80 then
			_pingLabel.TextColor3 = ALERT_GREEN
		elseif ping < 200 then
			_pingLabel.TextColor3 = ALERT_YELLOW
		else
			_pingLabel.TextColor3 = ALERT_RED
		end
	end

	if _memLabel then
		_memLabel.Text = string.format("%.1f MB", Stats:GetTotalMemoryUsageMb())
	end

	if _instancesLabel then
		_instancesLabel.Text = formatNumber(Stats.InstanceCount)
	end

	-- 3. network telemetry rates
	local tele = Channel.Telemetry
	if not tele or not tele.Sent or not tele.Received then
		return
	end

	local allBridges: { [string]: boolean } = {}
	for name in tele.Sent do
		allBridges[name] = true
	end
	for name in tele.Received do
		allBridges[name] = true
	end

	type CompiledRate = {
		name: string,
		sentRate: number,
		recvRate: number,
		sentKbps: number,
		recvKbps: number,
		currentKbps: number,
	}
	local rates: { CompiledRate } = {}
	local relayRecvKbps = 0

	for name in allBridges do
		local sentCurrent = tele.Sent[name] or { count = 0, bytes = 0 }
		local sentLast = _lastTelemetry.Sent[name] or { count = 0, bytes = 0 }

		local recvCurrent = tele.Received[name] or { count = 0, bytes = 0 }
		local recvLast = _lastTelemetry.Received[name] or { count = 0, bytes = 0 }

		local sentRate = (sentCurrent.count - sentLast.count) / elapsed
		local recvRate = (recvCurrent.count - recvLast.count) / elapsed

		local sentBytesRate = (sentCurrent.bytes - sentLast.bytes) / elapsed
		local recvBytesRate = (recvCurrent.bytes - recvLast.bytes) / elapsed
		local recvKbps = math.max(0, recvBytesRate / 1024)
		if name ~= "Debug_ReplicaTelemetry" then
			relayRecvKbps += recvKbps
		end

		table.insert(rates, {
			name = name,
			sentRate = math.max(0, sentRate),
			recvRate = math.max(0, recvRate),
			sentKbps = math.max(0, sentBytesRate / 1024),
			recvKbps = recvKbps,
			currentKbps = math.max(0, (sentBytesRate + recvBytesRate) / 1024),
		})
	end

	local now = os.clock()
	local externalRecvKbps = 0
	for name, row in _externalTelemetryRows do
		if row.expiresAt < now then
			_externalTelemetryRows[name] = nil
			continue
		end
		externalRecvKbps += row.recvKbps
		table.insert(rates, {
			name = name,
			sentRate = 0,
			recvRate = row.recvRate,
			sentKbps = 0,
			recvKbps = row.recvKbps,
			currentKbps = row.recvKbps,
		})
	end

	local totalRecv = readStatsItemContains({ "data", "receive" }) or readStatsItemContains({ "recv" })
	if totalRecv and totalRecv > 0 then
		table.insert(rates, {
			name = "__Roblox_Total_DataReceive",
			sentRate = 0,
			recvRate = 0,
			sentKbps = 0,
			recvKbps = totalRecv,
			currentKbps = totalRecv,
		})

		local gap = math.max(0, totalRecv - relayRecvKbps - externalRecvKbps)
		table.insert(rates, {
			name = "__Estimated_Untracked_Gap",
			sentRate = 0,
			recvRate = 0,
			sentKbps = 0,
			recvKbps = gap,
			currentKbps = gap,
		})
	end

	-- sort by current bandwidth so the active bottleneck rises to the top
	table.sort(rates, function(a, b)
		return a.currentKbps > b.currentKbps
	end)
	_lastRateSnapshot = table.clone(rates)

	-- drop row instances for bridges that disappeared (telemetry reset / expiry)
	local liveNames: { [string]: boolean } = {}
	for _, r in rates do
		liveNames[r.name] = true
	end
	for name, row in _activeRowInstances do
		if not liveNames[name] then
			row:Destroy()
			_activeRowInstances[name] = nil
		end
	end

	for i, r in rates do
		local row = getOrCreateRow(_scrollFrame :: ScrollingFrame, r.name)
		row.LayoutOrder = i
		row.BackgroundColor3 = if i % 2 == 0 then Color3.fromRGB(24, 28, 38) else Color3.fromRGB(20, 24, 33)

		local sentLabel = row:FindFirstChild("SentRate") :: TextLabel?
		if sentLabel then
			sentLabel.Text = string.format("%.1f Hz", r.sentRate)
			sentLabel.TextColor3 = if r.sentRate > 0 then WHITE else MUTED
		end

		local recvLabel = row:FindFirstChild("RecvRate") :: TextLabel?
		if recvLabel then
			recvLabel.Text = string.format("%.1f Hz", r.recvRate)
			recvLabel.TextColor3 = if r.recvRate > 0 then WHITE else MUTED
		end

		local sentKb = row:FindFirstChild("SentBandwidth") :: TextLabel?
		if sentKb then
			sentKb.Text = string.format("%.2f KB/s", r.sentKbps)
			sentKb.TextColor3 = if r.sentKbps > 5.0
				then ALERT_RED
				elseif r.sentKbps > 1.0 then ALERT_YELLOW
				elseif r.sentKbps > 0 then ALERT_GREEN
				else MUTED
		end

		local recvKb = row:FindFirstChild("RecvBandwidth") :: TextLabel?
		if recvKb then
			recvKb.Text = string.format("%.2f KB/s", r.recvKbps)
			recvKb.TextColor3 = if r.recvKbps > 5.0
				then ALERT_RED
				elseif r.recvKbps > 1.0 then ALERT_YELLOW
				elseif r.recvKbps > 0 then ALERT_GREEN
				else MUTED
		end
	end

	-- snapshot telemetry to diff next refresh
	_lastTelemetry.Sent = {}
	for name, entry in tele.Sent do
		_lastTelemetry.Sent[name] = { count = entry.count, bytes = entry.bytes }
	end
	_lastTelemetry.Received = {}
	for name, entry in tele.Received do
		_lastTelemetry.Received[name] = { count = entry.count, bytes = entry.bytes }
	end
end

function PerformanceDebug:Start(_fw: any)
	local localPlayer = Players.LocalPlayer
	if not localPlayer then
		return
	end

	-- Studio always; live servers only for listed developers
	if not RunService:IsStudio() and not table.find(DebugConfig.DeveloperIds, localPlayer.UserId) then
		return
	end

	_localPlayer = localPlayer
	local playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui

	local sg = Instance.new("ScreenGui")
	sg.Name = "PerformanceDebugGui"
	sg.ResetOnSpawn = false
	sg.IgnoreGuiInset = true
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	sg.DisplayOrder = 9999
	sg.Enabled = false
	sg.Parent = playerGui
	_screenGui = sg

	local main = Instance.new("CanvasGroup")
	main.Name = "MainFrame"
	main.AnchorPoint = Vector2.new(0.5, 0.5)
	main.Position = UDim2.fromScale(0.5, 0.5)
	main.Size = UDim2.fromOffset(720, 480)
	main.BackgroundColor3 = BG_COLOR
	main.BorderSizePixel = 0
	main.GroupTransparency = 0
	main.Parent = sg
	_mainFrame = main

	local mainCorner = Instance.new("UICorner")
	mainCorner.CornerRadius = UDim.new(0, 12)
	mainCorner.Parent = main

	local mainStroke = Instance.new("UIStroke")
	mainStroke.Color = BORDER_COLOR
	mainStroke.Thickness = 1.5
	mainStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	mainStroke.Parent = main

	local topBar = Instance.new("Frame")
	topBar.Name = "TopBar"
	topBar.BackgroundTransparency = 1
	topBar.Size = UDim2.new(1, 0, 0, 45)
	topBar.Parent = main

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(16, 0)
	title.Size = UDim2.new(1, -180, 1, 0)
	title.Font = Enum.Font.GothamBold
	title.Text = "SYSTEM PERFORMANCE & NETWORK PROFILER"
	title.TextColor3 = WHITE
	title.TextSize = 13
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = topBar

	local printBtn = Instance.new("TextButton")
	printBtn.Name = "PrintButton"
	printBtn.BackgroundColor3 = Color3.fromRGB(26, 32, 44)
	printBtn.Position = UDim2.new(1, -142, 0, 9)
	printBtn.Size = UDim2.fromOffset(96, 26)
	printBtn.Font = Enum.Font.GothamBold
	printBtn.Text = "PRINT"
	printBtn.TextColor3 = ACCENT_COLOR
	printBtn.TextSize = 11
	printBtn.Parent = topBar

	local printCorner = Instance.new("UICorner")
	printCorner.CornerRadius = UDim.new(0, 6)
	printCorner.Parent = printBtn

	local printStroke = Instance.new("UIStroke")
	printStroke.Color = INNER_BORDER_COLOR
	printStroke.Thickness = 1
	printStroke.Parent = printBtn

	printBtn.Activated:Connect(printSnapshot)

	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseButton"
	closeBtn.BackgroundTransparency = 1
	closeBtn.Position = UDim2.new(1, -40, 0, 7)
	closeBtn.Size = UDim2.fromOffset(30, 30)
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.Text = "✕"
	closeBtn.TextColor3 = MUTED
	closeBtn.TextSize = 16
	closeBtn.Parent = topBar
	closeBtn.Activated:Connect(function()
		toggleUI()
	end)

	local headerSep = Instance.new("Frame")
	headerSep.Name = "HeaderSeparator"
	headerSep.Position = UDim2.fromOffset(0, 45)
	headerSep.Size = UDim2.new(1, 0, 0, 1)
	headerSep.BackgroundColor3 = BORDER_COLOR
	headerSep.BorderSizePixel = 0
	headerSep.Parent = main

	local statsFrame = Instance.new("Frame")
	statsFrame.Name = "StatsFrame"
	statsFrame.BackgroundTransparency = 1
	statsFrame.Position = UDim2.fromOffset(16, 60)
	statsFrame.Size = UDim2.new(1, -32, 0, 75)
	statsFrame.Parent = main

	local statsLayout = Instance.new("UIListLayout")
	statsLayout.FillDirection = Enum.FillDirection.Horizontal
	statsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	statsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	statsLayout.Padding = UDim.new(0, 12)
	statsLayout.Parent = statsFrame

	local cardWidth = UDim2.new(0.25, -9, 1, 0)

	local card1, fpsLbl = createCard(statsFrame, "Client FPS")
	card1.Size = cardWidth
	card1.LayoutOrder = 1
	_fpsLabel = fpsLbl

	local card2, pingLbl = createCard(statsFrame, "Ping (Latency)")
	card2.Size = cardWidth
	card2.LayoutOrder = 2
	_pingLabel = pingLbl

	local card3, memLbl = createCard(statsFrame, "Total Memory")
	card3.Size = cardWidth
	card3.LayoutOrder = 3
	_memLabel = memLbl

	local card4, instLbl = createCard(statsFrame, "Active Instances")
	card4.Size = cardWidth
	card4.LayoutOrder = 4
	_instancesLabel = instLbl

	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.BackgroundTransparency = 1
	subtitle.Position = UDim2.fromOffset(16, 155)
	subtitle.Size = UDim2.new(1, -32, 0, 20)
	subtitle.Font = Enum.Font.GothamBold
	subtitle.Text = "ACTIVE NETWORK TRANSACTIONS (SORTED BY VOLUME)"
	subtitle.TextColor3 = MUTED
	subtitle.TextSize = 10
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.Parent = main

	local tableContainer = Instance.new("Frame")
	tableContainer.Name = "TableContainer"
	tableContainer.Position = UDim2.fromOffset(16, 185)
	tableContainer.Size = UDim2.new(1, -32, 1, -200)
	tableContainer.BackgroundColor3 = Color3.fromRGB(20, 24, 33)
	tableContainer.BorderSizePixel = 0
	tableContainer.Parent = main

	local tableCorner = Instance.new("UICorner")
	tableCorner.CornerRadius = UDim.new(0, 8)
	tableCorner.Parent = tableContainer

	local tableStroke = Instance.new("UIStroke")
	tableStroke.Color = INNER_BORDER_COLOR
	tableStroke.Thickness = 1
	tableStroke.Parent = tableContainer

	local tableHeader = Instance.new("Frame")
	tableHeader.Name = "TableHeader"
	tableHeader.Size = UDim2.new(1, 0, 0, 30)
	tableHeader.BackgroundColor3 = Color3.fromRGB(26, 32, 44)
	tableHeader.BorderSizePixel = 0
	tableHeader.Parent = tableContainer

	local headerCorner = Instance.new("UICorner")
	headerCorner.CornerRadius = UDim.new(0, 8)
	headerCorner.Parent = tableHeader

	local cornerFix = Instance.new("Frame")
	cornerFix.Name = "CornerFix"
	cornerFix.Position = UDim2.new(0, 0, 1, -4)
	cornerFix.Size = UDim2.new(1, 0, 0, 4)
	cornerFix.BackgroundColor3 = Color3.fromRGB(26, 32, 44)
	cornerFix.BorderSizePixel = 0
	cornerFix.Parent = tableHeader

	local function addHeaderCol(text: string, xPos: number, width: number, align: Enum.TextXAlignment)
		local lbl = Instance.new("TextLabel")
		lbl.BackgroundTransparency = 1
		lbl.Position = UDim2.fromScale(xPos, 0)
		lbl.Size = UDim2.fromScale(width, 1)
		lbl.Font = Enum.Font.GothamBold
		lbl.Text = text
		lbl.TextColor3 = MUTED
		lbl.TextSize = 10
		lbl.TextXAlignment = align
		lbl.Parent = tableHeader
	end

	addHeaderCol("EVENT BRIDGE NAME", 0.02, 0.38, Enum.TextXAlignment.Left)
	addHeaderCol("SENT RATE", 0.4, 0.12, Enum.TextXAlignment.Center)
	addHeaderCol("RECV RATE", 0.52, 0.12, Enum.TextXAlignment.Center)
	addHeaderCol("SENT BANDWIDTH", 0.64, 0.14, Enum.TextXAlignment.Right)
	addHeaderCol("RECV BANDWIDTH", 0.78, 0.14, Enum.TextXAlignment.Right)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "ScrollingFrame"
	scroll.Position = UDim2.fromOffset(4, 34)
	scroll.Size = UDim2.new(1, -8, 1, -38)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = Color3.fromRGB(60, 75, 100)
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = tableContainer
	_scrollFrame = scroll

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 4)
	listLayout.Parent = scroll

	-- server-reported rows (replica writes etc.)
	Relay.Debug.ReplicaTelemetry.listen(function(payload: any)
		local rows = payload and payload.rows
		if type(rows) ~= "table" then
			return
		end
		local expiresAt = os.clock() + 1.5
		for _, row in rows do
			if type(row) ~= "table" or type(row.name) ~= "string" then
				continue
			end
			local count = if type(row.count) == "number" then row.count else 0
			local bytes = if type(row.bytes) == "number" then row.bytes else 0
			_externalTelemetryRows[row.name] = {
				recvRate = count,
				recvKbps = math.max(0, bytes / 1024),
				expiresAt = expiresAt,
			}
		end
	end)

	_inputConnection = UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == DebugConfig.ToggleKey then
			toggleUI()
		end
	end)

	-- rolling 1-second window of frame times for average FPS
	_fpsConnection = RunService.RenderStepped:Connect(function(dt: number)
		table.insert(_fpsValues, dt)
		local total = 0
		for i = #_fpsValues, 1, -1 do
			total += _fpsValues[i]
			if total > 1.0 then
				table.remove(_fpsValues, i)
			end
		end
	end)

	_isLoopRunning = true
	task.spawn(function()
		local lastTime = os.clock()
		while _isLoopRunning do
			task.wait(0.5)
			if not _isLoopRunning then
				break
			end
			if not sg.Enabled then
				lastTime = os.clock()
				continue
			end

			local now = os.clock()
			local elapsed = now - lastTime
			lastTime = now
			if elapsed <= 0 then
				elapsed = 0.5
			end

			local ok, err = pcall(updateProfiler, elapsed)
			if not ok then
				warn("[PerformanceDebug] Update loop failed:", err)
			end
		end
	end)
end

function PerformanceDebug:Destroy()
	_isLoopRunning = false
	setTelemetryActive(false)

	if _inputConnection then
		_inputConnection:Disconnect()
		_inputConnection = nil
	end

	if _fpsConnection then
		_fpsConnection:Disconnect()
		_fpsConnection = nil
	end

	if _screenGui then
		_screenGui:Destroy()
		_screenGui = nil
	end

	table.clear(_fpsValues)
	table.clear(_activeRowInstances)
end

return PerformanceDebug
