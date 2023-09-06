local SmartScroller = {}
SmartScroller.__index = SmartScroller

local TweenService = game:GetService("TweenService")

SmartScroller.ExpansionPolicy = {}
SmartScroller.ExpansionPolicy.None = 0x0
SmartScroller.ExpansionPolicy.Item = 0x1
SmartScroller.ExpansionPolicy.Offset = 0x2

local floor,ceil,min,max = math.floor, math.ceil, math.min, math.max

function SmartScroller.new(scroller : ScrollingFrame)
	local self = setmetatable({}, SmartScroller)
	
	self:Build(scroller)
	
	return self
end

function SmartScroller:Build(Scroller : ScrollingFrame)
	self.Scroller = Scroller
	Scroller:SetAttribute("NewSize", Scroller.Size)
	self.SizeX = self.Scroller.Size.X
	
	self.Scroller.CanvasSize = UDim2.new(0,0,0,0)
	self.Padding = UDim.new(0,0)

	self.ExpansionPolicy = SmartScroller.ExpansionPolicy.None
	self.ExpansionScalar = 5

	self.DoTween = true
	self.TweenSpeed = 0.25
	self.TweenDirection = Enum.EasingDirection.InOut
	self.TweenStyle = Enum.EasingStyle.Linear
	self.DoSort = false
	self.ExpandOutsideBounds = false

	self.Info = TweenInfo.new(self.TweenSpeed, self.TweenStyle, self.TweenDirection, 0, false, 0)

	self.CurrentYSize = 0
	self.TotalCanvasSize = 0
	self.CanvasBottomOffset = 0

	self.Items = {}
	self.OrganizedItems = {}
	self.NumItems = 0
	
	self.ChangeLog = {}
	
	self.SizeChangedEvent = Instance.new("BindableEvent")
	self.OnSizeChanged = self.SizeChangedEvent.Event
	
	self.CanvasSizeChangedEvent = Instance.new("BindableEvent")
	self.OnCanvasSizeChanged = self.CanvasSizeChangedEvent.Event
	
	local UIListLayout = Instance.new("UIListLayout")
	UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	UIListLayout.Parent = Scroller
	UIListLayout.Padding = self.Padding
	self.UIListLayout = UIListLayout
	
	local function onSizeChange()
		self:CalculateYSize()
	end
	
	local function onChildRemoved(object : Instance)
		local conTable = self.Items[object]
		if conTable then
			if conTable.SizeChangeCon then
				conTable.SizeChangeCon:Disconnect()
				conTable.SizeChangeCon = nil
			end
			
			if conTable.AttributeAddedCon then
				conTable.AttributeAddedCon:Disconnect()
				conTable.AttributeAddedCon = nil
			end
			
			if conTable.NameChangeCon then
				conTable.NameChangeCon:Disconnect()
				conTable.NameChangeCon = nil
			end
			
			self.Items[object] = nil
			self.NumItems = self.NumItems - 1
			
			self:OrganizeList()
			self:CalculateYSize()
		end
	end
	
	local function attributeAdded(object : Instance)
		local conTable = self.Items[object]
		if conTable then
			if conTable.AttributeAddedCon then
				conTable.AttributeAddedCon:Disconnect()
				conTable.AttributeAddedCon = nil
			end
			
			if conTable.SizeChangeCon then
				conTable.SizeChangeCon:Disconnect()
				conTable.SizeChangeCon = nil
			end
			
			conTable.SizeChangeCon = object:GetAttributeChangedSignal("NewSize"):Connect(onSizeChange)
			
			self:CalculateYSize()
		end
	end
	
	local function nameChanged()
		if self.DoSort then
			self:OrganizeList()
			self:CalculateYSize()
		end
	end
	
	local function onChildAdded(object : Instance)
		if object:IsA("GuiObject") and not self.Items[object] then
			self.Items[object] = true
			
			self.NumItems = self.NumItems + 1
			
			local ConnectionTable = {}
			
			if object:GetAttribute("NewSize") then
				ConnectionTable.SizeChangeCon = object:GetAttributeChangedSignal("NewSize"):Connect(onSizeChange)
			else
				ConnectionTable.AttributeAddedCon = object:GetAttributeChangedSignal("NewSize"):Connect(function() attributeAdded(object) end)
				ConnectionTable.SizeChangeCon = object:GetPropertyChangedSignal("AbsoluteSize"):Connect(onSizeChange)
			end
			
			ConnectionTable.NameChangeCon = object:GetPropertyChangedSignal("Name"):Connect(nameChanged)
			
			self.Items[object] = ConnectionTable
			
			self:CalculateYSize()
			self:OrganizeList()
			object.Destroying:Connect(function() onChildRemoved(object) end)
		end
	end

	Scroller.ChildAdded:Connect(onChildAdded)
	Scroller.ChildRemoved:Connect(onChildRemoved)

	for _,child in pairs(Scroller:GetChildren()) do
		onChildAdded(child)
	end
	self:CalculateYSize()
	
	assert(Scroller.Parent ~= nil, "Cannot assign a smart scroller to a nil object")
	Scroller.Parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(onSizeChange)
