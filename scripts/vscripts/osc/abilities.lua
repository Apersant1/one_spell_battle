OSC_Abilities = {}

local function ShouldKeep(name)
    if OSC_KEEP_ABILITIES[name] then
        return true
    end
    if string.sub(name, 1, 14) == "special_bonus_" then
        return true
    end
    return false
end

function OSC_Abilities.StripHero(hero)
    -- Сначала собираем имена, потом удаляем, чтобы не сбить индексы
    local toRemove = {}
    for i = 0, hero:GetAbilityCount() - 1 do
        local ability = hero:GetAbilityByIndex(i)
        if ability and not ShouldKeep(ability:GetAbilityName()) then
            table.insert(toRemove, ability:GetAbilityName())
        end
    end

    for _, name in ipairs(toRemove) do
        hero:RemoveAbility(name)
    end
end

function OSC_Abilities.PickRandom(excludeName)
    local pool = OSC_ABILITY_POOL
    if #pool == 1 then
        return pool[1]
    end

    local entry
    repeat
        entry = pool[RandomInt(1, #pool)]
    until entry.name ~= excludeName  -- не выдаём ту же способность подряд

    return entry
end

function OSC_Abilities.CopyFromOwner(unit, owner)
    OSC_Abilities.StripHero(unit)

    local name = owner.osc_current_ability
    if not name then return end

    local source = owner:FindAbilityByName(name)
    local ability = unit:AddAbility(name)
    if ability then
        ability:SetLevel(source and source:GetLevel() or 1)
        ability:SetHidden(false)
    end

    unit.osc_current_ability = name
end


function OSC_Abilities.CalcLevel(heroLevel, ability)
    local target
    if ability:GetAbilityType() == ABILITY_TYPE_ULTIMATE then
        if heroLevel >= 18 then
            target = 3
        elseif heroLevel >= 12 then
            target = 2
        else
            target = 1
        end
    else
        target = math.ceil(heroLevel / 2)
    end

    return math.max(1, math.min(ability:GetMaxLevel(), target))
end

function OSC_Abilities.RemoveCurrent(hero)
    local oldName = hero.osc_current_ability
    if not oldName then
        return
    end

    local old = hero:FindAbilityByName(oldName)
    if old then
        if old:IsChanneling() then
            hero:InterruptChannel()
        end
        hero:RemoveAbilityByHandle(old)
    end
end

function OSC_Abilities.GiveRandom(hero, notify)
    local oldName = hero.osc_current_ability
    OSC_Abilities.RemoveCurrent(hero)

    local entry = OSC_Abilities.PickRandom(oldName)
    local ability = hero:AddAbility(entry.name)
    if not ability then
        print("[OSC] Failed to add ability: " .. entry.name)
        hero.osc_current_ability = nil
        return nil
    end

    ability:SetLevel(OSC_Abilities.CalcLevel(hero:GetLevel(), ability))
    ability:SetHidden(false)
    ability:EndCooldown()

    hero.osc_current_ability = entry.name

    if notify then
        OSC_Abilities.Notify(hero, entry)
    end

    return entry
end

function OSC_Abilities.AnnounceWarning(seconds)
    if not OSC_CONFIG.CHAT_MESSAGES then return end
    GameRules:SendCustomMessage(
        "<font color='#FF8C00'>Смена способностей через " .. seconds .. " сек!</font>", 0, 0)
end

function OSC_Abilities.AnnounceRotation()
    if not OSC_CONFIG.CHAT_MESSAGES then return end
    GameRules:SendCustomMessage(
        "<font color='#FFD700'>ХАОС! Все получили новые способности!</font>", 0, 0)
end

function OSC_Abilities.Notify(hero, entry)
    local fx = ParticleManager:CreateParticle(
        "particles/generic_hero_status/hero_levelup.vpcf", PATTACH_ABSORIGIN_FOLLOW, hero)
    ParticleManager:ReleaseParticleIndex(fx)

    local player = PlayerResource:GetPlayer(hero:GetPlayerOwnerID())
    if not player then return end

    CustomGameEventManager:Send_ServerToPlayer(player, "osc_ability_changed", {
        ability = entry.name,
        label   = entry.label,
    })

    if OSC_CONFIG.CHAT_MESSAGES then
        Say(player, "Моя способность: " .. entry.label, true)
    end
end