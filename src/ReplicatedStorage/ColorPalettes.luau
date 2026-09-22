--[[
	ColorPalettes - общие цветовые палитры кастомизации.
	ModuleScript в ReplicatedStorage с именем "ColorPalettes".

	Единый источник палитр для сервера (InventoryServer - случайный набор
	на спавне) и клиента (InventoryController - кнопка рандомайзера).

	Экспортирует:
	  ColorPalettes.pleasantColors - {Color3} основная палитра
	  ColorPalettes.accentColors   - {Color3} редкие яркие акценты
	  ColorPalettes.skinColors     - {Color3} телесные оттенки кожи
	  ColorPalettes.getPleasantColor(rng, accentChance?) -> Color3
]]

--!strict

local ColorPalettes = {}

ColorPalettes.pleasantColors = {
	Color3.fromRGB(255, 179, 186), Color3.fromRGB(255, 223, 186),
	Color3.fromRGB(255, 255, 186), Color3.fromRGB(186, 255, 201),
	Color3.fromRGB(186, 225, 255), Color3.fromRGB(210, 186, 255),
	Color3.fromRGB(222, 184, 135), Color3.fromRGB(160, 120, 90),
	Color3.fromRGB(150, 130, 110), Color3.fromRGB(100, 120, 150),
	Color3.fromRGB(70, 90, 70),    Color3.fromRGB(150, 150, 150),
	Color3.fromRGB(255, 255, 255), Color3.fromRGB(0, 0, 0),
	Color3.fromRGB(50, 50, 50),
}

ColorPalettes.accentColors = {
	Color3.fromRGB(255, 0, 0), Color3.fromRGB(0, 255, 0),
	Color3.fromRGB(0, 0, 255), Color3.fromRGB(255, 255, 0),
	Color3.fromRGB(255, 0, 255), Color3.fromRGB(0, 255, 255),
}

ColorPalettes.skinColors = {
	Color3.fromRGB(255, 205, 148), Color3.fromRGB(234, 192, 134),
	Color3.fromRGB(210, 170, 120), Color3.fromRGB(181, 136, 99),
	Color3.fromRGB(141, 101, 72),  Color3.fromRGB(102, 71, 45),
	Color3.fromRGB(77, 53, 33),
}

-- Случайный "приятный" цвет: с шансом accentChance (по умолчанию 0.07)
-- выпадает яркий акцент, иначе - цвет из основной палитры
function ColorPalettes.getPleasantColor(rng: Random, accentChance: number?): Color3
	local chance = accentChance or 0.07
	if rng:NextNumber() < chance then
		return ColorPalettes.accentColors[rng:NextInteger(1, #ColorPalettes.accentColors)]
	else
		return ColorPalettes.pleasantColors[rng:NextInteger(1, #ColorPalettes.pleasantColors)]
	end
end

return ColorPalettes
