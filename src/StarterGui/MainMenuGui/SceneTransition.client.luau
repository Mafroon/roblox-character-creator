--[[
	Главное меню и редактор персонажа (Client-Side LocalScript)
	Поместить в StarterGui (внутрь MainMenuGui).

	Оркестратор: ждёт StartGameEvent от загрузочного экрана, инициализирует
	модули, подключает кнопки и управляет переходами между экранами
	(меню - редактор - стихии - финальный полёт).

	Требует три ModuleScript в ReplicatedStorage (имена должны совпадать):
	  - SceneEffects          - анимации переходов и камера
	  - InventoryController   - инвентари и цвета
	  - ElementMenu           - инфо-фреймы стихий
]]

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

-- Ждём сигнал от загрузочного экрана (StartGameEvent должен быть BindableEvent в ReplicatedStorage)
local startGameEvent = ReplicatedStorage:WaitForChild("StartGameEvent")
startGameEvent.Event:Wait()

local player = Players.LocalPlayer
-- Ждём, пока сервер создаст StringValue (при спавне персонажа)
local genderValue = player:WaitForChild("PlayerGender", 10)  -- 10 сек таймаут
local playerGui = player:WaitForChild("PlayerGui")
local mainMenu = playerGui:WaitForChild("MainMenuGui")
local creationGui = playerGui:WaitForChild("CreationMenuGui")

mainMenu.Enabled = true
-- CreationMenuGui включаем только после инициализации модулей и скрытия
-- панелей (ниже): InventoryController.init делает серию InvokeServer-запросов,
-- и если включить GUI сейчас, всё это время игрок видит редактор целиком
-- (мерцание интерфейса после кнопки Continue)
creationGui.Enabled = false

-- ===================== МОДУЛИ =====================
local SceneEffects = require(ReplicatedStorage:WaitForChild("SceneEffects"))
local InventoryController = require(ReplicatedStorage:WaitForChild("InventoryController"))
local ElementMenu = require(ReplicatedStorage:WaitForChild("ElementMenu"))

-- ===================== REMOTE ОБЪЕКТЫ =====================
-- ElementChosenEvent и ResetElementChoiceEvent - BindableEvent (клиент->клиент,
-- обмен с HoverBorder2): у RemoteEvent нет ни .Event, ни :Fire()
local ElementChosenEvent = ReplicatedStorage:WaitForChild("ElementChosenEvent")

-- ===================== ОСНОВНЫЕ ЭЛЕМЕНТЫ ИНТЕРФЕЙСА =====================
local screenGui = script.Parent
local mainContainer = screenGui:WaitForChild("MainContainer")
local slot1 = mainContainer:WaitForChild("Slot1")
local slot2 = mainContainer:WaitForChild("Slot2")

local buttonContainer = creationGui:WaitForChild("ButtonContainer")
local backBtn = buttonContainer:WaitForChild("BackButton")
local nextBtn = buttonContainer:WaitForChild("NextButton")

local customizeLeft = creationGui:WaitForChild("CustomizeLeft")
local customizeRight = creationGui:WaitForChild("CustomizeRight")
local customizeText = creationGui:WaitForChild("CustomizeText")
local leftRight = creationGui:WaitForChild("LeftRight")
local randomFrame = creationGui:WaitForChild("Random")

local backgroundOverlay = screenGui:WaitForChild("BackgroundOverlay")
local bgLeft = backgroundOverlay:WaitForChild("BackgroundLeft")
local bgRight = backgroundOverlay:WaitForChild("BackgroundRight")

local bgLeftOriginalPos = UDim2.new(0.25, 0, 0.5, 0)
local bgRightOriginalPos = UDim2.new(0.75, 0, 0.5, 0)

local elementMenu = playerGui:WaitForChild("ElementMenuGui")
local elementButtonContainer = elementMenu:WaitForChild("ButtonContainer")
local elementBackButton = elementButtonContainer:WaitForChild("BackButton")