end

function SmartScroller:SetExpandOutsideBounds(expand : boolean)
	self.ExpandOutsideBounds = expand
end

function SmartScroller:SetOrderPolicy(OrderPolicy : Enum.SortOrder)
	self.UIListLayout.SortOrder = OrderPolicy
	self.DoSort = OrderPolicy == Enum.SortOrder.Name
	if self.DoSort then
		self:OrganizeList()
		self:CalculateYSize()
	end
end

function SmartScroller:OrganizeList()
	local posTable = {}
	for object : GuiObject, con in pairs(self.Items) do
		table.insert(posTable, object)
	end
	
	for i=1, #posTable - 1 do
		local currentIndex = i
		local currentHighestPoint = posTable[i].AbsoluteSize.Y
		
		for j=i+1, #posTable do
			local newPosY = posTable[j].AbsoluteSize.Y
			if newPosY < currentHighestPoint then
				currentIndex = j
				currentHighestPoint = newPosY
			end
		end
		
		local tmp = posTable[i]
		posTable[i] = posTable[currentIndex]
		posTable[currentIndex] = tmp
	end
	
	self.OrganizedItems = posTable
end

function SmartScroller:CalculateYSize()
	if not self.Scroller or not self.Scroller.Parent then return end
	
	local newCanvasSize, newYSize = 0, 0
	if self.NumItems ~= 0 then
		newCanvasSize = (self.NumItems - 1) * self.Padding.Offset + self.CanvasBottomOffset
		for object : GuiObject, connectionTable in pairs(self.Items) do
			local newSize = object:GetAttribute("NewSize")
			if newSize then
				newCanvasSize = newCanvasSize + newSize.Y.Offset
			else
				newCanvasSize = newCanvasSize + max(object.AbsoluteSize.Y, object.Size.Y.Offset)
			end
		end
	end
	
	local sizeMax = self.Scroller.Parent.AbsoluteSize.Y
	if self.ExpandOutsideBounds then
		sizeMax = self.Scroller:FindFirstAncestorOfClass("ScreenGui").AbsoluteSize.Y - self.Scroller.AbsolutePosition.Y
	end

	if self.ExpansionPolicy == SmartScroller.ExpansionPolicy.Item then
		local numItems = min(self.ExpansionScalar, self.NumItems)
		if numItems ~= 0 then
			if numItems == self.NumItems then
				newYSize = newCanvasSize
			else
				if not self.OrganizedItems[numItems] then self:OrganizeList() end

				for i=1, numItems do
					local obj = self.OrganizedItems[i]
					newYSize = newYSize + max(obj.AbsoluteSize.Y, obj.Size.Y.Offset)
				end
				
				newYSize = min(newYSize + self.Padding.Offset * (numItems - 1), sizeMax) 
			end
		else
			newCanvasSize = 0
			newYSize = 0
		end
	elseif self.ExpansionPolicy == SmartScroller.ExpansionPolicy.Offset then
		newYSize = min(self.ExpansionScalar, sizeMax)
	else
		newYSize = min(newCanvasSize, sizeMax)
	end
	
	if newYSize ~= self.CurrentYSize then
		self.CurrentYSize = newYSize
		local newSize = UDim2.new(self.SizeX.Scale, self.SizeX.Offset, 0, self.CurrentYSize)
		
		if self.SizeTween then self.SizeTween:Cancel() self.SizeTween = nil end
		
		self.SizeChangedEvent:Fire(newSize)
		if self.DoTween and not script.Parent:IsA("ScrollingFrame") then
			self.SizeTween = TweenService:Create(self.Scroller, self.Info, {Size = newSize})
			self.SizeTween:Play()
		else
			self.Scroller.Size = newSize
		end
	end
	
	if newCanvasSize ~= self.TotalCanvasSize then
		self.TotalCanvasSize = newCanvasSize
		local newSize = UDim2.new(0,0,0,self.TotalCanvasSize)
		self.CanvasSizeChangedEvent:Fire(newSize)
		if self.DoTween then
			self.CanvasTween = TweenService:Create(self.Scroller, self.Info, {CanvasSize = newSize})
			self.CanvasTween:Play()
		else
			self.Scroller.CanvasSize = newSize
		end
	end
