-- Module: VirtualScroller
-- Version: 1.0.0
-- Made by: @richmensch
-- Date: October 12, 2025
-- Documentation: https://mensch-dev.github.io/VirtualScroller/

local VirtualScroller = {}

--- When `GridCellSize` is set, layout matches UIGridLayout: cell pixels + padding pixels from parent AbsoluteSize.
function VirtualScroller:_refreshGridPixelMetrics()
	if not self.UsePixelGrid or not self.GridCellSize then
		return
	end
	local ax = self.ScrollingFrame.AbsoluteSize.X
	local ay = self.ScrollingFrame.AbsoluteSize.Y
	local cs = self.GridCellSize
	local cp = self.GridCellPadding or UDim2.new(0, 0, 0, 0)
	local cellW = cs.X.Scale * ax + cs.X.Offset
	local cellH = cs.Y.Scale * ay + cs.Y.Offset
	local padX = cp.X.Scale * ax + cp.X.Offset
	local padY = cp.Y.Scale * ay + cp.Y.Offset
	self._cellWpx = math.max(1, math.floor(cellW + 0.5))
	self._cellHpx = math.max(1, math.floor(cellH + 0.5))
	self._padXpx = math.max(0, math.floor(padX + 0.5))
	self._padYpx = math.max(0, math.floor(padY + 0.5))
	self._rowStepY = self._cellHpx + self._padYpx
	self._colStepX = self._cellWpx + self._padXpx
	self.ItemHeightOffset = math.max(1, self._rowStepY)
end

local function countTable(t)
	local count = 0
	for _ in pairs(t) do
		count += 1
	end
	return count
end

function VirtualScroller.new(
	scrollingFrame,
	itemTemplate,
	dataTable,
	itemHeight,
	numColumns,
	itemWidthScale,
	bufferRows,
	applyDataFunction,
	itemSetupFunction,
	onItemShown,
	onItemHidden,
	onScrolled,
	gridCellSize,
	gridCellPadding
)
	local self = setmetatable({}, { __index = VirtualScroller })

	self.ScrollingFrame = scrollingFrame
	self.ItemTemplate = itemTemplate
	self.Data = dataTable or {}
	self.ItemHeight = itemHeight or UDim.new(0.1, 0)
	self.NumColumns = numColumns or 1
	self.ItemWidthScale = itemWidthScale or (1 / self.NumColumns)
	self.BufferRows = bufferRows or 15
	self.ApplyDataFunction = applyDataFunction
	self.ItemSetupFunction = itemSetupFunction
	self.OnItemShown = onItemShown
	self.OnItemHidden = onItemHidden
	self.OnScrolled = onScrolled
	self.UsePixelGrid = typeof(gridCellSize) == "UDim2"
	self.GridCellSize = if self.UsePixelGrid then gridCellSize :: UDim2 else nil
	self.GridCellPadding = if self.UsePixelGrid and typeof(gridCellPadding) == "UDim2"
		then gridCellPadding :: UDim2
		else UDim2.new(0, 0, 0, 0)
	self.FramePool = {}
	self.ActiveFrames = {}
	self.LastCanvasPos = 0
	self.IsUpdating = false
	self.IsScrolling = false

	self.ScrollingFrame.AutomaticCanvasSize = Enum.AutomaticSize.None
	self.ScrollingFrame.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
	self.ScrollingFrame.ScrollingDirection = Enum.ScrollingDirection.Y
	self.ScrollingFrame.ScrollBarThickness = 10
	self.ScrollingFrame.ClipsDescendants = true
	self.ItemTemplate.Visible = false

	function self.GetItemHeightOffset(this)
		if this.UsePixelGrid then
			this:_refreshGridPixelMetrics()
			return this.ItemHeightOffset
		end
		local frameY = this.ScrollingFrame.AbsoluteSize.Y
		if typeof(this.ItemHeight) == "number" then
			return this.ItemHeight
		elseif typeof(this.ItemHeight) == "UDim" then
			return this.ItemHeight.Scale * frameY + this.ItemHeight.Offset
		end
		return 100
	end
	if self.UsePixelGrid then
		self:_refreshGridPixelMetrics()
	else
		self.ItemHeightOffset = self:GetItemHeightOffset()
	end

	local viewportY = self.ScrollingFrame.AbsoluteSize.Y
	local visibleRows = math.ceil(viewportY / self.ItemHeightOffset)
	self.PoolSize = math.min(500, (visibleRows + self.BufferRows * 2) * self.NumColumns + 10)

	self:InitializePool()

	self.ScrollConnection = self.ScrollingFrame:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		local posY = self.ScrollingFrame.CanvasPosition.Y
		self.IsScrolling = true
		if not self.IsUpdating then
			self:UpdateVisibleItems()
		end
		if self.OnScrolled then
			self.OnScrolled(posY)
		end
		task.delay(0.2, function()
			if self.LastCanvasPos == self.ScrollingFrame.CanvasPosition.Y then
				self.IsScrolling = false
			end
		end)
	end)
	self.ResizeConnection = self.ScrollingFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if self.UsePixelGrid then
			self:_refreshGridPixelMetrics()
		else
			self.ItemHeightOffset = self:GetItemHeightOffset()
		end
		local resizedRows = math.ceil(self.ScrollingFrame.AbsoluteSize.Y / self.ItemHeightOffset)
		self.PoolSize = math.min(500, (resizedRows + self.BufferRows * 2) * self.NumColumns + 10)
		self:UpdateCanvasSize()
		if not self.IsUpdating then
			self:UpdateVisibleItems()
		end
	end)

	self:UpdateCanvasSize()
	self:UpdateVisibleItems()

	return self
