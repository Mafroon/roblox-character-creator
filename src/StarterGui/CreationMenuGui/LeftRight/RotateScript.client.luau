    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local player = Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")
    local creationGui = playerGui:WaitForChild("CreationMenuGui")
    local leftRight = creationGui:WaitForChild("LeftRight")
    local leftBtn = leftRight:WaitForChild("Left"):WaitForChild("TextButton")
    local rightBtn = leftRight:WaitForChild("Right"):WaitForChild("TextButton")

    local rotatingLeft = false
    local rotatingRight = false
    local ROTATION_SPEED = 90  -- градусов в секунду
    local currentRotation = nil  -- захватим начальный угол при первом нажатии

    -- Подключаем кнопки
    leftBtn.MouseButton1Down:Connect(function() rotatingLeft = true end)
    leftBtn.MouseButton1Up:Connect(function() rotatingLeft = false end)
    leftBtn.MouseLeave:Connect(function() rotatingLeft = false end)

    rightBtn.MouseButton1Down:Connect(function() rotatingRight = true end)
    rightBtn.MouseButton1Up:Connect(function() rotatingRight = false end)
    rightBtn.MouseLeave:Connect(function() rotatingRight = false end)

    -- Главный цикл вращения
    RunService.RenderStepped:Connect(function(dt)
        if not (rotatingLeft or rotatingRight) then return end
        if not leftRight.Visible then return end  -- не в режиме создания

        local char = player.Character
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart")
        if not root then return end

        -- Запоминаем начальный угол при первом нажатии
        if currentRotation == nil then
            local _, y, _ = root.CFrame:ToOrientation()
            currentRotation = y
        end

        local angle = math.rad(ROTATION_SPEED) * dt
        if rotatingLeft then
            -- Left -> поворот вправо (по часовой) → отрицательный угол
            currentRotation = currentRotation - angle
        elseif rotatingRight then
            -- Right -> поворот влево → положительный угол
            currentRotation = currentRotation + angle
        end

        -- Применяем поворот, сохраняя позицию
        root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, currentRotation, 0)
        -- Обнуляем скорости, чтобы физика не дёргала
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end)
