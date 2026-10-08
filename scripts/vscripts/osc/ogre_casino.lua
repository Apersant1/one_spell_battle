ogre_magi_unrefined_fireblast = class({})

function ogre_magi_unrefined_fireblast:OnSpellStart()
    local hero = self:GetCaster()
    if not hero or hero:GetUnitName() ~= "npc_dota_hero_ogre_magi" or not hero:HasScepter() then
        print("[OSC] Casino ability requires Ogre Magi with Aghanim's Scepter")
        return
    end

    local gameMode = GameRules.OSC
    if gameMode then
        gameMode:OpenCasino(hero)
    end
end
