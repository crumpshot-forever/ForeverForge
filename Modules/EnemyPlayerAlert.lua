--[[
  Enemy Player Alert. When an enemy player enters detection range, play a
  short sound and post one local chat line:

    Crump Crump - 20 human mage detected!

  The same character is not announced again for 1 minute. There is no cap
  on how many enemies can be listed. A guild name is added in angle
  brackets when it can be read. Range is nameplates, target, focus,
  mouseover, and arena. This client hides the combat log from addons, and
  the nameplate-added event often does not fire, so nameplate1-40 are
  polled. Soft-target units and nameplate settings are left alone.
  Nameplate settings are left alone. The client blocks addons from changing them.

  Secret names, races, classes, levels, and combat-log fields are skipped.
  Nothing is sent to public chat.
]]

local FTK = ForeverToolkit
if not FTK then
  error("ForeverToolkit: Core.lua must load before Modules/EnemyPlayerAlert.lua")
end

local MODULE_ID = "EnemyPlayerAlert"
local WINDOW = 60
local SOUND_GAP = 1.5

local announced = {}
local lastSound = 0
local rescanToken = 0

local function IsSecret(value)
  if value == nil or not issecretvalue then
    return false
  end
  local ok, secret = pcall(issecretvalue, value)
  return ok and secret == true
end

local function PlainNumber(value)
  if type(value) ~= "number" or IsSecret(value) then
    return nil
  end
  local ok, valid = pcall(function()
    return value == value
  end)
  if not ok or valid ~= true then
    return nil
  end
  return value
end

local function PlainString(value)
  if IsSecret(value) or type(value) ~= "string" or value == "" then
    return nil
  end
  return value
end

local function Now()
  if not GetTime then
    return 0
  end
  local ok, value = pcall(GetTime)
  if not ok then
    return 0
  end
  return PlainNumber(value) or 0
end

local function Lower(text)
  local ok, value = pcall(string.lower, text)
  if ok and type(value) == "string" and not IsSecret(value) then
    return value
  end
  return text
end

local function Prune(now)
  local key, when
  for key, when in pairs(announced) do
    if now - when >= WINDOW then
      announced[key] = nil
    end
  end
end

local function OldestWait(now)
  local wait = nil
  local _, when
  for _, when in pairs(announced) do
    local remain = WINDOW - (now - when)
    if remain > 0 and (not wait or remain < wait) then
      wait = remain
    end
  end
  return wait
end

local function PlayId(id)
  if type(id) ~= "number" or not PlaySound then
    return false
  end
  local ok, played = pcall(PlaySound, id, "Master")
  return ok and played ~= false
end

local function PlayCue()
  local now = Now()
  if lastSound > 0 and now - lastSound < SOUND_GAP then
    return
  end
  lastSound = now
  if SOUNDKIT and PlayId(SOUNDKIT.MAP_PING) then
    return
  end
  if PlayId(3175) then
    return
  end
  PlayId(8960)
end

local function PostLine(line)
  FTK:Print(line)
end

local function FlagTrue(fn, ...)
  if type(fn) ~= "function" then
    return false
  end
  local ok, value = pcall(fn, ...)
  if not ok or IsSecret(value) then
    return false
  end
  return value == true
end

local function UnitHere(unit)
  if IsSecret(unit) or type(unit) ~= "string" or not UnitExists then
    return false
  end
  return FlagTrue(UnitExists, unit)
end

local function PlainFaction(unit)
  if not UnitFactionGroup then
    return nil
  end
  local ok, faction = pcall(UnitFactionGroup, unit)
  if not ok then
    return nil
  end
  return PlainString(faction)
end

-- Opposite faction is the useful test. Attack checks are often secret, or
-- false for an unflagged enemy. An enemy nameplate is still worth announcing
-- when faction cannot be read, unless the unit is definitely friendly.
local function IsEnemyPlayer(unit, fromPlate)
  if not UnitHere(unit) then
    return false
  end
  if not FlagTrue(UnitIsPlayer, unit) then
    return false
  end
  if FlagTrue(UnitIsUnit, unit, "player") then
    return false
  end
  if FlagTrue(UnitIsDeadOrGhost, unit) then
    return false
  end
  if FlagTrue(UnitIsFriend, "player", unit) then
    return false
  end
  local mine = PlainFaction("player")
  local theirs = PlainFaction(unit)
  if mine and theirs then
    return mine ~= theirs
  end
  if FlagTrue(UnitIsEnemy, "player", unit) or FlagTrue(UnitCanAttack, "player", unit) then
    return true
  end
  return fromPlate == true
end

local function PlainGUID(unit)
  if not UnitGUID then
    return nil
  end
  local ok, guid = pcall(UnitGUID, unit)
  if not ok then
    return nil
  end
  return PlainString(guid)
end

