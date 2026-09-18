--[[
	PlayerDataManager - серверное хранилище данных игрока.
	ModuleScript в ServerScriptService с именем "PlayerDataManager".

	Замена бывшей глобальной таблицы _G.PlayerSkinColors: цвет кожи -
	единственные данные, которыми обмениваются серверные скрипты, и теперь
	они живут в модуле с типизированным доступом, а не в _G (глобальное
	состояние легко перезатереть из любого скрипта и невозможно отследить).

	Используется из InventoryServer (хранение и выдача цвета кожи).
	Модуль должен быть загружен раньше обращений - require у потребителей
	гарантирует это.

	Экспортирует:
	  PlayerDataManager.getSkinColor(player) -> Color3?   -- nil, если не задан
	  PlayerDataManager.setSkinColor(player, color)
	  PlayerDataManager.clearPlayer(player)                -- вызывать в PlayerRemoving
]]

--!strict

local PlayerDataManager = {}

-- Слабые ключи: запись живёт, пока жив игрок, даже без явной очистки
local skinColors: {[Player]: Color3} = {}

function PlayerDataManager.getSkinColor(player: Player): Color3?
	return skinColors[player]
end

function PlayerDataManager.setSkinColor(player: Player, color: Color3)
	skinColors[player] = color
end

function PlayerDataManager.clearPlayer(player: Player)
	skinColors[player] = nil
end

return PlayerDataManager
