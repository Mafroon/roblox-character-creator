--[[
	SlotHover - hover-эффект слотов персонажей (Slot1-Slot3).
	LocalScript внутри MainMenuGui.MainContainer.

	Скрипт обходит слоты и вешает тот же эффект (подсветка обводки + смена текста
	плейсхолдера). И спец-поведение для Slot3 ("Buy Extra Slot").
]]

local DEFAULT_COLOR = Color3.fromRGB(206, 167, 62)
local HOVER_COLOR = Color3.fromRGB(255, 210, 80)
local HOVER_COLOR_BUY = Color3.fromRGB(255, 150, 90)
local HOVER_THICKNESS = 3
local HOVER_TEXT = "Create New Character"
local HOVER_TEXT_BUY = "Buy Extra Slot"

local function applySlotHover(btn: GuiButton)
	local stroke = btn:FindFirstChild("BorderStroke")
	-- Запоминаем реальные параметры обводки: иначе MouseLeave
	-- затирает их на хардкод (толщина 1, прозрачность 0.3)
	local defaultColor = stroke and stroke.Color or DEFAULT_COLOR
	local defaultThickness = stroke and stroke.Thickness or 1
	local defaultTransparency = stroke and stroke.Transparency or 0.3

	local isBuySlot = (btn.Name == "Slot3")
	local hoverColor = isBuySlot and HOVER_COLOR_BUY or HOVER_COLOR

	local label = btn:FindFirstChild("PlaceholderLabel")
	local defaultText = label and label.Text or "?"
	local hoverText = isBuySlot and HOVER_TEXT_BUY or HOVER_TEXT

	btn.MouseEnter:Connect(function()
		if stroke then
			stroke.Color = hoverColor
			stroke.Thickness = HOVER_THICKNESS
			stroke.Transparency = 0
		end
		if label then
			label.Text = hoverText
		end
	end)

	btn.MouseLeave:Connect(function()
		if stroke then
			stroke.Color = defaultColor
			stroke.Thickness = defaultThickness
			stroke.Transparency = defaultTransparency
		end
		if label then
			label.Text = defaultText
		end
	end)
end

for i = 1, 3 do
	local slot = script.Parent:FindFirstChild("Slot" .. i)
	if slot and slot:IsA("GuiButton") then
		applySlotHover(slot)
	else
		warn("SlotHover: Slot" .. i .. " не найден или не GuiButton")
	end
end
