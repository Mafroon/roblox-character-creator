-- Кастомный спавн персонажа (ServerScriptService)
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

Players.CharacterAutoLoads = false

-- Папки с готовыми моделями полов
local genderFolder = ServerStorage:WaitForChild("Gender")
local maleRig = genderFolder:WaitForChild("Male")
local femaleRig = genderFolder:WaitForChild("Female")

local spawnPosition = Vector3.new(10, 0, 0)
local spawnRotation = CFrame.Angles(0, math.rad(90), 0)

-- Idle-анимация ищется при каждом спавне, а не один раз при старте скрипта:
-- раньше FindFirstChild молча пропускал анимацию (нет папки, переименована,
-- пустой AnimationId), и персонаж замирал "стойкой смирно" без объяснений
local function findIdleAnimation()
	local folder = ServerStorage:FindFirstChild("Animations")
	if not folder then
		warn("ReplaceAvatarWithRig: в ServerStorage нет папки 'Animations' - персонаж будет стоять без idle-анимации")
		return nil
	end
	local idle = folder:FindFirstChild("Idle")
	if not idle then
		warn("ReplaceAvatarWithRig: в ServerStorage.Animations нет объекта 'Idle' - персонаж будет стоять без idle-анимации")
		return nil
	end
	if not idle:IsA("Animation") then
		warn("ReplaceAvatarWithRig: ServerStorage.Animations.Idle не является Animation - idle не сыграет")
		return nil
	end
	if idle.AnimationId == "" then
		warn("ReplaceAvatarWithRig: у ServerStorage.Animations.Idle пустой AnimationId - idle не сыграет")
		return nil
	end
	return idle
end

-- Проигрывает idle заново, останавливая уже идущие треки. Вынесено в _G для
-- серверных скриптов, которые трогают части тела: MaleFemale после
-- ReplaceBodyPartR15 перезапускает idle этим вызовом
function _G.ReplayCharacterIdle(character)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	local idle = findIdleAnimation()
	if not idle then return end

	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = humanoid
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		track:Stop(0.1)
	end
	local ok, err = pcall(function()
		local idleTrack = animator:LoadAnimation(idle)
		idleTrack.Looped = true
		idleTrack:Play()
	end)
	if ok then
		print("Кастомная idle-анимация для " .. character.Name)
	else
		warn("ReplaceAvatarWithRig: не удалось запустить idle-анимацию: " .. tostring(err))
	end
end

local rng = Random.new()

local function spawnPlayer(player)
	-- 50% шанс получить мужской или женский риг
	local chosenGender = if rng:NextNumber() < 0.5 then "male" else "female"
	local rigTemplate = if chosenGender == "male" then maleRig else femaleRig

	local rig = rigTemplate:Clone()
	rig.Name = player.Name .. "_CustomAvatar"

	-- Animator создаём ДО первого парента рига: треки реплицируются через
	-- Animator, и если клиент впервые видит персонажа ещё без него, запущенный
	-- сервером idle может не доехать (персонаж замирал до смены пола)
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
	-- сервером в это же окно, до клиента доезжает не всегда (поэтому персонаж
	-- "оживал" только после смены пола - там тот же трек запускался позже)
	task.delay(0.5, function()
		if rig.Parent then
			_G.ReplayCharacterIdle(rig)
		end
	end)
end

Players.PlayerAdded:Connect(spawnPlayer)

-- Игроки, зашедшие до запуска скрипта (например, в Studio Play Solo):
-- без отката риг для них вообще не создаётся
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(spawnPlayer, player)
end