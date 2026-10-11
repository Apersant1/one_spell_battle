OSC_Abilities = {}

local function IsInnateAbility(ability)
    local abilityData = GetAbilityKeyValuesByName(ability:GetAbilityName())
    return abilityData and (
        abilityData.Innate == "1"
        or abilityData.Innate == 1
        or abilityData.Innate == true
    )
end

local function ShouldKeep(ability)
    local name = ability:GetAbilityName()
    if OSC_KEEP_ABILITIES[name] then
        return true
    end
    if string.sub(name, 1, 14) == "special_bonus_" then
        return true
    end
    return IsInnateAbility(ability)
end

local SCEPTER_ABILITY = "ogre_magi_unrefined_fireblast"

local function GetCompanionNamesFromPool(abilityName)
    for _, pool in ipairs({ OSC_ABILITY_POOL, OSC_ULTIMATE_POOL }) do
        for _, entry in ipairs(pool) do
            if entry and entry.name == abilityName and entry.companions then
                return entry.companions
            end
        end
    end
    return {}
end

local function ApplyCompanionAbilities(hero, abilityName)
    local companionNames = GetCompanionNamesFromPool(abilityName)
    local nextIndex = 6
    for _, companionName in ipairs(companionNames) do
        local companion = hero:FindAbilityByName(companionName)
        if not companion then
            companion = hero:AddAbility(companionName)
        end
        if companion then
            companion:SetAbilityIndex(nextIndex)
            companion:SetLevel(1)
            companion:SetHidden(true)
            nextIndex = nextIndex + 1
        end
    end
end

local function RemoveCompanionAbilities(hero, abilityName)
    local companionNames = GetCompanionNamesFromPool(abilityName)
    for _, companionName in ipairs(companionNames) do
        local companion = hero:FindAbilityByName(companionName)
        if companion then
            local ok, err = pcall(function()
                if companion:IsChanneling() then
                    hero:InterruptChannel()
                end
                if companion:IsToggle() and companion:GetToggleState() then
                    companion:ToggleAbility()
                end
                local modifierName = companion:GetIntrinsicModifierName()
                if modifierName and modifierName ~= "" then
                    hero:RemoveModifierByName(modifierName)
                end
                hero:RemoveAbilityByHandle(companion)
            end)
            if not ok then
                OSC_Logger.Error("Failed to remove companion ability " .. tostring(companionName) .. ": " .. tostring(err))
            end
        end
    end
end

local function SafeRemoveAbility(hero, ability)
    if not hero or not ability or ability:IsNull() then
        return
    end

    local ok, err = pcall(function()
        if ability:IsChanneling() then
            hero:InterruptChannel()
        end
        if ability:IsToggle() and ability:GetToggleState() then
            ability:ToggleAbility()
        end
        local modifierName = ability:GetIntrinsicModifierName()
        if modifierName and modifierName ~= "" then
            hero:RemoveModifierByName(modifierName)
        end
        hero:RemoveAbilityByHandle(ability)
    end)

    if not ok then
        OSC_Logger.Error("Failed to remove ability " .. tostring(ability:GetAbilityName()) .. ": " .. tostring(err))
    end
end

local function PreserveScepterAbilitySlot(hero, preferredIndex)
    local scepterAbility = hero:FindAbilityByName(SCEPTER_ABILITY)
    if not scepterAbility or hero:GetAbilityByIndex(preferredIndex) ~= scepterAbility then
        return
    end

    local lastVisibleIndex = math.min(hero:GetAbilityCount() - 1, 5)
    for index = 0, lastVisibleIndex do
        if index ~= preferredIndex and not hero:GetAbilityByIndex(index) then
            scepterAbility:SetAbilityIndex(index)
            return
        end
    end

    error("[OSC] No free ability slot to preserve " .. SCEPTER_ABILITY)
end

function OSC_Abilities.StripHero(hero)
    local toRemove = {}
    for i = 0, hero:GetAbilityCount() - 1 do
        local ability = hero:GetAbilityByIndex(i)
        if ability and not ShouldKeep(ability) then
            table.insert(toRemove, ability)
        end
    end

    for i = #toRemove, 1, -1 do
        local ability = toRemove[i]
        if ability and not ability:IsNull() then
            local abilityName = ability:GetAbilityName()
            RemoveCompanionAbilities(hero, abilityName)
            SafeRemoveAbility(hero, ability)
        end
    end
end

function OSC_Abilities.EnsureOgreCasinoAbility(hero)
    if hero:GetUnitName() ~= "npc_dota_hero_ogre_magi" then return end

    local ability = hero:FindAbilityByName("ogre_magi_casino")
    if not ability then
        ability = hero:AddAbility("ogre_magi_casino")
    end
    if not ability then
        error("[OSC] Failed to add Ogre casino ability")
    end

    ability:SetAbilityIndex(1)
    ability:SetLevel(1)
    ability:SetHidden(false)
end

