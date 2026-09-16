                local btn = script.Parent
                local stroke = btn:FindFirstChild("BorderStroke")
                local defaultColor = stroke and stroke.Color or Color3.fromRGB(206, 167, 62)
                local hoverColor
                if btn.Name == "Slot3" then
                    hoverColor = Color3.fromRGB(255, 150, 90)
                else
                    hoverColor = Color3.fromRGB(255, 210, 80)
                end
                -- Запоминаем реальные параметры обводки: иначе MouseLeave
                -- затирает их на хардкод (толщина 1, прозрачность 0.3)
                local defaultThickness = stroke and stroke.Thickness or 1
                local defaultTransparency = stroke and stroke.Transparency or 0.3
                local hoverThickness = 3

                local label = btn:FindFirstChild("PlaceholderLabel")
                local defaultText = label and label.Text or "?"

                local hoverText
				if btn.Name == "Slot3" then
					hoverText = "Buy Extra Slot"
				else
					hoverText = "Create New Character"
				end

                btn.MouseEnter:Connect(function()
                    if stroke then
                        stroke.Color = hoverColor
                        stroke.Thickness = hoverThickness
                        stroke.Transparency = 0
                    end
                    if label then
                        label.Text = hoverText
                    end
                end)

                btn.MouseLeave:Connect(function()
                    if stroke then
                        stroke.Color = defaultColor
                        stroke.Thickness = defaultThickness
                        stroke.Transparency = defaultTransparency
                    end
                    if label then
                        label.Text = defaultText
                    end
                end)
                -- Обработчик клика убран
            