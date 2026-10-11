OSC_TeamShuffle = OSC_TeamShuffle or {}
local TeamShuffle = OSC_TeamShuffle

-- Команды, между которыми мешаем. Добавьте DOTA_TEAM_CUSTOM_*, если используете больше двух.
local TEAMS = { DOTA_TEAM_GOODGUYS, DOTA_TEAM_BADGUYS }

local function IsHost(playerID)
  local player = PlayerResource:GetPlayer(playerID)
  return player ~= nil and GameRules:PlayerHasCustomGameHostPrivileges(player)
end

function OSC_TeamShuffle:OnShuffle(event)
  if GameRules:State_Get() ~= DOTA_GAMERULES_STATE_CUSTOM_GAME_SETUP then return end
  if not IsHost(event.PlayerID) then return end

  local ids = {}
  for id = 0, DOTA_MAX_TEAM_PLAYERS - 1 do
    if PlayerResource:IsValidPlayerID(id) then table.insert(ids, id) end
  end

  -- Перемешивание Фишера–Йетса
  for i = #ids, 2, -1 do
    local j = RandomInt(1, i)
    ids[i], ids[j] = ids[j], ids[i]
  end

  -- Раскладываем по очереди, не превышая лимит команды
  local counts = {}
  for i, id in ipairs(ids) do
    for k = 0, #TEAMS - 1 do
      local team = TEAMS[((i - 1 + k) % #TEAMS) + 1]
      counts[team] = counts[team] or 0
      if counts[team] < GameRules:GetCustomGameTeamMaxPlayers(team) then
        PlayerResource:SetCustomTeamAssignment(id, team)
        counts[team] = counts[team] + 1
        break
      end
    end
  end
end

function OSC_TeamShuffle:Init()
  CustomGameEventManager:RegisterListener("osc_team_shuffle", function(_, event)
    self:OnShuffle(event)
  end)
end

return TeamShuffle