-- ===================== СОСТОЯНИЕ =====================
local isTransitioning = false
local originalMainPos: UDim2 = mainContainer.Position
-- База камеры должна совпадать со стартовой позицией из CameraLockScript (0, 4, 0),
-- иначе первый переход даёт рывок камеры по высоте
local cameraBasePos: Vector3 = Vector3.new(0, 4, 0)

-- ===================== ИНИЦИАЛИЗАЦИЯ МОДУЛЕЙ =====================
ElementMenu.init({
	elementMenu = elementMenu,
	yourChoiceFrame = elementMenu:WaitForChild("YourChoiceFrame"),
})
InventoryController.init({ creationGui = creationGui })
SceneEffects.init({
	buttonContainer = buttonContainer,
	customizeLeft = customizeLeft,
	customizeRight = customizeRight,
	customizeText = customizeText,
	leftRight = leftRight,
	randomFrame = randomFrame,
	elementMenu = elementMenu,
	elementButtonContainer = elementButtonContainer,
	elementBackFrameUp = elementMenu:WaitForChild("BackFrameUp"),
	elementBackFrameDown = elementMenu:WaitForChild("BackFrameDown"),
	elementBackFrame = elementMenu:WaitForChild("BackFrame"),
	yourChoiceFrame = elementMenu:WaitForChild("YourChoiceFrame"),
	bgLeft = bgLeft,
	bgRight = bgRight,
	bgLeftOriginalPos = bgLeftOriginalPos,
	bgRightOriginalPos = bgRightOriginalPos,
})

-- Изначально скрываем элементы редактора
buttonContainer.Visible = false
customizeLeft.Visible = false
customizeRight.Visible = false
customizeText.Visible = false
leftRight.Visible = false
randomFrame.Visible = false
elementMenu.Enabled = false
creationGui.Enabled = true

-- ===================== СМЕНА ПОЛА =====================
local changeGenderEvent = ReplicatedStorage:WaitForChild("ChangeGenderEvent")

local genderFrame = customizeLeft:WaitForChild("Frame"):WaitForChild("Gender")

local ACTIVE_COLOR = Color3.fromRGB(180, 180, 180)
local MALE_INACTIVE_COLOR = Color3.fromRGB(62, 127, 206)
local FEMALE_INACTIVE_COLOR = Color3.fromRGB(194, 124, 206)

local maleButton = genderFrame:WaitForChild("Frame"):WaitForChild("MaleButton")
local femaleButton = genderFrame:WaitForChild("Frame"):WaitForChild("FemaleButton")

local function updateGenderButtons(selectedGender: string)
	if selectedGender == "male" then
		maleButton.BackgroundColor3 = ACTIVE_COLOR
		femaleButton.BackgroundColor3 = FEMALE_INACTIVE_COLOR
	elseif selectedGender == "female" then
		maleButton.BackgroundColor3 = MALE_INACTIVE_COLOR
		femaleButton.BackgroundColor3 = ACTIVE_COLOR
	end
end

-- Первичная подсветка и слежение из StringValue.
-- genderValue может быть nil (таймаут WaitForChild) — тогда просто работаем без автоподсветки
if genderValue then
	updateGenderButtons(genderValue.Value)
	-- Слушаем изменения пола (если он меняется не только по кнопке, но и с сервера)
	genderValue.Changed:Connect(function(newValue)
		updateGenderButtons(newValue)
	end)
else
	warn("PlayerGender не пришёл за 10 сек - подсветка пола с сервера отключена")
end

-- Запрос смены пола на сервер
local function applyGender(gender: string)
	if gender == "male" or gender == "female" then
		changeGenderEvent:FireServer(gender)
		-- Мгновенно подсвечиваем кнопку для отзывчивости интерфейса
		updateGenderButtons(gender)
		print("Запрос на смену пола отправлен: " .. gender)
	else
		warn("Неизвестный пол: " .. tostring(gender))
	end
end

-- Activated вместо MouseButton1Click: работает и с геймпадом/тачем
maleButton.Activated:Connect(function() applyGender("male") end)
femaleButton.Activated:Connect(function() applyGender("female") end)

