ogre_magi_casino = class({})

function ogre_magi_casino:OnSpellStart()
    local hero = self:GetCaster()
    if not hero or hero:GetUnitName() ~= "npc_dota_hero_ogre_magi" then
        OSC_Logger.Error("Casino ability can only be used by Ogre Magi")
        return
    end

    OSC_Casino.SpawnMachine(hero)
end