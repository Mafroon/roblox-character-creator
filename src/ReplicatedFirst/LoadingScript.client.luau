-- ReplicatedFirst / LoadingScreenClient (LocalScript)
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local startGameEvent = ReplicatedStorage:WaitForChild("StartGameEvent", 10)
if not startGameEvent then
	warn("StartGameEvent не найден!")
	return
end

local FINAL_HEIGHT = 0.45
local GRADIENT_AMPLITUDE = 90
local GRADIENT_CENTER = 90
local GRADIENT_PERIOD = 4
local STOP_GRADIENT_DURATION = 1
local TWEEN_DURATION = 2
local MIN_SHOW_TIME = 3

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui", 5)
if not playerGui then return end

ReplicatedFirst:RemoveDefaultLoadingScreen()

-- Если шаблона нет — просто пропускаем экран загрузки, но не ломаем сессию:
-- иначе StartGameEvent не сработает и SceneTransition будет ждать вечно
local loadingTemplate = ReplicatedFirst:WaitForChild("LoadingScreen", 10)
if not loadingTemplate then
	warn("Шаблон LoadingScreen не найден - запускаем игру без экрана загрузки")
	startGameEvent:Fire()
	return
end
local loadingGui = loadingTemplate:Clone()
loadingGui.Parent = playerGui

-- скрываем другие GUI
for _, gui in playerGui:GetChildren() do
	if gui:IsA("ScreenGui") and gui ~= loadingGui then
		gui.Enabled = false
	end
end

local guiBlocker = playerGui.ChildAdded:Connect(function(child)
	if child:IsA("ScreenGui") and child ~= loadingGui then
		child.Enabled = false
	end
end)

-- Аварийное завершение: снимаем блокировку GUI и всё равно запускаем игру.
-- Нельзя просто return: guiBlocker остался бы навсегда и "убил" бы всю сессию.
local function abortLoadingScreen(reason)
	warn("Экран загрузки прерван: " .. reason)
	guiBlocker:Disconnect()
	for _, gui in playerGui:GetChildren() do
		if gui:IsA("ScreenGui") and gui ~= loadingGui then
			gui.Enabled = true
		end
	end
	startGameEvent:Fire()
	loadingGui:Destroy()
end

local backFrame = loadingGui:WaitForChild("BackFrame", 5)
local continueFrame = backFrame and backFrame:WaitForChild("ContinueFrame", 5)
if not continueFrame then return abortLoadingScreen("ContinueFrame не найден") end
continueFrame.Position = UDim2.new(0.5, 0, 1.1, 0)

local line = backFrame:WaitForChild("Line", 5)
if not line then return abortLoadingScreen("Line не найден") end
line.Rotation = 90
line.Size = UDim2.new(1, 0, 0, 0)

-- Цепочка разбита на шаги: chained WaitForChild на nil-промежуточном падает с ошибкой
local namesFrame = backFrame:WaitForChild("Names", 5)
local nameFrame = namesFrame and namesFrame:WaitForChild("Name", 5)
local draftFrame = nameFrame and nameFrame:WaitForChild("Draft", 5)
if not draftFrame then return abortLoadingScreen("Draft не найден") end
local gradient = draftFrame:WaitForChild("UIGradient", 5)
if not gradient then return abortLoadingScreen("UIGradient не найден") end

local accumulatedTime = 0
local renderConnection = RunService.RenderStepped:Connect(function(dt)
	accumulatedTime += dt
	local angle = GRADIENT_CENTER + GRADIENT_AMPLITUDE * math.sin(accumulatedTime * (2 * math.pi / GRADIENT_PERIOD))
	gradient.Rotation = angle
end)

if not game:IsLoaded() then game.Loaded:Wait() end

local startTime = os.clock()
while os.clock() - startTime < MIN_SHOW_TIME do task.wait(0.1) end

if renderConnection then renderConnection:Disconnect() end

local stopGradTween = TweenService:Create(gradient, TweenInfo.new(STOP_GRADIENT_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Rotation = 90})
stopGradTween:Play()
stopGradTween.Completed:Wait()

local showInfo = TweenInfo.new(TWEEN_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
TweenService:Create(line, showInfo, {Size = UDim2.new(1, 0, FINAL_HEIGHT, 0)}):Play()
TweenService:Create(continueFrame, showInfo, {Position = UDim2.new(0.5, 0, 0.77, 0)}):Play()

local continueButton = continueFrame:WaitForChild("ContinueButton", 5)
if continueButton then
	-- Activated покрывает мышь, тач и геймпад (MouseButton1Click - только мышь)
	continueButton.Activated:Wait()
end

guiBlocker:Disconnect()
startGameEvent:Fire()
loadingGui:Destroy()