--[[
	ColorPicker - HSV/RGB-пикер цвета для палитр кастомизации.
	ModuleScript в ReplicatedStorage с именем "ColorPicker".

	Используется InventoryController (каждая палитра открывает свой пикер).

	Слайдеры работают на UserInputService.InputChanged/InputEnded, а не на
	цикле while + RenderStepped: значение обновляется только при реальном
	движении указателя, поток не крутится каждый кадр, а освобождение
	кнопки ловится глобально - если отпустить её за пределами слайдера,
	GuiObject.InputEnded не прилетит и перетаскивание "залипнет".

	new(pickerGui, initialColor, onColorChanged, onClosed):
	  onColorChanged(color: Color3) - при любом изменении цвета
	  onClosed()                   - при закрытии (accept или cancel)
]]

local UserInputService = game:GetService("UserInputService")

local ColorPicker = {}
ColorPicker.__index = ColorPicker

type Connections = {RBXScriptConnection}

function ColorPicker.new(pickerGui: Instance, initialColor: Color3,
	onColorChanged: ((Color3) -> ())?, onClosed: (() -> ())?)
	local self = setmetatable({}, ColorPicker)
	self._pickerGui = pickerGui
	self._h, self._s, self._v = initialColor:ToHSV()
	self._initialColor = initialColor
	self._onColorChanged = onColorChanged
	self._onClosed = onClosed
	self._connections = {} :: Connections
	self._isDestroyed = false

	-- Структура палитры
	local cpframe = pickerGui:WaitForChild("color_picker_frame"):WaitForChild("color_picker"):WaitForChild("Frame")
	self._hueBar = cpframe:WaitForChild("hue_bar")
	self._satBar = cpframe:WaitForChild("saturation_bar")
	self._valBar = cpframe:WaitForChild("value_bar")
	self._colorDisplay = cpframe:WaitForChild("color_display")

	local bottomFrame = pickerGui.color_picker_frame:WaitForChild("bottom_frame")
	self._acceptBtn = bottomFrame:WaitForChild("accept_button")
	self._cancelBtn = bottomFrame:WaitForChild("cancel_button")

	local colorInput = pickerGui:WaitForChild("color_input"):WaitForChild("color_input")
	local hsvFrame = colorInput:WaitForChild("hsv_frame")
	local rgbFrame = colorInput:WaitForChild("rgb_frame")
	self._hsvInputs = {
		h = hsvFrame:WaitForChild("h"):WaitForChild("input"),
		s = hsvFrame:WaitForChild("s"):WaitForChild("input"),
		v = hsvFrame:WaitForChild("v"):WaitForChild("input"),
	}
	self._rgbInputs = {
		r = rgbFrame:WaitForChild("r"):WaitForChild("input"),
		g = rgbFrame:WaitForChild("g"):WaitForChild("input"),
		b = rgbFrame:WaitForChild("b"):WaitForChild("input"),
	}

	self:UpdateUI()
	self:_bindEvents()
	return self
end

function ColorPicker:UpdateUI()
	local color = Color3.fromHSV(self._h, self._s, self._v)
	self._colorDisplay.BackgroundColor3 = color

	self._hueBar.cursor.Position = UDim2.new(self._h, 0, 0.5, 0)
	self._satBar.cursor.Position = UDim2.new(self._s, 0, 0.5, 0)
	self._valBar.cursor.Position = UDim2.new(self._v, 0, 0.5, 0)

	self._satBar.UIGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromHSV(self._h, 0, self._v)),
		ColorSequenceKeypoint.new(1, Color3.fromHSV(self._h, 1, self._v))
	})
	self._valBar.UIGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromHSV(self._h, self._s, 0)),
		ColorSequenceKeypoint.new(1, Color3.fromHSV(self._h, self._s, 1))
	})

	self._hsvInputs.h.Text = string.format("%.2f", self._h)
	self._hsvInputs.s.Text = string.format("%.2f", self._s)
	self._hsvInputs.v.Text = string.format("%.2f", self._v)
	local r, g, b = math.floor(color.R*255), math.floor(color.G*255), math.floor(color.B*255)
	self._rgbInputs.r.Text = r
	self._rgbInputs.g.Text = g
	self._rgbInputs.b.Text = b