local function PickRandomFromPool(pool, excludeName, isAllowed)
    local function GetWeight(entry)
        local weight = entry.weight == nil and 4 or entry.weight
        if type(weight) ~= "number" or weight <= 0 or weight ~= math.floor(weight) then
            error("[OSC] Invalid weight for ability: " .. tostring(entry and entry.name))
        end
        return weight
    end

    local candidates = {}
    for _, entry in ipairs(pool) do
        if entry and entry.name ~= excludeName and (not isAllowed or isAllowed(entry)) then
            table.insert(candidates, entry)
        end
    end

    if #candidates == 0 and isAllowed then
        OSC_Logger.Error("Ability pool filter exhausted, ignoring duplicate limit for exclusion='" .. tostring(excludeName) .. "'")
        candidates = {}
        for _, entry in ipairs(pool) do
            if entry and entry.name ~= excludeName then
                table.insert(candidates, entry)
            end
        end
    end

    if #candidates == 0 then
        candidates = {}
        for _, entry in ipairs(pool) do
            if entry and entry.name ~= excludeName then
                table.insert(candidates, entry)
            end
        end
    end

    if #candidates == 0 then
        OSC_Logger.Error("Ability pool is empty after filtering")
        return nil
    end

    local totalWeight = 0
    for _, entry in ipairs(candidates) do
        totalWeight = totalWeight + GetWeight(entry)
    end

    local roll = RandomInt(1, totalWeight)
    for _, entry in ipairs(candidates) do
        roll = roll - GetWeight(entry)
        if roll <= 0 then
            return entry
        end
    end

    return candidates[#candidates]
end

function OSC_Abilities.PickRandom(excludeName)
    return PickRandomFromPool(OSC_ABILITY_POOL, excludeName)
end

local function GetAlliedUltimateCount(hero, abilityName)
    local count = 0
    local team = hero:GetTeamNumber()

    for playerID = 0, DOTA_MAX_TEAM_PLAYERS - 1 do
        if PlayerResource:IsValidPlayerID(playerID) then
            local teammate = PlayerResource:GetSelectedHeroEntity(playerID)
            if teammate and teammate ~= hero and teammate:GetTeamNumber() == team
                and teammate.osc_current_ultimate == abilityName then
                count = count + 1
            end
        end
    end

    return count
end

function OSC_Abilities.PickRandomUltimate(excludeName, hero)
    local maxDuplicates = OSC_CONFIG.MAX_DUPLICATE_ULTIMATES_PER_TEAM
    if type(maxDuplicates) ~= "number" or maxDuplicates < 1 then
        error("[OSC] MAX_DUPLICATE_ULTIMATES_PER_TEAM must be at least 1")
    end

    return PickRandomFromPool(OSC_ULTIMATE_POOL, excludeName, function(entry)
        return GetAlliedUltimateCount(hero, entry.name) < maxDuplicates
    end)
end

function OSC_Abilities.CopyFromOwner(unit, owner)
    OSC_Abilities.StripHero(unit)

    local name = owner.osc_current_ability
    if not name then return end

    local source = owner:FindAbilityByName(name)
    PreserveScepterAbilitySlot(unit, 0)
    local ability = unit:AddAbility(name)
    if ability then
        ability:SetLevel(source and source:GetLevel() or 1)
        ability:SetAbilityIndex(0)
        ability:SetHidden(false)
        ApplyCompanionAbilities(unit, name)
    end

    unit.osc_current_ability = name

    local ultimateName = owner.osc_current_ultimate
    unit.osc_current_ultimate = nil
    if ultimateName then
        local sourceUltimate = owner:FindAbilityByName(ultimateName)
        PreserveScepterAbilitySlot(unit, 5)
        local ultimate = unit:AddAbility(ultimateName)
        if ultimate then
            ultimate:SetLevel(sourceUltimate and sourceUltimate:GetLevel() or 1)
            ultimate:SetAbilityIndex(5)
            ultimate:SetHidden(false)
            ApplyCompanionAbilities(unit, ultimateName)
            unit.osc_current_ultimate = ultimateName
        else
            OSC_Logger.Error("Failed to copy ultimate: " .. ultimateName)
        end
    end
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
        RemoveCompanionAbilities(hero, oldName)
        SafeRemoveAbility(hero, old)
    end
end

function OSC_Abilities.GiveRandomUltimate(hero, notify)
    local oldName = hero.osc_current_ultimate
    local entry = OSC_Abilities.PickRandomUltimate(oldName, hero)
    if not entry then
        return nil
    end

    PreserveScepterAbilitySlot(hero, 5)
    local ability = hero:AddAbility(entry.name)
    if not ability then
        OSC_Logger.Error("Failed to add ultimate: " .. entry.name)
        return nil
    end

    local old = oldName and hero:FindAbilityByName(oldName)
    if old and old ~= ability then
        RemoveCompanionAbilities(hero, oldName)
        SafeRemoveAbility(hero, old)
    end

    ability:SetAbilityIndex(5)
    ability:SetLevel(OSC_Abilities.CalcLevel(hero:GetLevel(), ability))
    ability:SetHidden(false)
    ability:EndCooldown()
    ApplyCompanionAbilities(hero, entry.name)
    hero.osc_current_ultimate = entry.name

    if notify then
        OSC_Notifications.AbilityChanged(hero, entry)
    end

    return entry
end

function OSC_Abilities.GiveRandom(hero, notify)
    local oldName = hero.osc_current_ability
    local entry = OSC_Abilities.PickRandom(oldName)
    if not entry then
        return nil
    end

    PreserveScepterAbilitySlot(hero, 0)
    local ability = hero:AddAbility(entry.name)
    if not ability then
        OSC_Logger.Error("Failed to add ability: " .. entry.name)
        return nil
    end

    local old = oldName and hero:FindAbilityByName(oldName)
    if old and old ~= ability then
        RemoveCompanionAbilities(hero, oldName)
        SafeRemoveAbility(hero, old)
    end

    ability:SetLevel(OSC_Abilities.CalcLevel(hero:GetLevel(), ability))
    ability:SetAbilityIndex(0)
    ability:SetHidden(false)
    ability:EndCooldown()
    ApplyCompanionAbilities(hero, entry.name)
    hero.osc_current_ability = entry.name

    if notify then
        OSC_Notifications.AbilityChanged(hero, entry)
    end

    return entry
end