-- ===================== СБОЙ ТЕЛЕПОРТАЦИИ =====================
-- Финальный переход прячет все меню ещё до запроса телепортации. Если
-- TeleportAsync падает (сервер в Teleport.server.luau только предупреждает), игрок
-- остаётся в этом плейсе без интерфейса. TeleportInitFailed приходит и на
-- клиент — восстанавливаем меню стихий, фон и камеру.
-- restoreAfterTeleportFailure назначается в transitionToFinal.
local restoreAfterTeleportFailure = nil

TeleportService.TeleportInitFailed:Connect(function(_player, teleportResult, errorMessage)
	warn("Телепортация не удалась: " .. tostring(teleportResult) .. " (" .. tostring(errorMessage) .. ")")
	if restoreAfterTeleportFailure then
		restoreAfterTeleportFailure()
	end
end)

-- ===================== ПЕРЕХОДЫ =====================

-- Возврат из редактора в главное меню (кнопка Back)
local function returnToMenu()
	if isTransitioning then return end
	InventoryController.closeAll()
	isTransitioning = true

	TweenService:Create(mainContainer, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Position = originalMainPos}):Play()

	SceneEffects.hideCreationUI()

	-- Камера возвращается к прямому виду; разблокируем переход только после её окончания
	local tweenCam = SceneEffects.tweenCameraYaw(cameraBasePos, -math.pi/2, 0, 1.0)
	if not tweenCam then
		isTransitioning = false
		return
	end
	tweenCam.Completed:Connect(function(playbackState)
		if playbackState == Enum.PlaybackState.Completed then
			isTransitioning = false
		end
	end)
end

-- Переход из главного меню в редактор (слоты Slot1/Slot2)
local function transitionToCreation()
	if isTransitioning then return end
	isTransitioning = true

	local targetPos = UDim2.new(-1.2, 0, originalMainPos.Y.Scale, originalMainPos.Y.Offset)
	TweenService:Create(mainContainer, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Position = targetPos}):Play()

	SceneEffects.showCreationUI()

	-- Камера поворачивается ВЛЕВО на 90° (вид редактора)
	local tweenCam = SceneEffects.tweenCameraYaw(cameraBasePos, 0, -math.pi/2, 1.0)
	if not tweenCam then
		isTransitioning = false
		return
	end
	tweenCam.Completed:Connect(function(playbackState)
		if playbackState == Enum.PlaybackState.Completed then
			isTransitioning = false
		end
	end)
end

-- Переход из редактора в меню стихий (кнопка Next)
local function transitionFromCreation()
	if isTransitioning then return end
	isTransitioning = true

	-- Закрываем инвентари и палитры
	InventoryController.closeAll()

	-- ===== Скрываем CreationMenuGui (аналогично кнопке Back) =====
	SceneEffects.hideCreationUI()

	-- ===== Появление ElementMenuGui =====
	SceneEffects.showElementMenu()
	ElementMenu.setInputEnabled(true)

	-- ===== Анимация камеры: поворот ВПРАВО на 90° (от -pi/2 к -pi) =====
	local tweenCam = SceneEffects.tweenCameraYaw(cameraBasePos, -math.pi/2, -math.pi, 1.0)
	if not tweenCam then
		isTransitioning = false
		return
	end
	tweenCam.Completed:Connect(function(playbackState)
		if playbackState == Enum.PlaybackState.Completed then
			isTransitioning = false   -- разблокируем только после полного завершения камеры
		end
	end)

	-- Появление YourChoiceFrame
	SceneEffects.showYourChoiceFrame()
end

