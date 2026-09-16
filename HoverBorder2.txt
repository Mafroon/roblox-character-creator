--[[
	LocalScript внутри ElementMenuGui (HoverBorder2).

	ВАЖНО: это не устаревшая альтернатива HoverBorder, а НЕОБХОДИМЫЙ скрипт -
	единственный, кто передаёт выбор стихии дальше: PlayButton -> ElementChosenEvent.
	Без него финальный переход (SceneTransition) недостижим - не удалять.

	Требует в ReplicatedStorage ДВА BindableEvent (не RemoteEvent!):
	  - ElementChosenEvent       - выбор стихии отсюда в SceneTransition
	  - ResetElementChoiceEvent  - сброс выбора из SceneTransition обратно сюда
	У RemoteEvent нет ни .Event, ни :Fire(), код с RemoteEvent упал бы при старте.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local elementMenu = playerGui:WaitForChild("ElementMenuGui")

-- Модуль ElementMenu обслуживает инфо-фреймы тех же кнопок стихий.
-- Берём у него общий гейт кликов: если этот скрипт и модуль фильтруют клики
-- по отдельности, при спаме "Ваш выбор" и описание стихии разъезжаются
-- (видно описание одной стихии, а выбор - другой)
local ElementMenuModule = require(ReplicatedStorage:WaitForChild("ElementMenu"))

if not ElementMenuModule.onElementToggled or not ElementMenuModule.isClickAllowed then
	warn("HoverBorder2: модуль ElementMenu в ReplicatedStorage устарел (нет onElementToggled/isClickAllowed). "
		.. "Замените его тело содержимым ElementMenu.txt - без этого выбор стихии и кнопка Play не работают!")
end

local function brightenColor(color: Color3, factor: number): Color3
	local h, s, v = color:ToHSV()
	v = math.clamp(v + factor, 0, 1)
	return Color3.fromHSV(h, s, v)
end

-- Конфигурация стихий: имя кнопки > { отображаемое имя, цвет }
local ELEMENT_CONFIG = {
	FireButton  = { Name = "Fire",  Color = Color3.fromRGB(236, 124, 27) },
	WaterButton = { Name = "Water", Color = Color3.fromRGB(72, 165, 236) },
	EarthButton = { Name = "Earth", Color = Color3.fromRGB(110, 191, 66) },
	AirButton   = { Name = "Air",   Color = Color3.fromRGB(164, 188, 195) },
	LightButton = { Name = "Light", Color = Color3.fromRGB(213, 169, 109) },
	GloomButton = { Name = "Gloom", Color = Color3.fromRGB(157, 136, 117) },
}

-- Ищем TextLabel, куда будем выводить название стихии
local yourChoiceLabel = nil
local yourChoiceFrame = elementMenu:FindFirstChild("YourChoiceFrame", true)

local playButton = nil
local buttonContainer = elementMenu:FindFirstChild("ButtonContainer")
if buttonContainer then
	playButton = buttonContainer:FindFirstChild("PlayButton")
end

if yourChoiceFrame then
	yourChoiceLabel = yourChoiceFrame:FindFirstChild("Element")
end

-- ===== ЛОГИКА ПОДСВЕТКИ КНОПОК (без изменений в основной части) =====
local buttonHighlights = {}

local function setupElementButton(button: GuiButton)
	if buttonHighlights[button] then
		return buttonHighlights[button]
	end

	local stroke = button:FindFirstChildOfClass("UIStroke")
	if not stroke then
		buttonHighlights[button] = false
		return nil
	end

	local originalColor = stroke.Color
	local originalThickness = stroke.Thickness
	local originalTransparency = stroke.Transparency
	local hoverThickness = math.min(originalThickness + 2, 10)
	local hoverColor = brightenColor(originalColor, 0.2)

	button.MouseEnter:Connect(function()
		if button.Selected then return end
		stroke.Color = hoverColor
		stroke.Thickness = hoverThickness
		stroke.Transparency = 0
	end)

	button.MouseLeave:Connect(function()
		if button.Selected then return end
		stroke.Color = originalColor
		stroke.Thickness = originalThickness
		stroke.Transparency = originalTransparency
	end)

	local function applySelectedHighlight()
		stroke.Color = hoverColor
		stroke.Thickness = hoverThickness
		stroke.Transparency = 0
	end

	local function clearSelectedHighlight()
		stroke.Color = originalColor
		stroke.Thickness = originalThickness
		stroke.Transparency = originalTransparency
	end

	local highlightFunctions = {
		select = applySelectedHighlight,
		deselect = clearSelectedHighlight
	}
	buttonHighlights[button] = highlightFunctions
	return highlightFunctions
end

local selectedButton: GuiButton? = nil

-- Обновление текстового поля при выборе/сбросе
local function updateChoiceLabel(button: GuiButton?)
	if not yourChoiceLabel then return end

	if button then
		local config = ELEMENT_CONFIG[button.Name]
		if config then
			yourChoiceLabel.Text = config.Name
			yourChoiceLabel.TextColor3 = config.Color
			yourChoiceLabel.Visible = true
			if playButton then
				playButton.BackgroundTransparency = 0.3
			end
		else
			yourChoiceLabel.Visible = false
			if playButton then
				playButton.BackgroundTransparency = 1
			end
		end
	else
		yourChoiceLabel.Text = ""
		yourChoiceLabel.Visible = false
		if playButton then
			playButton.BackgroundTransparency = 1
		end
	end
end

-- ===== ВЫБОР СТИХИЙ =====
-- Кнопки стихий подключает модуль ElementMenu (он же открывает инфо-фреймы).
-- Сюда приходит готовое решение: (кнопка, выбрана/снята) - и подсветка, и
-- "Ваш выбор", и описание стихии живут по одному решению. Раньше у этого
-- скрипта был собственный обработчик с отдельным фильтром кликов, и из-за
-- расхождения фильтров выбор мог теряться молча.
if ElementMenuModule.onElementToggled then
	ElementMenuModule.onElementToggled(function(button, isSelected)
		if isSelected then
			if selectedButton and selectedButton ~= button and buttonHighlights[selectedButton] then
				buttonHighlights[selectedButton].deselect()
			end
			local highlight = setupElementButton(button)
			if highlight then
				highlight.select()
				selectedButton = button
			end
		else
			if selectedButton and buttonHighlights[selectedButton] then
				buttonHighlights[selectedButton].deselect()
			end
			selectedButton = nil
		end
		updateChoiceLabel(isSelected and button or nil)
	end)
end

local function deselectAllButtons()
	if selectedButton then
		local highlight = buttonHighlights[selectedButton]
		if highlight then
			highlight.deselect()
			-- GuiButton.Selected не влияет на Custom-кнопки, поэтому не трогаем
		end
		selectedButton = nil
		updateChoiceLabel(nil)
	end
end

-- BindableEvent (клиент->клиент): у RemoteEvent нет .Event и :Fire()
-- (ReplicatedStorage объявлен в начале скрипта)
local resetChoiceEvent = ReplicatedStorage:WaitForChild("ResetElementChoiceEvent")
resetChoiceEvent.Event:Connect(deselectAllButtons)

-- ===== СКАНИРОВАНИЕ =====
if elementMenu then
	local function scan(parent: Instance)
		for _, child in ipairs(parent:GetChildren()) do
			-- Только hover-подсветка: сами клики подключает ElementMenu
			if child:IsA("GuiButton") and ELEMENT_CONFIG[child.Name] then
				setupElementButton(child)
			end
			scan(child)
		end
	end
	scan(elementMenu)

	-- Кнопка "Назад"
	local backButton = elementMenu:FindFirstChild("BackButton", true)
	if backButton and backButton:IsA("GuiButton") then
		backButton.Activated:Connect(deselectAllButtons)
	else
		warn("BackButton не найден")
	end

	-- Инициализация состояния метки (скрыта, пока ничего не выбрано)
	updateChoiceLabel(nil)

	print("Hover-эффекты, выбор стихий и отображение названия работают.")
else
	warn("ElementMenuGui не найден")
end

-- ===============================
-- Обработка нажатия PlayButton
-- ===============================
-- BindableEvent (клиент->клиент): у RemoteEvent нет :Fire()
local chosenEvent = ReplicatedStorage:WaitForChild("ElementChosenEvent")

if playButton then
	playButton.Activated:Connect(function()
		-- На время переходов и анимаций инфо-фреймов Play заблокирован
		if not ElementMenuModule.isClickAllowed() then return end
		if selectedButton then
			local config = ELEMENT_CONFIG[selectedButton.Name]
			if config then
				-- Отправляем имя стихии в первый скрипт
				chosenEvent:Fire(config.Name)
			else
				warn("Не удалось определить конфигурацию для кнопки " .. selectedButton.Name)
			end
		else
			-- Ничего не выбрано – можно добавить звук или анимацию "ошибки", если нужно
			print("Стихия не выбрана, переход заблокирован.")
		end
	end)
else
	warn("PlayButton не найден в ElementMenuGui.ButtonContainer")
end