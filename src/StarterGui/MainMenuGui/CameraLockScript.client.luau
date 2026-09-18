--[[
	CameraLockScript - стартовая камера главного меню.
	LocalScript внутри MainMenuGui.

	Ставит Scriptable-камеру один раз при старте. Специально НЕ держит
	CFrame каждый RenderStepped: во время переходов камеру ведут
	SceneEffects.tweenCameraYaw и финальный полёт в SceneTransition, и
	постоянный лок конфликтовал бы с ними (двойная запись CFrame).
]]

local camera = workspace.CurrentCamera
if not camera then return end

camera.CameraType = Enum.CameraType.Scriptable

-- Вариант 1: Строго горизонтально (прямо)
local targetPosition = Vector3.new(0, 4, 0)
local lookAtPoint = Vector3.new(0, 8, -50)  -- смотрит прямо вдоль отрицательной Z

-- Вариант 2: Лёгкий наклон для красивого вида (как в Genshin)
-- local targetPosition = Vector3.new(0, 10, 15)
-- local lookAtPoint = Vector3.new(0, 2, 0)   -- камера смотрит немного вниз и вперёд

local cameraCFrame = CFrame.lookAt(targetPosition, lookAtPoint)
camera.CFrame = cameraCFrame
camera.FieldOfView = 55  -- узкий угол для кинематографичности
