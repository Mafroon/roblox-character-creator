--[[
	Смена пола персонажа (Script в ServerScriptService).

	По ChangeGenderEvent заменяет торсы рига (ReplaceBodyPartR15) из
	ServerStorage.Gender, сохраняет цвет кожи, обновляет StringValue
	PlayerGender и перезапускает idle (AnimationController).

	Требует в ReplicatedStorage RemoteEvent "ChangeGenderEvent".
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")

local AnimationController = require(script.Parent:WaitForChild("AnimationController"))
local RigParts = require(script.Parent:WaitForChild("RigParts"))

local changeGenderEvent = ReplicatedStorage:WaitForChild("ChangeGenderEvent")

local genderFolder = ServerStorage:WaitForChild("Gender")
local maleRig = genderFolder:WaitForChild("Male")
local femaleRig = genderFolder:WaitForChild("Female")

-- Функция замены конкретной части тела
local function replaceTorso(character, rigModel, partName, bodyPartEnum)
	local sourcePart = rigModel:FindFirstChild(partName)
	if not sourcePart then
		warn("Не найдена часть " .. partName .. " в риге " .. rigModel.Name)
		return
	end

	local clone = sourcePart:Clone()
	clone.Parent = character

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:ReplaceBodyPartR15(bodyPartEnum, clone)
	end
end

changeGenderEvent.OnServerEvent:Connect(function(player, gender)
	-- Валидация: иначе любое значение, кроме "male" (в т.ч. мусор от эксплойтера),
	-- молча выбирает женский риг
	if gender ~= "male" and gender ~= "female" then
		warn("MaleFemale: некорректный пол " .. tostring(gender) .. " от " .. tostring(player and player.Name))
		return
	end

	if not player or not player.Character then return end

	local character = player.Character

	if not maleRig or not femaleRig then
		warn("Риг для пола " .. gender .. " не найден")
		return
	end
	local rig = (gender == "male") and maleRig or femaleRig

	-- 1. Запоминаем текущий цвет кожи (возьмём цвет головы, он всегда есть)
	local skinColor = nil
	local head = character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		skinColor = head.Color
		print("Сохранён цвет кожи:", skinColor)
	else
		-- Если головы нет, пробуем взять цвет любой другой части
		for _, part in ipairs(character:GetChildren()) do
			if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
				skinColor = part.Color
				break
			end
		end
	end

	-- 2. Заменяем торсы
	replaceTorso(character, rig, "UpperTorso", Enum.BodyPartR15.UpperTorso)
	replaceTorso(character, rig, "LowerTorso", Enum.BodyPartR15.LowerTorso)

	-- 3. Обновляем StringValue с полом
	local genderValue = player:FindFirstChild("PlayerGender")
	if not genderValue then
		genderValue = Instance.new("StringValue")
		genderValue.Name = "PlayerGender"
		genderValue.Parent = player
	end
	genderValue.Value = gender

	-- 4. Восстанавливаем цвет кожи (применяем к частям тела из RigParts)
	if skinColor then
		RunService.Heartbeat:Wait()  -- ждём ровно 1 кадр, минимум задержки
		for _, partName in ipairs(RigParts.SKIN_PART_NAMES) do
			local part = character:FindFirstChild(partName)
			if part and part:IsA("BasePart") then
				part.Color = skinColor
			end
		end
		-- Широкую "подстраховку" (перекраска всех BasePart персонажа) убрали:
		-- она красила бы цветом кожи любой предмет, если тот окажется голым BasePart
		print("Цвет кожи восстановлен после смены пола")
	end

	-- 5. Замена торсов через ReplaceBodyPartR15 пересобирает Motor6D и может
	-- остановить игравший idle-трек - перезапускаем его, иначе персонаж
	-- застывает "стойкой смирно" после смены пола
	AnimationController.replayCharacterIdle(character)

	print("Пол игрока " .. player.Name .. " изменён на " .. gender)
end)