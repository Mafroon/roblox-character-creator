--[[
	ElementMenu - клиентский модуль инфо-фреймов стихий.
	ModuleScript: поместить в ReplicatedStorage с именем "ElementMenu".
	Используется локальным скриптом SceneTransition (см. SceneTransition.txt).

	Отвечает за информационные фреймы стихий (Fire, Water, Earth, Air,
	Light, Gloom) в ElementMenuGui: показ/скрытие по клику на кнопку
	стихии и принудительное закрытие при переходах.

	Единственный обработчик кликов по кнопкам стихий: HoverBorder2 больше
	не подключает эти кнопки сам, а подписывается на готовое решение через
	ElementMenu.onElementToggled (иначе у двух скриптов расходились фильтры
	кликов и "Ваш выбор" оставался пустым).
]]

local TweenService = game:GetService("TweenService")

local ElementMenu = {}

-- Позиции анимации инфо-фреймов
local INFO_HIDE_POS = UDim2.new(1.1, 0, 0.4, 0)
local INFO_SHOW_POS = UDim2.new(0.6, 0, 0.4, 0)

-- Список стихий: имена фрейма в InfoFrame и кнопки в ElementMenuGui
local ELEMENTS = {
	{ infoFrame = "FireInfoFrame",  button = "FireButton" },
	{ infoFrame = "WaterInfoFrame", button = "WaterButton" },
	{ infoFrame = "EarthInfoFrame", button = "EarthButton" },
	{ infoFrame = "AirInfoFrame",   button = "AirButton" },
	{ infoFrame = "LightInfoFrame", button = "LightButton" },
	{ infoFrame = "GloomInfoFrame", button = "GloomButton" },
}

local currentInfoFrame = nil    -- какой фрейм открыт сейчас
local isInfoAnimating = false
-- Блокировка кликов на время переходов: SceneEffects.hideElementMenu выключает
-- ElementMenuGui только через 0.8с, и без этого флага клик в этом окне
-- успевает переоткрыть инфо-фрейм, который переход только что закрыл
local inputEnabled = true

-- ============ ЕДИНСТВЕННЫЙ ОБРАБОТЧИК КЛИКОВ ПО КНОПКАМ СТИХИЙ ============
-- Кнопки стихий обслуживает ТОЛЬКО этот модуль: он решает, принят ли клик
-- (переходы, анимация инфо-фрейма, анти-спам 0.3с), и открывает инфо-фрейм.
-- HoverBorder2 своих обработчиков на эти кнопки больше не вешает - он
-- подписывается через onElementToggled и получает готовое решение, поэтому
-- "Ваш выбор" физически не может разойтись с описанием стихии.
local CLICK_DEBOUNCE = 0.3        -- сек между принимаемыми кликами
local lastAcceptedClickTime = 0
local toggleListeners = {}        -- подписчики (HoverBorder2) на решение о выборе

-- Подписка на решение о выборе: listener(button, isSelected)
function ElementMenu.onElementToggled(listener)
	table.insert(toggleListeners, listener)
end

-- Клик разрешён, но не расходует дебаунс (для PlayButton во время переходов)
function ElementMenu.isClickAllowed()
	return inputEnabled and not isInfoAnimating
end

-- Внутренний гейт: решать, принимать ли клик по кнопке стихии
local function acquireClick()
	local now = os.clock()
	if not inputEnabled then
		warn("ElementMenu: клик отклонён - идёт переход (inputEnabled=false)")
		return false
	end
	if isInfoAnimating then
		warn("ElementMenu: клик отклонён - инфо-фрейм ещё анимируется")
		return false
	end
	if now - lastAcceptedClickTime < CLICK_DEBOUNCE then
		return false -- анти-спам: слишком быстро, молча игнорируем
	end
	lastAcceptedClickTime = now
	return true
end

-- ===================== АНИМАЦИЯ ИНФО-ФРЕЙМОВ =====================
-- ВАЖНО: TweenBase.Completed срабатывает и при отмене твина (PlaybackState.Cancelled),
-- например когда переход прерывает анимацию через closeOpenInfoFrame. Поэтому
-- состояние фиксируем только при реальном завершении, а при отмене лишь
-- снимаем флаг анимации, чтобы кнопки стихий не "залипли".

local function closeInfoFrame(infoFrame, callback)
	local tween = TweenService:Create(infoFrame,
		TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Position = INFO_HIDE_POS})
	tween:Play()
	tween.Completed:Connect(function(playbackState)
		if playbackState == Enum.PlaybackState.Completed then
			infoFrame.Visible = false
			if callback then callback() end
		else
			isInfoAnimating = false
		end
	end)
end

