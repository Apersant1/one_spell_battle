OSC_TeamShuffle = OSC_TeamShuffle or {}
local TeamShuffle = OSC_TeamShuffle

-- Команды, между которыми мешаем
local TEAMS = { DOTA_TEAM_GOODGUYS, DOTA_TEAM_BADGUYS }

local function IsHost(playerID)
  local player = PlayerResource:GetPlayer(playerID)
  return player ~= nil and GameRules:PlayerHasCustomGameHostPrivileges(player)
end

local function IsPlayableTeam(team)
  for _, playable in ipairs(TEAMS) do
    if playable == team then return true end
  end
  return false
end

local function IsSetup()
  return GameRules:State_Get() == DOTA_GAMERULES_STATE_CUSTOM_GAME_SETUP
end

function TeamShuffle:OnShuffle(event)
  if not IsSetup() or not IsHost(event.PlayerID) then return end

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

-- Хост перетаскивает игрока в команду
function TeamShuffle:OnMove(event)
  if not IsSetup() then return end

  local target = tonumber(event.player_id)
  local team = tonumber(event.team)
  if target == nil or not IsPlayableTeam(team) then return end

  -- Себя может двигать любой, других — только хост
  if target ~= event.PlayerID and not IsHost(event.PlayerID) then return end
  if not PlayerResource:IsValidPlayerID(target) then return end
  if PlayerResource:GetCustomTeamAssignment(target) == team then return end
  if PlayerResource:GetPlayerCountForTeam(team) >= GameRules:GetCustomGameTeamMaxPlayers(team) then return end

  PlayerResource:SetCustomTeamAssignment(target, team)
end

function TeamShuffle:Init()
  CustomGameEventManager:RegisterListener("osc_team_shuffle", function(_, event)
    self:OnShuffle(event)
  end)
  CustomGameEventManager:RegisterListener("osc_team_move", function(_, event)
    self:OnMove(event)
  end)
end

return TeamShuffle