end

function VirtualScroller:GetVisibleItemCount()
	return countTable(self.ActiveFrames)
end

function VirtualScroller:InitializePool()
	if self.UsePixelGrid then
		self:_refreshGridPixelMetrics()
	end
	for _ = 1, self.PoolSize do
		local frame = self.ItemTemplate:Clone()
		frame.Visible = false
		frame.Position = UDim2.new(0, 0, 0, 0)
		if self.UsePixelGrid then
			frame.Size = UDim2.fromOffset(self._cellWpx, self._cellHpx)
		else
			frame.Size = UDim2.new(self.ItemWidthScale - 0.01, 0, 0, self.ItemHeightOffset)
		end
		frame.Parent = self.ScrollingFrame
		if self.ItemSetupFunction then
			self.ItemSetupFunction(frame, self)
		end
		table.insert(self.FramePool, frame)
	end
end

function VirtualScroller:UpdateCanvasSize()
	local totalRows = math.ceil(#self.Data / self.NumColumns)
	if self.UsePixelGrid then
		self:_refreshGridPixelMetrics()
		local cellH = self._cellHpx
		local padY = self._padYpx
		local h = if totalRows <= 0 then 1 else totalRows * cellH + math.max(0, totalRows - 1) * padY
		self.ScrollingFrame.CanvasSize = UDim2.fromOffset(0, h)
		return
	end
	self.ScrollingFrame.CanvasSize = UDim2.fromOffset(0, totalRows * self.ItemHeightOffset)
end

function VirtualScroller:UpdateVisibleItems()
	if self.IsUpdating then
		return
	end
	self.IsUpdating = true

	if self.UsePixelGrid then
		self:_refreshGridPixelMetrics()
	end

	local viewportPixels = self.ScrollingFrame.AbsoluteSize.Y
	local canvasPosPixels = self.ScrollingFrame.CanvasPosition.Y
	local itemHeightPixels = self.ItemHeightOffset

	if itemHeightPixels == 0 then
		self.IsUpdating = false
		return
	end

	self.LastCanvasPos = canvasPosPixels

	local bufferPixels = self.BufferRows * itemHeightPixels
	local startRow = math.max(0, math.floor((canvasPosPixels - bufferPixels) / itemHeightPixels))
	local endRow = math.ceil((canvasPosPixels + viewportPixels + bufferPixels) / itemHeightPixels)
	local startIndex = startRow * self.NumColumns + 1
	local endIndex = math.min(#self.Data, endRow * self.NumColumns)

	local toRecycle = {}
	for index, frame in pairs(self.ActiveFrames) do
		if index < startIndex or index > endIndex or not self.Data[index] then
			toRecycle[index] = frame
		end
	end
	for index, frame in pairs(toRecycle) do
		frame.Visible = false
		frame.Position = UDim2.new(0, 0, 0, 0)
		frame:SetAttribute("Index", nil)
		table.insert(self.FramePool, frame)
		self.ActiveFrames[index] = nil
		if self.OnItemHidden then
			self.OnItemHidden(index, frame)
		end
	end

	for i = startIndex, endIndex do
		if self.Data[i] then
			local frame = self.ActiveFrames[i]
			local wasNew = false
			if not frame then
				if #self.FramePool == 0 then
					if #self.FramePool + countTable(self.ActiveFrames) < 500 then
						frame = self.ItemTemplate:Clone()
						frame.Visible = false
						frame.Position = UDim2.new(0, 0, 0, 0)
						if self.UsePixelGrid then
							self:_refreshGridPixelMetrics()
							frame.Size = UDim2.fromOffset(self._cellWpx, self._cellHpx)
						else
							frame.Size = UDim2.new(self.ItemWidthScale - 0.01, 0, 0, self.ItemHeightOffset)
						end
						frame.Parent = self.ScrollingFrame
						if self.ItemSetupFunction then
							self.ItemSetupFunction(frame, self)
						end
					else
						frame = table.remove(self.FramePool, 1)
					end
				else
					frame = table.remove(self.FramePool)
				end
				self.ActiveFrames[i] = frame
				wasNew = true
			end
			self:ApplyDataToFrame(frame, self.Data[i], i)
			if wasNew and self.OnItemShown then
				self.OnItemShown(i, frame, self.Data[i])
			end
		end
	end

	self.IsUpdating = false
end

--- Position/size for one cell (no data callback).
function VirtualScroller:ApplyLayoutToFrame(frame: Instance, index: number)
	local gui = frame :: GuiObject
	local row = math.floor((index - 1) / self.NumColumns)
	local col = (index - 1) % self.NumColumns
	local newPos: UDim2
	local newSize: UDim2
	if self.UsePixelGrid then
		local x = col * self._colStepX
		local y = row * self._rowStepY
		newPos = UDim2.fromOffset(x, y)
		newSize = UDim2.fromOffset(self._cellWpx, self._cellHpx)
	else
		newPos = UDim2.new(col * self.ItemWidthScale, 0, 0, row * self.ItemHeightOffset)
		newSize = UDim2.new(self.ItemWidthScale - 0.01, 0, 0, self.ItemHeightOffset)
	end

	gui.Position = newPos
	gui.Size = newSize
	gui.Visible = true
	gui.ClipsDescendants = true
end

--- Swap a visible pooled cell for another `Frame` (e.g. rarity template mismatch). Updates ActiveFrames / FramePool.
function VirtualScroller:ReplaceActiveFrame(index: number, oldFrame: Instance, newFrame: Frame)
	if self.ActiveFrames[index] ~= oldFrame then
		return
	end
	for i = 1, #self.FramePool do
		if self.FramePool[i] == oldFrame then
			self.FramePool[i] = newFrame
			break
		end
	end
	self.ActiveFrames[index] = newFrame
	oldFrame:Destroy()
	newFrame.Parent = self.ScrollingFrame
	self:ApplyLayoutToFrame(newFrame, index)
end

function VirtualScroller:ApplyDataToFrame(frame, dataItem, index)
	self:ApplyLayoutToFrame(frame, index)

	if self.ApplyDataFunction then
		self.ApplyDataFunction(frame, dataItem, index)
	else
		local nameLabel = frame:FindFirstChild("NameLabel")
		if nameLabel then
			nameLabel.Text = dataItem.Name or "Item " .. index
			nameLabel.Visible = true
		end
		local descLabel = frame:FindFirstChild("DescriptionLabel")
		if descLabel then
			descLabel.Text = dataItem.Description or ""
			descLabel.Visible = true
		end
	end

	local bound = self.ActiveFrames[index]
	if bound then
		(bound :: Instance):SetAttribute("Index", index)
	else
		frame:SetAttribute("Index", index)
	end
end

function VirtualScroller:ReloadData(newDataTable)
	self.Data = newDataTable or self.Data
	self:UpdateCanvasSize()
	self:UpdateVisibleItems()
end

function VirtualScroller:ScrollToIndex(index, animated)
	local row = math.floor((index - 1) / self.NumColumns)
	local targetPos = row * self.ItemHeightOffset
	if animated then
		local tweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		game:GetService("TweenService")
			:Create(self.ScrollingFrame, tweenInfo, { CanvasPosition = Vector2.new(0, targetPos) })
			:Play()
	else
		self.ScrollingFrame.CanvasPosition = Vector2.new(0, targetPos)
	end
end

function VirtualScroller:SortData(comparatorFunction)
	table.sort(self.Data, comparatorFunction)
	self:UpdateCanvasSize()
	self:UpdateVisibleItems()
end

function VirtualScroller:AddItem(dataItem, position)
	position = position or (#self.Data + 1)
	table.insert(self.Data, position, dataItem)

	local newActive = {}
	for oldIndex, frame in pairs(self.ActiveFrames) do
		if oldIndex >= position then
			newActive[oldIndex + 1] = frame
			self:ApplyDataToFrame(frame, self.Data[oldIndex + 1], oldIndex + 1)
		else
			newActive[oldIndex] = frame
		end
	end
	self.ActiveFrames = newActive

	self:UpdateCanvasSize()
	self:UpdateVisibleItems()
end

function VirtualScroller:RemoveItem(index)
	if self.Data[index] then
		table.remove(self.Data, index)

		local newActive = {}
		for oldIndex, frame in pairs(self.ActiveFrames) do
			if oldIndex > index then
				newActive[oldIndex - 1] = frame
				self:ApplyDataToFrame(frame, self.Data[oldIndex - 1], oldIndex - 1)
			elseif oldIndex < index then
				newActive[oldIndex] = frame
			else
				frame.Visible = false
				frame.Position = UDim2.new(0, 0, 0, 0)
				frame:SetAttribute("Index", nil)
				table.insert(self.FramePool, frame)
			end
		end
		self.ActiveFrames = newActive

		self:UpdateCanvasSize()
		self:UpdateVisibleItems()
	end
end

function VirtualScroller:Destroy()
	if self.ScrollConnection then
		self.ScrollConnection:Disconnect()
	end
	if self.ResizeConnection then
		self.ResizeConnection:Disconnect()
	end
	self.FramePool = {}
	self.ActiveFrames = {}
end

return VirtualScroller
