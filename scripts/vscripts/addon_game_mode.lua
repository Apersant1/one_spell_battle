require("osc/config")
require("osc/abilities")
require("osc/item_ultimate_reroll")
require("osc/ogre_casino")
require("osc/ogre_casino")
require("osc/modifier_osc_courier_drunk")
require("osc/couriers")
require("osc/game_mode")


-- Generated from template

if CAddonTemplateGameMode == nil then
	CAddonTemplateGameMode = class({})
end

function Precache(context)
    -- Прекэшим героев-владельцев способностей из whitelist,
    -- иначе у чужих способностей не будет партиклов и звуков
    local done = {}
    for _, pool in ipairs({ OSC_ABILITY_POOL, OSC_ULTIMATE_POOL }) do
        for _, entry in ipairs(pool) do
            if not done[entry.hero] then
                done[entry.hero] = true
                PrecacheUnitByNameSync(entry.hero, context)
            end
        end
    end

    PrecacheUnitByNameSync("npc_osc_casino_test_object", context)
    PrecacheResource("particle", "particles/generic_hero_status/hero_levelup.vpcf", context)
end

function Activate()
    GameRules.OSC = OneSpellChaos()
    GameRules.OSC:Init()
end

function CAddonTemplateGameMode:InitGameMode()
	print( "[DEBUG] Template addon is loaded." )
	GameRules:GetGameModeEntity():SetThink( "OnThink", self, "GlobalThink", 2 )
end

-- Evaluate the state of the game
function CAddonTemplateGameMode:OnThink()
	if GameRules:State_Get() == DOTA_GAMERULES_STATE_GAME_IN_PROGRESS then
		--print( "Template addon script is running." )
	elseif GameRules:State_Get() >= DOTA_GAMERULES_STATE_POST_GAME then
		return nil
	end
	return 1
end