-- Обратный переход: ElementMenu > CreationMenu (кнопка Back в меню стихий)
local function transitionBackToCreation()
	if isTransitioning then return end
	isTransitioning = true
	-- Панели меню стихий уезжают ~0.8с, всё это время GUI ещё активен:
	-- блокируем кнопки стихий, чтобы клик в этом окне не испортил состояние
	ElementMenu.setInputEnabled(false)

	-- Закрываем все открытые инвентари (на всякий случай)
	InventoryController.closeAll()

	local resetChoiceEvent = ReplicatedStorage:WaitForChild("ResetElementChoiceEvent")
	resetChoiceEvent:Fire()

	-- === Плавно убираем открытый инфо-фрейм стихии (если есть) ===
	ElementMenu.closeOpenInfoFrame(0.5, true)

	-- === Убираем ElementMenuGui и возвращаем редактор ===
	-- (onHidden больше не разблокирует переход: ждём окончания камеры, см. ниже)
	SceneEffects.hideElementMenu({ yourChoice = "hide" })
	SceneEffects.showCreationUI()

	-- Камера назад в редактор; разблокируем переход только после её окончания
	local tweenCam = SceneEffects.tweenCameraYaw(cameraBasePos, -math.pi, -math.pi/2, 1.0)
	if not tweenCam then
		isTransitioning = false
		return
	end
	tweenCam.Completed:Connect(function(playbackState)
		if playbackState == Enum.PlaybackState.Completed then
			isTransitioning = false
		end
	end)
end