local function ReadIdentity(unit)
  if not UnitName or not UnitRace or not UnitClass then
    return nil
  end
  local nameOk, name, realm = pcall(UnitName, unit)
  if not nameOk then
    return nil
  end
  name = PlainString(name)
  realm = PlainString(realm)
  if not name then
    return nil
  end
  local raceOk, race = pcall(UnitRace, unit)
  if not raceOk then
    return nil
  end
  race = PlainString(race)
  local classOk, className = pcall(UnitClass, unit)
  if not classOk then
    return nil
  end
  className = PlainString(className)
  if not race or not className then
    return nil
  end
  local level = nil
  if UnitLevel then
    local levelOk, value = pcall(UnitLevel, unit)
    if levelOk then
      value = PlainNumber(value)
      if value and value >= 1 then
        level = value
      end
    end
  end
  local guild = nil
  if GetGuildInfo then
    local guildOk, guildName = pcall(GetGuildInfo, unit)
    if guildOk then
      guild = PlainString(guildName)
    end
  end
  local key = realm and (name .. "-" .. realm) or name
  return {
    key = key,
    name = name,
    guild = guild,
    race = Lower(race),
    className = Lower(className),
    level = level,
  }
end

local function AlertLine(info)
  local who = info.name
  if info.guild then
    who = who .. " <" .. info.guild .. ">"
  end
  if info.level then
    return who .. " - " .. info.level .. " " .. info.race .. " " .. info.className .. " detected!"
  end
  return who .. " - " .. info.race .. " " .. info.className .. " detected!"
end

local ScanKnown

local function ScheduleRescan()
  local wait = OldestWait(Now())
  if not wait or not (C_Timer and C_Timer.After) then
    return
  end
  rescanToken = rescanToken + 1
  local token = rescanToken
  C_Timer.After(wait + 0.1, function()
    if token ~= rescanToken or not FTK:IsEnabled(MODULE_ID) then
      return
    end
    Prune(Now())
    ScanKnown()
  end)
end

local function Consider(unit, attempt, expectedGuid, fromPlate)
  if not FTK:IsEnabled(MODULE_ID) then
    return
  end
  if not UnitHere(unit) then
    return
  end
  local guid = PlainGUID(unit)
  if expectedGuid and guid and guid ~= expectedGuid then
    return
  end
  if not IsEnemyPlayer(unit, fromPlate) then
    return
  end
  local info = ReadIdentity(unit)
  if not info then
    local nextAttempt = (attempt or 0) + 1
    if nextAttempt <= 3 and C_Timer and C_Timer.After then
      local watch = guid or expectedGuid
      C_Timer.After(0.25, function()
        Consider(unit, nextAttempt, watch, fromPlate)
      end)
    end
    return
  end
  local now = Now()
  Prune(now)
  local previous = announced[info.key]
  if previous and now - previous < WINDOW then
    return
  end
  announced[info.key] = now
  PlayCue()
  PostLine(AlertLine(info))
  ScheduleRescan()
end

ScanKnown = function()
  Consider("target", 0, nil, false)
  Consider("focus", 0, nil, false)
  Consider("mouseover", 0, nil, false)
  local index
  for index = 1, 5 do
    Consider("arena" .. index, 0, nil, false)
  end
  for index = 1, 40 do
    Consider("nameplate" .. index, 0, nil, true)
  end
end

local poll = CreateFrame("Frame")
local pollWait = 0
poll:Hide()
poll:SetScript("OnUpdate", function(_, elapsed)
  if not FTK:IsEnabled(MODULE_ID) then
    return
  end
  pollWait = pollWait + (PlainNumber(elapsed) or 0)
  if pollWait < 1 then
    return
  end
  pollWait = 0
  ScanKnown()
end)

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, unit)
  if not FTK:IsEnabled(MODULE_ID) then
    return
  end
  if event == "NAME_PLATE_UNIT_ADDED" then
    Consider(unit, 0, nil, true)
    return
  end
  if event == "UPDATE_MOUSEOVER_UNIT" then
    Consider("mouseover", 0, nil, false)
    return
  end
  if event == "PLAYER_TARGET_CHANGED" then
    Consider("target", 0, nil, false)
    return
  end
  if event == "PLAYER_FOCUS_CHANGED" then
    Consider("focus", 0, nil, false)
    return
  end
  if event == "ARENA_OPPONENT_UPDATE" then
    local index
    for index = 1, 5 do
      Consider("arena" .. index, 0, nil, false)
    end
    return
  end
  if event == "PLAYER_ENTERING_WORLD" then
    ScanKnown()
  end
end)

local function EnableEvents()
  local names = {
    "NAME_PLATE_UNIT_ADDED",
    "UPDATE_MOUSEOVER_UNIT",
    "PLAYER_TARGET_CHANGED",
    "PLAYER_FOCUS_CHANGED",
    "ARENA_OPPONENT_UPDATE",
    "PLAYER_ENTERING_WORLD",
  }
  local index
  for index = 1, #names do
    pcall(events.RegisterEvent, events, names[index])
  end
end

FTK:RegisterModule({
  id = MODULE_ID,
  name = "Enemy Player Alert",
  description = "Plays a short sound and posts a local line when an enemy player is detected. The same character is skipped for 1 minute. A guild name is included when it can be read.",
  defaultEnabled = true,
  onEnable = function()
    EnableEvents()
    pollWait = 0
    poll:Show()
    ScanKnown()
  end,
  onDisable = function()
    events:UnregisterAllEvents()
    poll:Hide()
    rescanToken = rescanToken + 1
  end,
})
