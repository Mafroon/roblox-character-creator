--[[
	RigParts - имена частей тела кастомного R15-рига.
	ModuleScript в ServerScriptService с именем "RigParts".

	Риги персонажей в этой игре - R15 (торсы меняются через
	Humanoid:ReplaceBodyPartR15 в MaleFemale), поэтому здесь только
	R15-имена. Раньше список дублировался в InventoryServer (перемешанный
	с никогда не совпадающими R6-именами вроде "Left Arm" и "Torso") и
	MaleFemale - теперь источник один.

	Рук и стоп (LeftHand, RightFoot, ...) в списке нет: они не входили
	в исходные наборы перекраски, добавление изменило бы поведение.

	Экспортирует:
	  RigParts.SKIN_PART_NAMES - {string} части, которые перекрашиваются
	  под цвет кожи
]]

--!strict

local RigParts = {}

RigParts.SKIN_PART_NAMES = {
	"Head",
	"UpperTorso", "LowerTorso",
	"LeftUpperArm", "LeftLowerArm",
	"RightUpperArm", "RightLowerArm",
	"LeftUpperLeg", "LeftLowerLeg",
	"RightUpperLeg", "RightLowerLeg",
}

return RigParts