-- Финальный переход из меню стихий (выбор сделан)
local function transitionToFinal(chosenElement)
	if isTransitioning then return end
	isTransitioning = true
	-- Блокируем кнопки стихий на время перехода (GUI активен ещё ~0.8с)
	ElementMenu.setInputEnabled(false)

	-- Закрываем все инвентари/палитры
	InventoryController.closeAll()

	-- === EntranceGui нужен для перехода: проверяем ДО скрытия меню ===
	-- Иначе при отсутствии экземпляра WaitForChild висит вечно, а меню уже
	-- спрятаны - игровой процесс заблокирован навсегда
	local entranceGui = playerGui:WaitForChild("EntranceGui", 10)
	local entranceBackFrame = entranceGui and entranceGui:FindFirstChild("BackFrame")
	local entranceFrame = entranceGui and entranceGui:FindFirstChild("Frame")
	if not entranceBackFrame or not entranceFrame then
		warn("EntranceGui/BackFrame/Frame не найдены - финальный переход отменён")
		ElementMenu.setInputEnabled(true)
		isTransitioning = false
		return
	end

	-- === Восстановление после неудачной телепортации ===
	-- Возвращаем фон, меню стихий (выбор в HoverBorder2 сохранён) и камеру
	restoreAfterTeleportFailure = function()
		local backInfo = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(bgLeft, backInfo,
			{Position = bgLeftOriginalPos}):Play()
		TweenService:Create(bgRight, backInfo,
			{Position = bgRightOriginalPos}):Play()
		entranceGui.Enabled = false
		ElementMenu.setInputEnabled(true)
		SceneEffects.showElementMenu()
		SceneEffects.showYourChoiceFrame()
		SceneEffects.tweenCameraYaw(cameraBasePos, -3 * math.pi / 2, -math.pi, 1.0)
	end

	-- === Скрываем ElementMenuGui ===
	SceneEffects.hideElementMenu({ yourChoice = "slide" })

	-- Убираем открытый инфо-фрейм, если остался
	ElementMenu.closeOpenInfoFrame(0.5, false)

	-- === Фоновые панели MainMenuGui разлетаются в стороны ===
	local tweenInfo = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(bgLeft, tweenInfo,
		{Position = UDim2.new(-2, 0, 0.5, 0)}):Play()
	TweenService:Create(bgRight, tweenInfo,
		{Position = UDim2.new(2, 0, 0.5, 0)}):Play()

	-- Прозрачность нужно менять и у детей: BackgroundTransparency родителя на них
	-- не действует, и при включении GUI они вспыхнули бы раньше твина.
	-- Запоминаем исходные значения и прячем всё ДО включения GUI.
	local entranceFadeTargets = {}
	local function collectAndHideFade(obj)
		local props = nil
		if obj:IsA("GuiObject") then
			props = { BackgroundTransparency = obj.BackgroundTransparency }
			if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
				props.TextTransparency = obj.TextTransparency
				props.TextStrokeTransparency = obj.TextStrokeTransparency
			end
			if obj:IsA("ImageLabel") or obj:IsA("ImageButton") then
				props.ImageTransparency = obj.ImageTransparency
			end
		elseif obj:IsA("UIStroke") then
			props = { Transparency = obj.Transparency }
		end
		if props then
			for prop in pairs(props) do
				obj[prop] = 1
			end
			entranceFadeTargets[obj] = props
		end
	end

	entranceBackFrame.Visible = true
	entranceFrame.Visible = true
	collectAndHideFade(entranceBackFrame)
	collectAndHideFade(entranceFrame)
	for _, desc in ipairs(entranceBackFrame:GetDescendants()) do collectAndHideFade(desc) end
	for _, desc in ipairs(entranceFrame:GetDescendants()) do collectAndHideFade(desc) end
	entranceGui.Enabled = true

	-- === Поворот и подъём камеры ===
	local camera = workspace.CurrentCamera
	if not camera then
		warn("CurrentCamera отсутствует - финальный переход отменён")
		restoreAfterTeleportFailure()
		isTransitioning = false
		return
	end

	camera.CameraType = Enum.CameraType.Scriptable

	local angleVal = Instance.new("NumberValue")
	angleVal.Value = -math.pi
	local targetAngle = -3 * math.pi / 2

	local heightVal = Instance.new("NumberValue")
	heightVal.Value = 0
	local targetHeight = 3   -- подъём на 3 студита

	local function updateCamera()
		camera.CFrame = CFrame.new(cameraBasePos + Vector3.new(0, heightVal.Value, 0))
			* CFrame.Angles(0, angleVal.Value, 0)
	end

	angleVal.Changed:Connect(updateCamera)
	heightVal.Changed:Connect(updateCamera)

	local tweenAngle = TweenService:Create(angleVal,
		TweenInfo.new(2.0, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Value = targetAngle})
	local tweenHeight = TweenService:Create(heightVal,
		TweenInfo.new(2.0, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Value = targetHeight})

	tweenAngle:Play()
	tweenHeight:Play()

	tweenAngle.Completed:Connect(function(playbackState)
		if playbackState ~= Enum.PlaybackState.Completed then return end

		-- Пауза после поворота/подъёма
		task.wait(0.5)

		-- Движение вперёд
		local forwardDistance = 30
		local targetCFrame = camera.CFrame * CFrame.new(0, 0, -forwardDistance)

		local tweenForward = TweenService:Create(camera,
			TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{CFrame = targetCFrame})
		tweenForward:Play()

		-- Примерно в конце движения (через 0.6 секунды) начинаем проявлять EntranceGui
		task.spawn(function()
			task.wait(0.6)
			local appearInfo = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			-- Проявляем и сами фреймы, и их детей (каждый к своей исходной прозрачности)
			for obj, props in pairs(entranceFadeTargets) do
				TweenService:Create(obj, appearInfo, props):Play()
			end
		end)

		tweenForward.Completed:Connect(function(playbackStateFwd)
			if playbackStateFwd ~= Enum.PlaybackState.Completed then return end
			angleVal:Destroy()
			heightVal:Destroy()
			isTransitioning = false
			print("Финальный переход завершён. Элемент:", chosenElement)

			-- Телепортируем только когда анимация полностью доиграла:
			-- раньше запрос уходил на 0.7с раньше окончания движения и проявления
			-- EntranceGui
			local requestTeleport = ReplicatedStorage:WaitForChild("RequestTeleport", 10)
			if requestTeleport then
				requestTeleport:FireServer(chosenElement) -- chosenElement - имя выбранной стихии
			else
				warn("RequestTeleport не найден - возврат в меню стихий")
				restoreAfterTeleportFailure()
			end
		end)
	end)
end

-- ===================== ПОДКЛЮЧЕНИЕ КНОПОК И СОБЫТИЙ =====================
slot1.Activated:Connect(transitionToCreation)
slot2.Activated:Connect(transitionToCreation)
backBtn.Activated:Connect(returnToMenu)
nextBtn.Activated:Connect(transitionFromCreation)

-- Кнопка Back в меню стихий
elementBackButton.Activated:Connect(transitionBackToCreation)

ElementChosenEvent.Event:Connect(function(elementName)
	print("Выбрана стихия:", elementName, "– выполняю финальный переход.")
	transitionToFinal(elementName)
end)

print("Система управления инвентарями, цвета и рандомайзер готова!")