local function showInfoFrame(infoFrame, callback)
	infoFrame.Visible = true
	infoFrame.Position = INFO_HIDE_POS
	-- Фиксируем сразу, а не в Completed: переход может начаться посреди
	-- анимации, и closeOpenInfoFrame должен найти фрейм, чтобы его закрыть
	currentInfoFrame = infoFrame
	local tween = TweenService:Create(infoFrame,
		TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Position = INFO_SHOW_POS})
	tween:Play()
	tween.Completed:Connect(function(playbackState)
		if playbackState == Enum.PlaybackState.Completed then
			if callback then callback() end
		else
			-- Фрейм прерван переходом (closeOpenInfoFrame уже сбросил
			-- currentInfoFrame): снимаем только флаг анимации
			isInfoAnimating = false
		end
	end)
end

-- Обработчик нажатия на кнопку стихии (открыть/закрыть/переключить)
local function onElementButtonClicked(button, infoFrame)
	if not acquireClick() then return end

	local selecting
	if currentInfoFrame == infoFrame then
		selecting = false
		isInfoAnimating = true
		closeInfoFrame(infoFrame, function()
			currentInfoFrame = nil
			isInfoAnimating = false
		end)
	else
		selecting = true
		isInfoAnimating = true
		local previous = currentInfoFrame
		local function openNew()
			showInfoFrame(infoFrame, function()
				-- currentInfoFrame уже выставлен в showInfoFrame до анимации
				isInfoAnimating = false
			end)
		end
		if previous then
			closeInfoFrame(previous, openNew)
		else
			openNew()
		end
	end

	-- Одно решение на всех: и инфо-фрейм, и подписчики (подсветка +
	-- "Ваш выбор" в HoverBorder2) живут по нему
	print("ElementMenu: " .. infoFrame.Name .. " -> " .. (selecting and "выбрана" or "снята"))
	for _, listener in ipairs(toggleListeners) do
		listener(button, selecting)
	end
end

-- ===================== ИНИЦИАЛИЗАЦИЯ =====================
-- init(deps): deps = {
--   elementMenu     = ElementMenuGui,
--   yourChoiceFrame = элемент YourChoiceFrame (изначально прячется),
-- }
function ElementMenu.init(deps)
	local elementMenu = deps.elementMenu

	-- YourChoiceFrame изначально спрятан снизу
	local yourChoiceFrame = deps.yourChoiceFrame
	yourChoiceFrame.Visible = false
	yourChoiceFrame.Position = UDim2.new(0.5, 0, 1.1, 0)

	local infoFrameContainer = elementMenu:WaitForChild("InfoFrame")

	-- Рекурсивный поиск кнопки по имени внутри elementMenu
	local function findButton(parent, name)
		for _, child in ipairs(parent:GetChildren()) do
			if child.Name == name and child:IsA("GuiButton") then
				return child
			end
			local found = findButton(child, name)
			if found then return found end
		end
		return nil
	end

	-- Скрываем все инфо-фреймы и подключаем кнопки стихий
	for _, element in ipairs(ELEMENTS) do
		local infoFrame = infoFrameContainer:WaitForChild(element.infoFrame)
		infoFrame.Visible = false
		infoFrame.Position = INFO_HIDE_POS

		local button = findButton(elementMenu, element.button)
		if not button then
			warn("Кнопка " .. element.button .. " не найдена в ElementMenuGui!")
		else
			-- Единственная точка клика по кнопке стихии; Activated работает
			-- и с геймпадом (HoverBorder2 получает решение через onElementToggled)
			button.Activated:Connect(function()
				onElementButtonClicked(button, infoFrame)
			end)
		end
	end
end

-- Включает/выключает обработку кликов по кнопкам стихий.
-- SceneTransition выключает на время переходов (пока панели меню стихий
-- уезжают, GUI ещё активен ~0.8с) и включает при возврате в меню стихий.
function ElementMenu.setInputEnabled(enabled)
	inputEnabled = enabled
end

-- Принудительно убрать открытый инфо-фрейм (если есть). Вызывается при переходах.
-- duration - длительность анимации, hideOnComplete - скрыть фрейм после анимации.
-- Возвращает запущенный Tween или nil, если открытого фрейма не было.
function ElementMenu.closeOpenInfoFrame(duration, hideOnComplete)
	if not currentInfoFrame then
		return nil
	end
	local frameToClose = currentInfoFrame
	currentInfoFrame = nil                -- сбрасываем ссылку сразу
	local closeTween = TweenService:Create(frameToClose,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Position = INFO_HIDE_POS})
	closeTween:Play()
	if hideOnComplete then
		closeTween.Completed:Connect(function(playbackState)
			-- Completed срабатывает и при отмене: повторное открытие фрейма
			-- отменило бы этот твин, и прятать его в этом случае нельзя
			if playbackState == Enum.PlaybackState.Completed then
				frameToClose.Visible = false
			end
		end)
	end
	return closeTween
end

return ElementMenu