end

function SmartScroller:SetCanvasBottomOffset(offset : number)
	self.CanvasBottomOffset = offset
	self:CalculateYSize()
end

function SmartScroller:SetExpansionScalar(scalar : number)
	self.ExpansionScalar = scalar
	self:CalculateYSize()
end

function SmartScroller:SetExpansionPolicy(policyType : number)
	assert(policyType == SmartScroller.ExpansionPolicy.Item or 
		policyType == SmartScroller.ExpansionPolicy.Offset or 
		policyType == SmartScroller.ExpansionPolicy.None, 
		"Error in setting expansion policy. Policy passed in is invalid")
	self.ExpansionPolicy = policyType
	self:CalculateYSize()
end

function SmartScroller:SetTween(tween : boolean)
	self.DoTween = tween
	if self.SizeTween then
		self.SizeTween:Cancel()
		self.SizeTween = nil
		self.Scroller.Size = UDim2.new(0,0,0,self.CurrentYSize)
	end
end

function SmartScroller:SetTweenSpeed(newSpeed : number)
	self.TweenSpeed = newSpeed
	self.Info = TweenInfo.new(self.TweenSpeed, self.TweenStyle, self.TweenDirection, 0, false, 0)
end

function SmartScroller:SetEasingDirection(newDir : Enum.EasingDirection)
	self.TweenDirection = newDir
	self.Info = TweenInfo.new(self.TweenSpeed, self.TweenStyle, self.TweenDirection, 0, false, 0)
end

function SmartScroller:SetEasingStyle(newStyle : Enum.EasingStyle)
	self.TweenStyle = newStyle
	self.Info = TweenInfo.new(self.TweenSpeed, self.TweenStyle, self.TweenDirection, 0, false, 0)
end

function SmartScroller:SetPadding(dim : UDim)
	self.Padding = dim
	self.UIListLayout.Padding = dim
end

function SmartScroller:AddPadding(paddingAmount : number)
	self.Padding = self.Padding + UDim.new(0, paddingAmount)
end

function SmartScroller:RemovePadding(paddingAmount : number)
	self.Padding = self.Padding - UDim.new(0, paddingAmount)
end

function SmartScroller:IsA(classname : string)
	return classname == "SmartScroller"
end

function SmartScroller:ClearAllChildren()
	for object : Instance,con : RBXScriptConnection in pairs(self.Items) do
		con:Disconnect()
		object:Destroy()
	end
	self.Items = {}
end

return SmartScroller
