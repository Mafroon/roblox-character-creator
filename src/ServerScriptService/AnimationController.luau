--[[
	AnimationController - серверный перезапуск idle-анимации персонажа.
	ModuleScript в ServerScriptService с именем "AnimationController".

	Замена бывшей глобальной функции _G.ReplayCharacterIdle: вызовы между
	серверными скриптами теперь идут через require, а не через _G.

	Idle ищется в ServerStorage.Animations.Idle при каждом вызове, а не
	один раз при старте: раньше FindFirstChild молча пропускал анимацию
	(нет папки, переименована, пустой AnimationId), и персонаж замирал
	"стойкой смирно" без объяснений.

	Используется из:
	  - ReplaceAvatarWithRig - спавн (с задержкой: в момент присвоения
	    player.Character клиент забирает владение ригом, и трек, запущенный
	    сервером в это же окно, до клиента доезжает не всегда);
	  - MaleFemale - после ReplaceBodyPartR15, который пересобирает
	    Motor6D и останавливает игравший трек;
	  - InventoryServer - после случайной экипировки на спавне.

	Экспортирует:
	  AnimationController.replayCharacterIdle(character)
]]

--!strict

local ServerStorage = game:GetService("ServerStorage")

local AnimationController = {}

local function findIdleAnimation(): Animation?
	local folder = ServerStorage:FindFirstChild("Animations")
	if not folder then
		warn("AnimationController: в ServerStorage нет папки 'Animations' - персонаж будет стоять без idle-анимации")
		return nil
	end
	local idle = folder:FindFirstChild("Idle")
	if not idle then
		warn("AnimationController: в ServerStorage.Animations нет объекта 'Idle' - персонаж будет стоять без idle-анимации")
		return nil
	end
	if not idle:IsA("Animation") then
		warn("AnimationController: ServerStorage.Animations.Idle не является Animation - idle не сыграет")
		return nil
	end
	if idle.AnimationId == "" then
		warn("AnimationController: у ServerStorage.Animations.Idle пустой AnimationId - idle не сыграет")
		return nil
	end
	return idle
end

-- Проигрывает idle заново, останавливая уже идущие треки
function AnimationController.replayCharacterIdle(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	local idle = findIdleAnimation()
	if not idle then return end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
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
		warn("AnimationController: не удалось запустить idle-анимацию: " .. tostring(err))
	end
end

return AnimationController