end

function ColorPicker:_fireColorChanged()
	if self._onColorChanged then
		local color = Color3.fromHSV(self._h, self._s, self._v)
		self._onColorChanged(color)
	end
end

-- Пересчитать координату экрана в компонент HSV (0..1) и применить
function ColorPicker:_applySliderValue(slider: GuiObject, component: string, screenX: number)
	if slider.AbsoluteSize.X <= 0 then return end
	local relX = math.clamp(screenX - slider.AbsolutePosition.X, 0, slider.AbsoluteSize.X)
	self["_"..component] = relX / slider.AbsoluteSize.X
	self:UpdateUI()
	self:_fireColorChanged()
end

function ColorPicker:_bindEvents()
	-- Активное перетаскивание: какой слайдер и какой компонент HSV
	local activeSlider: GuiObject? = nil
	local activeComponent: string? = nil

	local function isPress(input: InputObject): boolean
		return input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
	end

	-- Слайдеры: значение по нажатию, дальше - по движению указателя
	local function onSliderInput(slider: GuiObject, component: string)
		local conn = slider.InputBegan:Connect(function(input)
			if isPress(input) and not self._isDestroyed then
				activeSlider = slider
				activeComponent = component
				self:_applySliderValue(slider, component, input.Position.X)
			end
		end)
		table.insert(self._connections, conn)
	end
	onSliderInput(self._hueBar, "h")
	onSliderInput(self._satBar, "s")
	onSliderInput(self._valBar, "v")

	local connMove = UserInputService.InputChanged:Connect(function(input)
		if not activeSlider or not activeComponent then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then
			self:_applySliderValue(activeSlider, activeComponent, input.Position.X)
		end
	end)
	table.insert(self._connections, connMove)

	-- Отпускание слушаем глобально: GuiObject.InputEnded не придёт, если
	-- кнопка отпущена за пределами слайдера
	local connRelease = UserInputService.InputEnded:Connect(function(input)
		if isPress(input) then
			activeSlider = nil
			activeComponent = nil
		end
	end)
	table.insert(self._connections, connRelease)

	-- Ввод HSV
	for component, input in pairs(self._hsvInputs) do
		local conn = input.FocusLost:Connect(function()
			local val = tonumber(input.Text)
			if val then
				self["_"..component] = math.clamp(val, 0, 1)
				self:UpdateUI()
				self:_fireColorChanged()
			else
				self:UpdateUI() -- восстановить отображение
			end
		end)
		table.insert(self._connections, conn)
	end

	-- Ввод RGB
	local function rgbChanged()
		local r = tonumber(self._rgbInputs.r.Text)
		local g = tonumber(self._rgbInputs.g.Text)
		local b = tonumber(self._rgbInputs.b.Text)
		if r and g and b then
			local color = Color3.fromRGB(math.clamp(r,0,255), math.clamp(g,0,255), math.clamp(b,0,255))
			self._h, self._s, self._v = color:ToHSV()
			self:UpdateUI()
			self:_fireColorChanged()
		end
	end
	for _, input in pairs(self._rgbInputs) do
		local conn = input.FocusLost:Connect(rgbChanged)
		table.insert(self._connections, conn)
	end

	-- Кнопка Accept: просто закрываем
	local connAccept = self._acceptBtn.Activated:Connect(function()
		self:Destroy()
	end)
	table.insert(self._connections, connAccept)

	-- Кнопка Cancel: возвращаем исходный цвет и закрываем
	local connCancel = self._cancelBtn.Activated:Connect(function()
		if self._onColorChanged then
			self._onColorChanged(self._initialColor)
		end
		self:Destroy()
	end)
	table.insert(self._connections, connCancel)
end

function ColorPicker:Destroy()
	if self._isDestroyed then return end
	self._isDestroyed = true

	for _, conn in ipairs(self._connections) do
		conn:Disconnect()
	end
	self._connections = nil

	if self._onClosed then
		self._onClosed()
	end
	-- сам ScreenGui не удаляем, он скрывается извне
end

return ColorPicker
