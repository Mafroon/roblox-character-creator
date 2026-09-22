--[[
	Кастомный спавн персонажа (Script в ServerScriptService).

	Отключает автоспавн (Players.CharacterAutoLoads = false) и выдаёт
	игроку клон рига Male/Female из ServerStorage.Gender со случайным
	полом. Idle-анимацию перезапускает AnimationController.

	Требует в ServerStorage:
	  Gender.Male, Gender.Female - модели ригов R15
	  Animations.Idle            - Animation с заполненным AnimationId
]]

local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")

local AnimationController = require(script.Parent:WaitForChild("AnimationController"))

Players.CharacterAutoLoads = false

-- Папки с готовыми моделями полов
local genderFolder = ServerStorage:WaitForChild("Gender")
local maleRig = genderFolder:WaitForChild("Male")
local femaleRig = genderFolder:WaitForChild("Female")

local spawnPosition = Vector3.new(10, 0, 0)
local spawnRotation = CFrame.Angles(0, math.rad(90), 0)

local rng = Random.new()

local function spawnPlayer(player)
	-- 50% шанс получить мужской или женский риг
	local chosenGender = if rng:NextNumber() < 0.5 then "male" else "female"
	local rigTemplate = if chosenGender == "male" then maleRig else femaleRig

	local rig = rigTemplate:Clone()
	rig.Name = player.Name .. "_CustomAvatar"

	-- Animator создаём ДО первого парента рига: треки реплицируются через
	-- Animator, и если клиент впервые видит персонажа ещё без него, запущенный
	-- сервером idle может не доехать
	local humanoidEarly = rig:FindFirstChildOfClass("Humanoid")
	if humanoidEarly and not humanoidEarly:FindFirstChildOfClass("Animator") then
		Instance.new("Animator").Parent = humanoidEarly
	end

	rig.Parent = workspace

	-- Позиционируем риг
	local rootPart = rig:FindFirstChild("HumanoidRootPart") or rig.PrimaryPart
	if rootPart then
		rootPart.Anchored = true
		rig:PivotTo(CFrame.new(spawnPosition) * spawnRotation)
	else
		warn("Риг не имеет HumanoidRootPart или PrimaryPart – пропускаем позиционирование")
		rig:PivotTo(CFrame.new(spawnPosition) * spawnRotation)
	end

	-- Настраиваем гуманоида
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.AutoRotate = false
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Physics, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
		humanoid.PlatformStand = false
	end

	-- Пауза для подписок других скриптов (инвентарь, одежда и т.д.)
	task.wait(0.1)
	player.Character = rig

	-- Сохраняем пол игрока в StringValue, чтобы клиент знал его всегда
	local genderValue = player:FindFirstChild("PlayerGender")
	if not genderValue then
		genderValue = Instance.new("StringValue")
		genderValue.Name = "PlayerGender"
		genderValue.Parent = player
	end
	genderValue.Value = chosenGender

	print("Заспавнен " .. chosenGender .. " персонаж для " .. player.Name)

	-- Проигрываем idle-анимацию. Задержка не случайна: в момент присвоения
	-- player.Character клиент забирает владение ригом, и трек, запущенный
	-- сервером в это же окно, до клиента доезжает не всегда
	task.delay(0.5, function()
		if rig.Parent then
			AnimationController.replayCharacterIdle(rig)
		end
	end)
end

Players.PlayerAdded:Connect(spawnPlayer)

-- Игроки, зашедшие до запуска скрипта (например, в Studio Play Solo):
-- без отката риг для них вообще не создаётся
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(spawnPlayer, player)
end
