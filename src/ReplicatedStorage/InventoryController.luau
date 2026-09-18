--[[
	InventoryController - клиентский модуль инвентарей и цветов.
	ModuleScript в ReplicatedStorage с именем "InventoryController".
	Используется локальным скриптом SceneTransition
	(src/StarterGui/MainMenuGui/SceneTransition.client.luau).

	Отвечает за: инвентари категорий (одежда, волосы и т.д.), цветовые
	палитры с ColorPicker, текстовые метки экипировки и рандомайзер.
	Снаружи используются InventoryController.init(deps) и .closeAll().
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InventoryController = {}

-- ===================== REMOTE ОБЪЕКТЫ И ШАБЛОНЫ =====================
local GetInventoryItems = ReplicatedStorage:WaitForChild("GetInventoryItems")
local EquipItemEvent = ReplicatedStorage:WaitForChild("EquipItem")
local GetEquippedItems = ReplicatedStorage:WaitForChild("GetEquippedItems") -- RemoteFunction: снимок надетого
local ChangePartColorEvent = ReplicatedStorage:WaitForChild("ChangePartColorEvent")
local GetPlayerSkinColor = ReplicatedStorage:WaitForChild("GetPlayerSkinColor")
local ColorPickerModule = require(ReplicatedStorage:WaitForChild("ColorPicker"))
local ColorPalettes = require(ReplicatedStorage:WaitForChild("ColorPalettes"))
local itemTemplate = ReplicatedStorage:WaitForChild("Templates"):WaitForChild("InventoryItemTemplate")

-- Палитры общие с сервером (рандомайзер спавна) - см. ReplicatedStorage.ColorPalettes
local skinColors = ColorPalettes.skinColors

local rng = Random.new()

-- ===================== СОСТОЯНИЕ =====================
local creationGui = nil
local allFrames = {}                -- множество всех инвентарей и палитр
local currentOpenInventory = nil    -- открытый сейчас инвентарь или палитра
local currentEquipped = {}          -- [категория] = имя надетого предмета
local colorPickers = {}             -- [палитра] = открытый ColorPicker
local colorPalettes = {}            -- список всех цветовых палитр (для closeOtherPalettes)
local populatedInventories = {}     -- инвентари, уже заполненные предметами
local inventoryMapping = {}         -- [фрейм инвентаря] = имя категории
local currentCategoryColors = {
	Eyes = Color3.new(1, 1, 1),
	FacialHair = Color3.new(1, 1, 1),
	Hair = Color3.new(1, 1, 1),
	Race = Color3.new(1, 1, 1),
	Skin = Color3.new(1, 1, 1),
}
local skinColorFrame = nil          -- квадратик предпросмотра цвета кожи
local categoryItemCache = {}        -- кэш предметов для рандомайзера
local equipTextLabels = {}          -- [категория] = TextLabel с названием предмета
local lastEquipClickTime = 0        -- защита от двойного клика (тоггл "надеть-снять" туда-обратно)
local lastRandomTime = 0            -- защита от спама кнопкой рандомайзера
local lastInventoryClickTime = 0    -- защита от двойного клика по кнопкам инвентарей

-- ===================== ЗАКРЫТИЕ ИНВЕНТАРЕЙ =====================
local function closeAllInventories()
	for pal, picker in pairs(colorPickers) do
		picker:Destroy()
		colorPickers[pal] = nil
	end
	for frame in pairs(allFrames) do
		frame.Visible = false
	end
	currentOpenInventory = nil
	print("Все инвентари и палитры закрыты.")
end
InventoryController.closeAll = closeAllInventories

-- ===================== ЗАПОЛНЕНИЕ ИНВЕНТАРЕЙ =====================
local function populateInventory(inventoryFrame, categoryName)
	local scrollingFrame = inventoryFrame:WaitForChild("ScrollingFrame")
	for _, child in ipairs(scrollingFrame:GetChildren()) do
		if child:GetAttribute("Item") == true then
			child:Destroy()
		end
	end

	local items = GetInventoryItems:InvokeServer(categoryName)
	if not items then
		warn("Не удалось загрузить инвентарь '" .. categoryName .. "'")
		return
	end

	for _, itemData in ipairs(items) do
		local itemClone = itemTemplate:Clone()
		itemClone:SetAttribute("Item", true)
		itemClone.Name = itemData.name .. "_Frame"
		local button = itemClone:FindFirstChild("ImageButton")
		if button then
			button.Activated:Connect(function()
				-- Дебаунс: быстрый двойной клик успевает отправить "надеть" и "снять" подряд
				local now = os.clock()
				if now - lastEquipClickTime < 0.25 then return end
				lastEquipClickTime = now

				local equippedName = currentEquipped[categoryName]
				if equippedName == itemData.name then
					EquipItemEvent:FireServer(categoryName, nil)
					print("Снятие: " .. itemData.name .. " из " .. categoryName)
				else
					EquipItemEvent:FireServer(categoryName, itemData.name)
					print("Экипировка: " .. itemData.name .. " из " .. categoryName)
				end
			end)
		end
		itemClone.Parent = scrollingFrame
	end
	populatedInventories[inventoryFrame] = true
end

-- ===================== ЦВЕТОВЫЕ ПАЛИТРЫ =====================
-- Закрывает все палитры, кроме указанной (вместе с их пикерами)
local function closeOtherPalettes(currentPalette)
	for _, pal in ipairs(colorPalettes) do
		if pal.Visible and pal ~= currentPalette then
			if colorPickers[pal] then
				colorPickers[pal]:Destroy()
				colorPickers[pal] = nil
			end
			pal.Visible = false
		end
	end
end

local function openColorPicker(palette, categoryName, parentInventory)
	if currentOpenInventory == palette then
		if colorPickers[palette] then
			colorPickers[palette]:Destroy()
			colorPickers[palette] = nil
		end
		palette.Visible = false
		-- Палитра закрывается, а родительский инвентарь остаётся открытым:
		-- он снова становится текущим окном. Иначе следующий клик по кнопке
		-- категории переоткроет инвентарь вместо того, чтобы его закрыть
		currentOpenInventory = parentInventory or nil
		print("Палитра закрыта: " .. palette.Name)
		return
	end

	closeOtherPalettes(palette)

	if parentInventory then
		parentInventory.Visible = true
	end

	palette.Visible = true
	currentOpenInventory = palette

	local initialColor = currentCategoryColors[categoryName] or Color3.new(1, 1, 1)

	local picker = nil
	local function onColorChanged(newColor)
		currentCategoryColors[categoryName] = newColor
		ChangePartColorEvent:FireServer(categoryName, newColor)
		print("Предпросмотр " .. categoryName .. ": " .. tostring(newColor))
	end

	local function onClosed()
		palette.Visible = false
		-- Accept/Cancel закрывает только палитру, родительский инвентарь
		-- остаётся на экране. Возвращаем ему статус текущего окна, иначе
		-- состояние ("ничего не открыто") расходится с экраном: следующий
		-- клик по кнопке категории печатал "Открыт", а окно не закрывалось,
		-- и закрыть его получалось только со второго раза
		if currentOpenInventory == palette then
			currentOpenInventory = parentInventory or nil
		end
		if colorPickers[palette] == picker then
			colorPickers[palette] = nil
		end
		if categoryName == "Skin" then
			skinColorFrame.BackgroundColor3 = currentCategoryColors.Skin
		end
		print("Пикер закрыт: " .. categoryName)
	end

	picker = ColorPickerModule.new(palette, initialColor, onColorChanged, onClosed)
	colorPickers[palette] = picker
end

local function switchToMainInventory(targetFrame)
	if currentOpenInventory == targetFrame then
		closeAllInventories()
		return
	end

	for pal, picker in pairs(colorPickers) do
		picker:Destroy()
		colorPickers[pal] = nil
	end
	for frame in pairs(allFrames) do
		frame.Visible = false
	end

	targetFrame.Visible = true
	currentOpenInventory = targetFrame
	print("Открыт: " .. targetFrame.Name)

	if not populatedInventories[targetFrame] and inventoryMapping[targetFrame] then
		populateInventory(targetFrame, inventoryMapping[targetFrame])
	end
end

-- ===================== ПОДКЛЮЧЕНИЕ КНОПОК =====================
-- Проходит цепочку дочерних имей от root: путь до элемента читается одной
-- строкой вместо серии WaitForChild, и при переименовании узла GUI правка
-- локализована в одном месте
local function waitForPath(root: Instance, names: {string}): Instance
	local current = root
	for _, name in ipairs(names) do
		current = current:WaitForChild(name)
	end
	return current
end

-- Подключает кнопку, найденную по пути от CreationMenuGui
local function connectMainButton(guiPath, targetFrame)
	local btn = waitForPath(creationGui, guiPath)
	-- Activated: работает и с геймпадом (MouseButton1Click - только мышь/тач)
	btn.Activated:Connect(function()
		-- Дебаунс: второй клик во время InvokeServer внутри populateInventory
		-- успевает закрыть только что открытый инвентарь (тоггл по
		-- currentOpenInventory срабатывает раньше окончания загрузки)
		local now = os.clock()
		if now - lastInventoryClickTime < 0.25 then return end
		lastInventoryClickTime = now
		switchToMainInventory(targetFrame)
	end)
end

-- Подключает кнопку открытия цветовой палитры
local function connectColorButton(guiPath, colorPalette, parentInventory, categoryName)
	local btn = waitForPath(creationGui, guiPath)
	btn.Activated:Connect(function()
		openColorPicker(colorPalette, categoryName, parentInventory)
	end)
end

-- ===================== РАНДОМАЙЗЕР =====================
local function preloadCategories()
	-- ИСПРАВЛЕНО: добавлена "Race" для корректной работы рандомайзера
	local cats = {"Shirt", "Pants", "Extra", "Eyes", "Hair", "FacialHair", "Mouth", "Race"}
	for _, cat in ipairs(cats) do
		categoryItemCache[cat] = GetInventoryItems:InvokeServer(cat)
	end
end

-- ===================== ТЕКСТОВЫЕ МЕТКИ ЭКИПИРОВКИ =====================
local function updateEquipText(category, itemName)
	local label = equipTextLabels[category]
	if not label then return end
	label.Text = itemName or "..."
end

-- ===================== ИНИЦИАЛИЗАЦИЯ =====================
type InitDeps = {
	creationGui: ScreenGui,   -- CreationMenuGui из PlayerGui
}

function InventoryController.init(deps: InitDeps)
	creationGui = deps.creationGui

	local inventoryContainer = creationGui:WaitForChild("InventoryColor")

	local Inventory1Pants = inventoryContainer:WaitForChild("Inventory1Pants")
	local Inventory1Shirt = inventoryContainer:WaitForChild("Inventory1Shirt")
	local Inventory1Extra = inventoryContainer:WaitForChild("Inventory1Extra")
	local Inventory1Mouth = inventoryContainer:WaitForChild("Inventory1Mouth")
	local Inventory2Eyes = inventoryContainer:WaitForChild("Inventory2Eyes")
	local Inventory2FacialHair = inventoryContainer:WaitForChild("Inventory2FacialHair")
	local Inventory2Hair = inventoryContainer:WaitForChild("Inventory2Hair")
	local Inventory2Race = inventoryContainer:WaitForChild("Inventory2Race")

	local ColorSkin = inventoryContainer:WaitForChild("ColorSkin")
	local ColorEyes = inventoryContainer:WaitForChild("ColorEyes")
	local ColorFacialHair = inventoryContainer:WaitForChild("ColorFacialHair")
	local ColorHair = inventoryContainer:WaitForChild("ColorHair")
	local ColorRace = inventoryContainer:WaitForChild("ColorRace")

	colorPalettes = {ColorSkin, ColorEyes, ColorFacialHair, ColorHair, ColorRace}

	-- Регистрируем и скрываем все инвентари и палитры
	for _, frame in ipairs({
		Inventory1Pants, Inventory1Shirt, Inventory1Extra, Inventory1Mouth,
		Inventory2Eyes, Inventory2FacialHair, Inventory2Hair, Inventory2Race,
		ColorSkin, ColorEyes, ColorFacialHair, ColorHair, ColorRace,
		}) do
		allFrames[frame] = true
		frame.Visible = false
	end

	inventoryMapping = {
		[Inventory1Extra] = "Extra",
		[Inventory1Mouth] = "Mouth",
		[Inventory1Pants] = "Pants",
		[Inventory2Race]  = "Race",
		[Inventory1Shirt] = "Shirt",
		[Inventory2Eyes]  = "Eyes",
		[Inventory2FacialHair] = "FacialHair",
		[Inventory2Hair]  = "Hair",
	}

	-- Квадратик предпросмотра цвета кожи
	skinColorFrame = waitForPath(creationGui, {"CustomizeLeft", "Frame", "SkinColor", "Frame", "Text", "Frame"})
	skinColorFrame.BackgroundColor3 = currentCategoryColors.Skin

	-- Запрашиваем у сервера сохранённый цвет кожи (если есть)
	local savedSkin = GetPlayerSkinColor:InvokeServer()
	if savedSkin then
		currentCategoryColors.Skin = savedSkin
		skinColorFrame.BackgroundColor3 = savedSkin
		print("Начальный цвет кожи загружен:", savedSkin)
	else
		print("Цвет кожи ещё не сохранён, используется дефолтный")
	end

	-- Кнопки открытия инвентарей
	connectMainButton({"CustomizeLeft", "Frame", "Pants", "Frame", "Frame", "PantsButton"}, Inventory1Pants)
	connectMainButton({"CustomizeLeft", "Frame", "Race", "Frame", "Frame", "RaceButton"}, Inventory2Race)
	connectMainButton({"CustomizeLeft", "Frame", "Shirt", "Frame", "Frame", "ShirtButton"}, Inventory1Shirt)
	connectMainButton({"CustomizeRight", "Frame", "Extra", "Frame", "Frame", "ExtraButton"}, Inventory1Extra)
	connectMainButton({"CustomizeRight", "Frame", "Eyes", "Frame", "Frame", "EyesButton"}, Inventory2Eyes)
	connectMainButton({"CustomizeRight", "Frame", "FacialHair", "Frame", "Frame", "FacialHairButton"}, Inventory2FacialHair)
	connectMainButton({"CustomizeRight", "Frame", "Hair", "Frame", "Frame", "HairButton"}, Inventory2Hair)
	connectMainButton({"CustomizeRight", "Frame", "Mouth", "Frame", "Frame", "MouthButton"}, Inventory1Mouth)

	-- Кнопка цвета кожи (особый случай: палитра без родительского инвентаря)
	local skinColorButton = waitForPath(creationGui, {"CustomizeLeft", "Frame", "SkinColor", "Frame", "Frame", "SkinColorButton"})
	skinColorButton.Activated:Connect(function()
		if currentOpenInventory == ColorSkin then
			-- Повторный клик закрывает палитру одним нажатием
			if colorPickers[ColorSkin] then
				colorPickers[ColorSkin]:Destroy()
				colorPickers[ColorSkin] = nil
			end
			ColorSkin.Visible = false
			currentOpenInventory = nil
		else
			closeAllInventories()
			openColorPicker(ColorSkin, "Skin", nil)
		end
	end)

	-- Кнопки открытия палитр внутри инвентарей
	connectColorButton({"InventoryColor", "Inventory2Eyes", "Frame", "ColorButton"}, ColorEyes, Inventory2Eyes, "Eyes")
	connectColorButton({"InventoryColor", "Inventory2FacialHair", "Frame", "ColorButton"}, ColorFacialHair, Inventory2FacialHair, "FacialHair")
	connectColorButton({"InventoryColor", "Inventory2Hair", "Frame", "ColorButton"}, ColorHair, Inventory2Hair, "Hair")
	connectColorButton({"InventoryColor", "Inventory2Race", "Frame", "ColorButton"}, ColorRace, Inventory2Race, "Race")

	-- Рандомайзер: предзагружаем категории и подключаем кнопку
	preloadCategories()

	local randomButton = creationGui:WaitForChild("Random"):WaitForChild("Frame"):WaitForChild("RandomButton")
	randomButton.Activated:Connect(function()
		-- Дебаунс: один клик и так шлёт ~12 запросов на сервер
		local now = os.clock()
		if now - lastRandomTime < 0.5 then return end
		lastRandomTime = now

		closeAllInventories()

		-- Обязательные категории (всегда новые предметы)
		local required = {"Shirt", "Pants", "Eyes", "Mouth", "Race"}
		for _, cat in ipairs(required) do
			local items = categoryItemCache[cat]
			if items and #items > 0 then
				local chosen = items[rng:NextInteger(1, #items)]
				EquipItemEvent:FireServer(cat, chosen.name)
			end
		end

		-- Опциональные категории с вероятностями и возможностью снятия
		local optional = {
			{name = "Hair",       chance = 0.85},
			{name = "FacialHair", chance = 0.20},
			{name = "Extra",      chance = 0.20},
		}
		for _, opt in ipairs(optional) do
			local items = categoryItemCache[opt.name]
			if items and #items > 0 then
				if rng:NextNumber() < opt.chance then
					local chosen = items[rng:NextInteger(1, #items)]
					EquipItemEvent:FireServer(opt.name, chosen.name)
				else
					-- Снимаем только когда категория известна и предмет реально не выпал
					EquipItemEvent:FireServer(opt.name, nil)
				end
			end
			-- Пустой кэш (нет предметов/не догрузился): пропускаем, чтобы
			-- не снимать вручную надетый предмет категории
		end

		-- Применяем цвета
		local colorable = {"Eyes", "Hair", "FacialHair", "Race"}
		for _, cat in ipairs(colorable) do
			local col = ColorPalettes.getPleasantColor(rng)
			currentCategoryColors[cat] = col
			ChangePartColorEvent:FireServer(cat, col)
		end

		-- Цвет кожи отдельно (телесная палитра)
		local skinCol = skinColors[rng:NextInteger(1, #skinColors)]
		currentCategoryColors.Skin = skinCol
		ChangePartColorEvent:FireServer("Skin", skinCol)
		skinColorFrame.BackgroundColor3 = skinCol

		print("Рандомайзер выполнен!")
	end)

	-- Текстовые метки экипировки: TextLabel категории лежит по пути
	-- <panel>/<Category>/Frame/Text/Text<Category>
	local leftFrame = waitForPath(creationGui, {"CustomizeLeft", "Frame"})
	local rightFrame = waitForPath(creationGui, {"CustomizeRight", "Frame"})
	local function equipLabel(panel: Instance, category: string): TextLabel
		return waitForPath(panel, {category, "Frame", "Text", "Text" .. category}) :: TextLabel
	end
	equipTextLabels = {
		Race = equipLabel(leftFrame, "Race"),
		Shirt = equipLabel(leftFrame, "Shirt"),
		Pants = equipLabel(leftFrame, "Pants"),
		Eyes = equipLabel(rightFrame, "Eyes"),
		Extra = equipLabel(rightFrame, "Extra"),
		Mouth = equipLabel(rightFrame, "Mouth"),
		FacialHair = equipLabel(rightFrame, "FacialHair"),
		Hair = equipLabel(rightFrame, "Hair"),
	}

	-- Сервер подтверждает экипировку - обновляем метки
	EquipItemEvent.OnClientEvent:Connect(function(data)
		currentEquipped[data.category] = data.item
		updateEquipText(data.category, data.item)
	end)

	-- Синхронизация с сервером: случайный набор выдаётся на спавне, когда клиент
	-- ещё не подключён к EquipItem, поэтому все подтверждения спавна потеряны.
	-- Запрашиваем снимок надетого и выбранных цветов, иначе первый клик по уже
	-- надетому предмету работает "наоборот" (снимает вместо показа надетого).
	local initialEquipped, initialColors = GetEquippedItems:InvokeServer()
	if initialEquipped then
		for category, itemName in pairs(initialEquipped) do
			currentEquipped[category] = itemName
			updateEquipText(category, itemName)
		end
	end
	if initialColors then
		for category, color in pairs(initialColors) do
			currentCategoryColors[category] = color
		end
		if initialColors.Skin then
			skinColorFrame.BackgroundColor3 = initialColors.Skin
		end
	end
end

return InventoryController
