require("osc/core/client_commands")
require("osc/core/util")

OSC_TeamShuffle = OSC_TeamShuffle or {}
local TeamShuffle = OSC_TeamShuffle

-- Команды, между которыми мешаем
local TEAMS = { DOTA_TEAM_GOODGUYS, DOTA_TEAM_BADGUYS }

local function IsHost(cmd)
  return GameRules:PlayerHasCustomGameHostPrivileges(cmd.player)
end

local function IsSetup()
  return GameRules:State_Get() == DOTA_GAMERULES_STATE_CUSTOM_GAME_SETUP
end

function TeamShuffle:OnShuffle(event)
  if not IsSetup() then return end
  local ok, cmd = OSC_ClientCommands.Check(nil, event)
  if not ok or not IsHost(cmd) then return end

  local ids = {}
  OSC_Util.ForEachPlayerID(function(id) table.insert(ids, id) end)

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

  local ok, cmd = OSC_ClientCommands.Check(nil, event, {
    args = {
      { name = "player_id", check = OSC_ClientCommands.PlayerID() },
      { name = "team", check = OSC_ClientCommands.Integer({ one_of = TEAMS }) },
    },
  })
  if not ok then return end
  local target, team = cmd.args.player_id, cmd.args.team

  -- Себя может двигать любой, других — только хост
  if target ~= cmd.player_id and not IsHost(cmd) then return end
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