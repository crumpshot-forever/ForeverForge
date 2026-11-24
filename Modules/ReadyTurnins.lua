--[[
  Ready Turn-ins. Lists quests in the log that are ready to hand in,
  grouped by zone, with the NPC the quest text names.

  This client drops a quest's objective rows once it is ready to turn in,
  and it has no turn-in NPC field. The zone is the quest log header above
  the quest. The NPC is read from the quest text ("Return to Name at
  Place", including instructions buried in a sentence). When Questie is
  installed, its turn-in NPC and that NPC's zone fill anything still blank.

  A chat line fires only when a quest we already saw in progress becomes
  ready. Quests that are already ready the first time we see them stay quiet,
  so login does not dump the whole log into chat.
]]

local FTK = ForeverForge
if not FTK then
  error("ForeverForge: Core.lua must load before Modules/ReadyTurnins.lua")
end

local MODULE_ID = "ReadyTurnins"
local UNKNOWN_ZONE = "Zone unknown"

local frame = CreateFrame("Frame")
local window
local state = {}
local scanPending = false
local Scan
local ScrollBy

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

local function IsFlag(value)
  if IsSecret(value) then
    return false
  end
  return value == true or value == 1
end

local function Config()
  return FTK:GetConfig(MODULE_ID)
end

local function FilterMode()
  local mode = Config().filter
  if mode == "here" or mode == "away" then
    return mode
  end
  return "all"
end

local function ChatOn()
  return Config().chat ~= false
end

local function Trim(text)
  return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function StripMarkup(text)
  text = tostring(text or "")
  text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
  text = text:gsub("|r", "")
  text = text:gsub("|n", " ")
  text = text:gsub("|H.-|h(.-)|h", "%1")
  text = text:gsub("|T.-|t", "")
  return text
end

local function StripCount(text)
  text = StripMarkup(text)
  text = text:gsub("%s*:%s*%d+%s*/%s*%d+%s*$", "")
  text = text:gsub("%s*%(%d+%s*/%s*%d+%)%s*$", "")
  return Trim(text)
end

local function CleanName(text)
  text = Trim(text or "")
  text = text:gsub("%.$", "")
  text = Trim(text)
  if text == "" then
    return nil
  end
  return text
end

local function LooksLikeKill(text)
  local lower = text:lower()
  return lower:find("slain", 1, true)
    or lower:find("killed", 1, true)
    or lower:find("destroyed", 1, true)
    or lower:find("visited", 1, true)
end

-- "the Hinterlands" is the zone "The Hinterlands".
local function TitleZone(name)
  if type(name) ~= "string" then
    return nil
  end
  if name:lower():sub(1, 4) == "the " then
    return "The " .. name:sub(5)
  end
  return name
end

local function CutSentence(text)
  text = Trim(text or "")
  local cut = text:match("^(.-)[%.%!%?]")
  if cut and Trim(cut) ~= "" then
    text = cut
  end
  cut = text:match("^(.-)[\r\n]")
  if cut and Trim(cut) ~= "" then
    text = cut
  end
  return Trim(text)
end

local function WordCount(text)
  local count = 0
  for _ in tostring(text or ""):gmatch("%S+") do
    count = count + 1
  end
  return count
end

-- "Name at Town in the Zone" -> Name, Town, The Zone.
local function SplitNpcPlace(rest)
  rest = CutSentence(rest)
  if rest == "" or LooksLikeKill(rest) then
    return nil, nil, nil
  end
  local npc, loc = rest:match("^(.-)%s+[Aa]t%s+(.+)$")
  if not npc then
    npc, loc = rest:match("^(.-)%s+[Ii]n%s+(.+)$")
  end
  if not npc then
    npc = rest
  end
  npc = CleanName(npc)
  if not npc or npc:find("%d") or WordCount(npc) > 7 then
    return nil, nil, nil
  end
  local place, region
  if loc then
    loc = CutSentence(loc)
    local town, area = loc:match("^(.-)%s+[Ii]n%s+(.+)$")
    if town then
      place = TitleZone(CleanName(town))
      region = TitleZone(CleanName(area))
    else
      place = TitleZone(CleanName(loc))
    end
  end
  return npc, place, region
end

-- The hand-in is usually the last "return / report / bring to" in the text,
-- not the first words. Completed quests keep that sentence in the quest
-- text after the objective rows are gone.
local VERB_PATTERNS = {
  "[Rr]eturn to%s+",
  "[Rr]eport to%s+",
  "[Ss]peak with%s+",
  "[Ss]peak to%s+",
  "[Tt]alk with%s+",
  "[Tt]alk to%s+",
  "[Mm]eet with%s+",
  "[Dd]eliver%s+.-%s+to%s+",
  "[Bb]ring%s+.-%s+to%s+",
  "[Gg]ive%s+.-%s+to%s+",
  "[Rr]eturn%s+.-%s+to%s+",
}

local function LastVerbRest(text)
  local bestAt = 0
  local bestRest
  local index
  for index = 1, #VERB_PATTERNS do
    local pattern = VERB_PATTERNS[index] .. "(.+)"
    local from = 1
    while from <= #text do
      local startAt, _, rest = text:find(pattern, from)
      if not startAt then
        break
      end
      if startAt >= bestAt and type(rest) == "string" and rest ~= "" then
        bestAt = startAt
        bestRest = rest
      end
      from = startAt + 1
    end
  end
  return bestRest
end

-- Returns the NPC, a town when the sentence names one, and a region.
local function ParseTurnIn(text)
  text = StripCount(text or "")
  if text == "" then
    return nil, nil, nil
  end
  local rest = LastVerbRest(text)
  if rest then
    local npc, place, region = SplitNpcPlace(rest)
    if npc then
      return npc, place, region
    end
  end
  if not text:find("[\r\n]") and LooksLikeKill(text) then
    return nil, nil, nil
  end
  local spoken = text:match("^(.+)%s+[Ss]poken to$")
  if spoken then
    return CleanName(spoken), nil, nil
  end
  return nil, nil, nil
end

-- Waypoint text is sometimes only the NPC, with no "Return to".
local function BareNpcName(text, title)
  text = StripCount(text or "")
  if text == "" or LooksLikeKill(text) then
    return nil
  end
  if #text > 60 or text:find("%d") or text:find("%.") or text:find("!") then
    return nil
  end
  local lower = text:lower()
  if lower:find("collected", 1, true) or lower:find(" quest", 1, true) then
    return nil
  end
  if type(title) == "string" and lower == title:lower() then
    return nil
  end
  if lower:find("^return") or lower:find("^speak") or lower:find("^talk") or lower:find("^report") then
    return nil
  end
  if lower:find("^go ") or lower:find("^head ") or lower:find("^find ") or lower:find("^kill ") or lower:find("^slay ") or lower:find("^collect ") or lower:find("^gather ") or lower:find("^search ") or lower:find("^use ") then
    return nil
  end
  local words = 0
  for _ in text:gmatch("%S+") do
    words = words + 1
  end
  if words > 6 then
    return nil
  end
  return text
end

local function ResolveTurnIn(waypointText, lines, mapZone, title)
  local npc, place, region = ParseTurnIn(waypointText or "")
  if not npc then
    npc = BareNpcName(waypointText or "", title)
  end
  if type(lines) == "table" then
    local index
    for index = 1, #lines do
      if type(lines[index]) == "string" then
        local lineNpc, linePlace, lineRegion = ParseTurnIn(lines[index])
        if not npc and lineNpc then
          npc = lineNpc
        end
        if not place and linePlace then
          place = linePlace
        end
        if not region and lineRegion then
          region = lineRegion
        end
      end
    end
  end
  if npc and type(mapZone) == "string" and npc:lower() == mapZone:lower() then
    npc = nil
  end
  local zone = mapZone
  if type(zone) ~= "string" or zone == "" then
    zone = region
  end
  if type(zone) ~= "string" or zone == "" then
    zone = place
  end
  if type(zone) == "string" then
    zone = TitleZone(zone)
  end
  return npc, zone, place
end

local function NameMatch(a, b)
  if type(a) ~= "string" or type(b) ~= "string" then
    return false
  end
  a = a:lower()
  b = b:lower()
  if a == "" or b == "" then
    return false
  end
  if a == b then
    return true
  end
  local short, long = a, b
  if #a > #b then
    short, long = b, a
  end
  if #short < 6 then
    return false
  end
  return long:find(short, 1, true) ~= nil
end

local function ZonesMatch(quest, player)
  if type(quest) ~= "table" or type(player) ~= "table" then
    return false
  end
  if quest.mapID and player.mapID and quest.mapID == player.mapID then
    return true
  end
  if NameMatch(quest.zone, player.zone) or NameMatch(quest.place, player.zone) then
    return true
  end
  if NameMatch(quest.place, player.subzone) or NameMatch(quest.zone, player.subzone) then
    return true
  end
  return false
end

local function FilterQuests(quests, mode, player)
  if mode ~= "here" and mode ~= "away" then
    return quests, "all"
  end
  local known = false
  if type(player) == "table" then
    if player.mapID then
      known = true
    elseif type(player.zone) == "string" and player.zone ~= "" then
      known = true
    end
  end
  if not known then
    return quests, "unknown"
  end
  local out = {}
  local index
  for index = 1, #quests do
    local same = ZonesMatch(quests[index], player)
    if (mode == "here" and same) or (mode == "away" and not same) then
      out[#out + 1] = quests[index]
    end
  end
  return out, mode
end

local function GroupQuests(quests)
  local buckets = {}
  local order = {}
  local index
  for index = 1, #quests do
    local quest = quests[index]
    local zone = quest.zone
    if type(zone) ~= "string" or zone == "" then
      zone = UNKNOWN_ZONE
    end
    local bucket = buckets[zone]
    if not bucket then
      bucket = { zone = zone, quests = {} }
      buckets[zone] = bucket
      order[#order + 1] = bucket
    end
    bucket.quests[#bucket.quests + 1] = quest
  end
  table.sort(order, function(a, b)
    if a.zone == UNKNOWN_ZONE then
      return false
    end
    if b.zone == UNKNOWN_ZONE then
      return true
    end
    return a.zone:lower() < b.zone:lower()
  end)
  local group
  for group = 1, #order do
    table.sort(order[group].quests, function(a, b)
      local left = (a.title or ""):lower()
      local right = (b.title or ""):lower()
      if left == right then
        return (a.questID or 0) < (b.questID or 0)
      end
      return left < right
    end)
  end
  return order
end

local function SameLabel(a, b)
  return type(a) == "string" and type(b) == "string" and a:lower() == b:lower()
end

local function ReadyLine(quest)
  local title = quest.title or "Quest"
  local who = quest.npc
  local place = quest.place
  local zone = quest.zone
  if SameLabel(place, zone) then
    place = nil
  end
  local where = place
  if place and zone then
    where = place .. ", " .. zone
  elseif zone then
    where = zone
  end
  if who and where then
    return "Ready: " .. title .. " - " .. who .. ", " .. where .. "."
  end
  if who then
    return "Ready: " .. title .. " - " .. who .. "."
  end
  if where then
    return "Ready: " .. title .. " - " .. where .. "."
  end
  return "Ready: " .. title .. "."
end

local function Summary(shown, total, mode, playerZone)
  if total == 0 then
    return "No quests are ready to turn in."
  end
  if mode == "unknown" then
    return "Current zone is unknown. Showing every ready quest."
  end
  if mode == "here" then
    if shown == 0 then
      if type(playerZone) == "string" and playerZone ~= "" then
        return "No ready turn-ins in " .. playerZone .. "."
      end
      return "No ready turn-ins in this zone."
    end
    if type(playerZone) == "string" and playerZone ~= "" then
      return shown .. " ready in " .. playerZone .. ". Click a quest to track it."
    end
    return shown .. " ready in this zone. Click a quest to track it."
  end
  if mode == "away" then
    if shown == 0 then
      return "No ready turn-ins outside this zone."
    end
    return shown .. " ready outside this zone. Click a quest to track it."
  end
  if shown == 1 then
    return "1 quest is ready. Click a quest to track it."
  end
  return shown .. " quests are ready. Click a quest to track it."
end

-- previous[id] == false means we saw the quest in the log and it was not ready.
-- First sight of an already-ready quest does not announce.
local function Transitions(previous, entries, chatOn)
  local announced = {}
  local nextState = {}
  local index
  for index = 1, #entries do
    local entry = entries[index]
    local questID = entry.questID
    if questID then
      if entry.ready and previous[questID] == false and chatOn then
        announced[#announced + 1] = entry
      end
      nextState[questID] = entry.ready and true or false
    end
  end
  return nextState, announced
end

local function MapType(name, fallback)
  local enums = Enum and Enum.UIMapType
  local value = enums and PlainNumber(enums[name])
  if value then
    return value
  end
  return fallback
end

local function MapRecord(mapID)
  mapID = PlainNumber(mapID)
  if not mapID or mapID < 1 or not (C_Map and type(C_Map.GetMapInfo) == "function") then
    return nil
  end
  local ok, info = pcall(C_Map.GetMapInfo, mapID)
  if not ok or type(info) ~= "table" then
    return nil
  end
  return {
    id = mapID,
    name = PlainString(info.name),
    mapType = PlainNumber(info.mapType),
    parent = PlainNumber(info.parentMapID),
  }
end

-- Walk a waypoint map up to the zone or dungeon it sits in.
local function ZoneFromMap(mapID)
  mapID = PlainNumber(mapID)
  if not mapID or mapID < 1 then
    return nil, nil
  end
  local zoneType = MapType("Zone", 3)
  local dungeonType = MapType("Dungeon", 4)
  local continentType = MapType("Continent", 2)
  local worldType = MapType("World", 1)
  local cosmicType = MapType("Cosmic", 0)
  local seen = {}
  local current = mapID
  local fallbackID
  local fallbackName
  local guard = 0
  while current and current >= 1 and not seen[current] and guard < 8 do
    guard = guard + 1
    seen[current] = true
    local info = MapRecord(current)
    if not info then
      break
    end
    if not fallbackName and info.name then
      fallbackName = info.name
      fallbackID = info.id
    end
    if info.mapType == zoneType or info.mapType == dungeonType then
      return info.id, info.name
    end
    if info.mapType == continentType or info.mapType == worldType or info.mapType == cosmicType then
      break
    end
    current = info.parent
  end
  return fallbackID, fallbackName
end

local function Waypoint(questID)
  local mapID
  local text
  if questID and C_QuestLog and type(C_QuestLog.GetNextWaypoint) == "function" then
    local ok, id = pcall(C_QuestLog.GetNextWaypoint, questID)
    if ok then
      mapID = PlainNumber(id)
    end
  end
  if questID and C_QuestLog and type(C_QuestLog.GetNextWaypointText) == "function" then
    local ok, value = pcall(C_QuestLog.GetNextWaypointText, questID)
    if ok then
      text = PlainString(value)
    end
  end
  return mapID, text
end

local function ObjectiveLines(questID, logIndex)
  local lines = {}
  local function add(text)
    text = PlainString(text)
    if not text then
      return
    end
    local index
    for index = 1, #lines do
      if lines[index] == text then
        return
      end
    end
    lines[#lines + 1] = text
  end
  if questID and C_QuestLog and type(C_QuestLog.GetQuestObjectives) == "function" then
    local ok, objectives = pcall(C_QuestLog.GetQuestObjectives, questID)
    if ok and type(objectives) == "table" then
      local index
      for index = 1, #objectives do
        local row = objectives[index]
        if type(row) == "table" then
          add(row.text)
        else
          add(row)
        end
      end
    end
  end
  if logIndex and type(GetNumQuestLeaderBoards) == "function" and type(GetQuestLogLeaderBoard) == "function" then
    local ok, count = pcall(GetNumQuestLeaderBoards, logIndex)
    count = ok and PlainNumber(count) or 0
    local index
    for index = 1, count do
      local boardOk, text = pcall(GetQuestLogLeaderBoard, index, logIndex)
      if boardOk then
        add(text)
      end
    end
  end
  return lines
end

local function QuestIsReady(questID, classicComplete)
  if PlainNumber(classicComplete) == -1 then
    return false
  end
  if questID and C_QuestLog and type(C_QuestLog.IsFailed) == "function" then
    local ok, failed = pcall(C_QuestLog.IsFailed, questID)
    if ok and (failed == true or failed == 1) then
      return false
    end
  end
  if questID and C_QuestLog and type(C_QuestLog.ReadyForTurnIn) == "function" then
    local ok, value = pcall(C_QuestLog.ReadyForTurnIn, questID)
    if ok and not IsSecret(value) then
      return value == true or value == 1
    end
  end
  if questID and C_QuestLog and type(C_QuestLog.IsComplete) == "function" then
    local ok, value = pcall(C_QuestLog.IsComplete, questID)
    if ok and not IsSecret(value) then
      return value == true or value == 1
    end
  end
  return classicComplete == 1 or classicComplete == true
end

local GENERIC_HEADER = {
  miscellaneous = true,
  misc = true,
  quests = true,
  ["world quests"] = true,
  campaign = true,
  dungeon = true,
  dungeons = true,
  raid = true,
  raids = true,
  class = true,
  professions = true,
  seasonal = true,
  battleground = true,
  battlegrounds = true,
  scenarios = true,
  legendary = true,
}

local function UsefulHeader(name)
  name = PlainString(name)
  if not name then
    return nil
  end
  if GENERIC_HEADER[name:lower()] then
    return nil
  end
  return name
end

-- A log header is the zone the quest is filed under. Use it when we do not
-- already have a real zone. A town we parsed ("Ratchet") stays on the row.
local function ApplyLogHeader(entry, header)
  header = UsefulHeader(header)
  if not header or type(entry) ~= "table" then
    return
  end
  local zone = entry.zone
  local place = entry.place
  if type(zone) == "string" and zone ~= "" and not SameLabel(zone, place) then
    return
  end
  if type(zone) == "string" and zone ~= "" and not SameLabel(zone, header) then
    entry.place = zone
  end
  entry.zone = header
  if SameLabel(entry.place, entry.zone) then
    entry.place = nil
  end
end

local function AreaName(areaID)
  areaID = PlainNumber(areaID)
  if not areaID or areaID < 1 then
    areaID = PlainNumber(tonumber(areaID))
  end
  if not areaID or areaID < 1 or not (C_Map and type(C_Map.GetAreaInfo) == "function") then
    return nil
  end
  local ok, name = pcall(C_Map.GetAreaInfo, areaID)
  if not ok then
    return nil
  end
  return PlainString(name)
end

local function ZoneFromSpawns(spawns)
  if type(spawns) ~= "table" then
    return nil
  end
  local bestID
  local bestCount = -1
  local zoneID, coords
  for zoneID, coords in pairs(spawns) do
    local id = PlainNumber(zoneID)
    if not id then
      id = PlainNumber(tonumber(zoneID))
    end
    local count = 0
    if type(coords) == "table" then
      count = #coords
    end
    if id and id > 0 and count >= bestCount then
      bestID = id
      bestCount = count
    end
  end
  return AreaName(bestID)
end

local function FirstId(list)
  if type(list) ~= "table" then
    return nil
  end
  local id = PlainNumber(list[1])
  if id and id > 0 then
    return id
  end
  return nil
end

-- Questie's database, when that addon is loaded. Completed quests no longer
-- carry a turn-in line in the log, and Questie still knows who accepts them.
local function CatalogTurnIn(questID)
  local db = _G.QuestieDB
  if not questID or type(db) ~= "table" or type(db.QueryQuestSingle) ~= "function" then
    return nil, nil
  end
  local ok, finishedBy = pcall(db.QueryQuestSingle, questID, "finishedBy")
  if not ok or type(finishedBy) ~= "table" then
    return nil, nil
  end
  local name
  local spawns
  local npcID = FirstId(finishedBy[1])
  if npcID and type(db.QueryNPCSingle) == "function" then
    local nameOk, npcName = pcall(db.QueryNPCSingle, npcID, "name")
    local spawnOk, npcSpawns = pcall(db.QueryNPCSingle, npcID, "spawns")
    if nameOk then
      name = PlainString(npcName)
    end
    if spawnOk then
      spawns = npcSpawns
    end
  end
  if not name then
    local objectID = FirstId(finishedBy[2])
    if objectID and type(db.QueryObjectSingle) == "function" then
      local nameOk, objectName = pcall(db.QueryObjectSingle, objectID, "name")
      local spawnOk, objectSpawns = pcall(db.QueryObjectSingle, objectID, "spawns")
      if nameOk then
        name = PlainString(objectName)
      end
      if spawnOk then
        spawns = objectSpawns
      end
    end
  end
  local zone = ZoneFromSpawns(spawns)
  if not zone then
    local zoneOk, zoneOrSort = pcall(db.QueryQuestSingle, questID, "zoneOrSort")
    if zoneOk then
      zone = AreaName(zoneOrSort)
    end
  end
  return name, zone
end

local function AddLine(lines, text)
  text = PlainString(text)
  if not text then
    return
  end
  local index
  for index = 1, #lines do
    if lines[index] == text then
      return
    end
  end
  lines[#lines + 1] = text
end

local function QuestTextLines(logIndex, questID)
  local lines = {}
  if logIndex and type(GetQuestLogQuestText) == "function" then
    local ok, description, objectives = pcall(GetQuestLogQuestText, logIndex)
    if ok then
      AddLine(lines, objectives)
      AddLine(lines, description)
    end
  end
  if logIndex and type(GetQuestLogCompletionText) == "function" then
    local ok, text = pcall(GetQuestLogCompletionText, logIndex)
    if ok then
      AddLine(lines, text)
    end
  end
  local db = _G.QuestieDB
  if questID and type(db) == "table" and type(db.QueryQuestSingle) == "function" then
    local ok, text = pcall(db.QueryQuestSingle, questID, "objectivesText")
    if ok and type(text) == "table" then
      local index
      for index = 1, #text do
        AddLine(lines, text[index])
      end
    elseif ok then
      AddLine(lines, text)
    end
  end
  return lines
end

local function FillTurnIn(entry)
  local wpMap, wpText = Waypoint(entry.questID)
  local zoneMap, zoneName = ZoneFromMap(wpMap)
  local lines = ObjectiveLines(entry.questID, entry.logIndex)
  local extra = QuestTextLines(entry.logIndex, entry.questID)
  local index
  for index = 1, #extra do
    lines[#lines + 1] = extra[index]
  end
  local npc, zone, place = ResolveTurnIn(wpText, lines, zoneName, entry.title)
  local catalogNpc, catalogZone = CatalogTurnIn(entry.questID)
  if catalogNpc then
    npc = catalogNpc
  end
  if catalogZone then
    if zone and not SameLabel(zone, catalogZone) and not place then
      place = zone
    end
    zone = catalogZone
  end
  entry.npc = npc
  entry.zone = zone
  entry.place = place
  entry.mapID = zoneMap
end

local function LogCount()
  if C_QuestLog and type(C_QuestLog.GetNumQuestLogEntries) == "function" then
    local ok, value = pcall(C_QuestLog.GetNumQuestLogEntries)
    if ok then
      local count = PlainNumber(value)
      if count then
        return count
      end
    end
  end
  if type(GetNumQuestLogEntries) == "function" then
    local ok, value = pcall(GetNumQuestLogEntries)
    if ok then
      return PlainNumber(value) or 0
    end
  end
  return 0
end

local function HasCompleteApi()
  return type(C_QuestLog) == "table"
    and (type(C_QuestLog.ReadyForTurnIn) == "function" or type(C_QuestLog.IsComplete) == "function")
end

local function ClassicComplete(index)
  if type(GetQuestLogTitle) ~= "function" then
    return nil
  end
  local ok, _, _, _, isHeader, _, isComplete = pcall(GetQuestLogTitle, index)
  if not ok or IsFlag(isHeader) then
    return nil
  end
  return isComplete
end

local function ReadEntry(index)
  if C_QuestLog and type(C_QuestLog.GetInfo) == "function" then
    local ok, info = pcall(C_QuestLog.GetInfo, index)
    if ok and type(info) == "table" then
      if IsFlag(info.isHeader) or IsFlag(info.isHidden) then
        return nil
      end
      local questID = PlainNumber(info.questID)
      local title = PlainString(info.title)
      if questID and title then
        local ready = QuestIsReady(questID, info.isComplete)
        -- Some logs name the quest but only the older title call says it is done.
        if not ready and info.isComplete == nil and not HasCompleteApi() then
          ready = QuestIsReady(questID, ClassicComplete(index))
        end
        return {
          questID = questID,
          logIndex = PlainNumber(info.questLogIndex) or index,
          title = title,
          ready = ready,
        }
      end
    end
  end
  if type(GetQuestLogTitle) ~= "function" then
    return nil
  end
  local ok, title, _, _, isHeader, _, isComplete, _, questID = pcall(GetQuestLogTitle, index)
  if not ok or IsFlag(isHeader) then
    return nil
  end
  questID = PlainNumber(questID)
  title = PlainString(title)
  if not questID or not title then
    return nil
  end
  return {
    questID = questID,
    logIndex = index,
    title = title,
    ready = QuestIsReady(questID, isComplete),
  }
end

-- The quest log files each quest under a zone header. That header is the
-- zone name this client actually gives us.
local function ReadHeader(index)
  if C_QuestLog and type(C_QuestLog.GetInfo) == "function" then
    local ok, info = pcall(C_QuestLog.GetInfo, index)
    if ok and type(info) == "table" then
      if IsFlag(info.isHeader) then
        return PlainString(info.title)
      end
      return nil
    end
  end
  if type(GetQuestLogTitle) ~= "function" then
    return nil
  end
  local ok, title, _, _, isHeader = pcall(GetQuestLogTitle, index)
  if ok and IsFlag(isHeader) then
    return PlainString(title)
  end
  return nil
end

local function Collect()
  local entries = {}
  local header
  local count = LogCount()
  local index
  for index = 1, count do
    local zoneHeader = ReadHeader(index)
    if zoneHeader then
      header = zoneHeader
    else
      local entry = ReadEntry(index)
      if entry then
        if entry.ready then
          FillTurnIn(entry)
          ApplyLogHeader(entry, header)
        end
        entries[#entries + 1] = entry
      end
    end
  end
  return entries
end

local function PlayerPlace()
  local mapID
  local zone
  if C_Map and type(C_Map.GetBestMapForUnit) == "function" then
    local ok, id = pcall(C_Map.GetBestMapForUnit, "player")
    if ok then
      mapID, zone = ZoneFromMap(id)
    end
  end
  if not zone and type(GetRealZoneText) == "function" then
    local ok, text = pcall(GetRealZoneText)
    if ok then
      zone = PlainString(text)
    end
  end
  if not zone and type(GetZoneText) == "function" then
    local ok, text = pcall(GetZoneText)
    if ok then
      zone = PlainString(text)
    end
  end
  local subzone
  if type(GetSubZoneText) == "function" then
    local ok, text = pcall(GetSubZoneText)
    if ok then
      subzone = PlainString(text)
    end
  end
  return { mapID = mapID, zone = zone, subzone = subzone }
end

local function Note(entries)
  local nextState, announced = Transitions(state, entries, ChatOn())
  state = nextState
  if not FTK:IsEnabled(MODULE_ID) then
    return
  end
  local index
  for index = 1, #announced do
    FTK:Print(ReadyLine(announced[index]))
  end
end

local function Track(quest)
  local did = false
  local questID = quest.questID
  local logIndex = quest.logIndex
  if questID and C_QuestLog and type(C_QuestLog.AddQuestWatch) == "function" then
    local ok, added = pcall(C_QuestLog.AddQuestWatch, questID)
    if ok and added ~= false then
      did = true
    end
  elseif logIndex and type(AddQuestWatch) == "function" then
    if pcall(AddQuestWatch, logIndex) then
      did = true
    end
  end
  if questID and C_SuperTrack and type(C_SuperTrack.SetSuperTrackedQuestID) == "function" then
    if pcall(C_SuperTrack.SetSuperTrackedQuestID, questID) then
      did = true
    end
  elseif questID and type(SetSuperTrackedQuestID) == "function" then
    if pcall(SetSuperTrackedQuestID, questID) then
      did = true
    end
  end
  if questID and C_QuestLog and type(C_QuestLog.SetSelectedQuest) == "function" then
    pcall(C_QuestLog.SetSelectedQuest, questID)
  elseif logIndex and type(SelectQuestLogEntry) == "function" then
    pcall(SelectQuestLogEntry, logIndex)
  end
  local title = quest.title or "that quest"
  if did then
    FTK:Print("Tracking " .. title .. ".")
  else
    FTK:Print("Could not track " .. title .. ".")
  end
end

local function DetailText(quest)
  if quest.npc and quest.place and not SameLabel(quest.place, quest.zone) then
    return quest.npc .. ", " .. quest.place
  end
  return quest.npc
end

local FRAME_W = 460
local FRAME_H = 500
local PAD = 16
local LIST_W = FRAME_W - (PAD * 2) - 22
local HEADER_H = 22
local ROW_H = 36
local ROW_GAP = 4

local function WithBackdrop(target)
  if not target.SetBackdrop then
    local bg = target:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    if bg.SetColorTexture then
      bg:SetColorTexture(0.07, 0.05, 0.04, 0.96)
    end
    return
  end
  target:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  target:SetBackdropColor(0.07, 0.05, 0.04, 0.96)
  target:SetBackdropBorderColor(0.78, 0.64, 0.32, 1)
end

local function MakeButton(parent, label, width)
  local button
  local ok, created = pcall(CreateFrame, "Button", nil, parent, "UIPanelButtonTemplate")
  if ok and type(created) == "table" then
    button = created
  else
    button = CreateFrame("Button", nil, parent)
    local text = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetAllPoints()
    button:SetFontString(text)
  end
  button:SetSize(width, 22)
  button:SetText(label)
  return button
end

local function MakeFrame(name, parent, w, h)
  local createdFrame
  local ok, created = pcall(CreateFrame, "Frame", name, parent, "BackdropTemplate")
  if ok and type(created) == "table" then
    createdFrame = created
  else
    createdFrame = CreateFrame("Frame", name, parent)
  end
  if w and h then
    createdFrame:SetSize(w, h)
  end
  return createdFrame
end

local function SavePosition(target)
  local cfg = Config()
  local ok, point, _, relPoint, x, y = pcall(target.GetPoint, target, 1)
  if not ok or type(point) ~= "string" or type(x) ~= "number" or type(y) ~= "number" then
    return
  end
  cfg.point = point
  cfg.relPoint = type(relPoint) == "string" and relPoint or point
  cfg.x = x
  cfg.y = y
end

local function RestorePosition(target)
  local cfg = Config()
  local function center()
    target:ClearAllPoints()
    target:SetPoint("CENTER", UIParent, "CENTER", 80, 40)
  end
  if type(cfg.point) ~= "string" or type(cfg.x) ~= "number" or type(cfg.y) ~= "number" then
    center()
    return
  end
  local ok = pcall(function()
    target:ClearAllPoints()
    target:SetPoint(cfg.point, UIParent, cfg.relPoint or cfg.point, cfg.x, cfg.y)
  end)
  if not ok then
    center()
  end
end

local function MarkFilters(mode)
  if not window then
    return
  end
  local key, button
  for key, button in pairs(window.filters) do
    local selected = key == mode
    local font = button.GetFontString and button:GetFontString()
    if font and font.SetTextColor then
      if selected then
        font:SetTextColor(1, 0.86, 0.45)
      else
        font:SetTextColor(0.75, 0.7, 0.6)
      end
    end
    if button.bar then
      if selected then
        button.bar:Show()
      else
        button.bar:Hide()
      end
    end
  end
end

local function ReadyOnly(entries)
  local ready = {}
  local index
  for index = 1, #entries do
    if entries[index].ready then
      ready[#ready + 1] = entries[index]
    end
  end
  return ready
end

local function HidePool(pool, used)
  local index
  for index = used + 1, #pool do
    pool[index]:Hide()
  end
end

local function GetHeader(index)
  local header = window.headers[index]
  if header then
    return header
  end
  header = CreateFrame("Frame", nil, window.content)
  header:SetSize(LIST_W, HEADER_H)
  local text = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  text:SetPoint("LEFT", 4, 0)
  text:SetPoint("RIGHT", -4, 0)
  text:SetJustifyH("LEFT")
  text:SetWordWrap(false)
  text:SetTextColor(0.93, 0.8, 0.45)
  header.text = text
  window.headers[index] = header
  return header
end

local function GetRow(index)
  local row = window.rows[index]
  if row then
    return row
  end
  row = CreateFrame("Button", nil, window.content)
  row:SetSize(LIST_W, ROW_H)
  row:RegisterForClicks("LeftButtonUp")
  local bg = row:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  if bg.SetColorTexture then
    bg:SetColorTexture(1, 1, 1, 0.04)
  end
  row.bg = bg
  local title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  title:SetPoint("TOPLEFT", 8, -4)
  title:SetPoint("TOPRIGHT", -8, -4)
  title:SetJustifyH("LEFT")
  title:SetWordWrap(false)
  title:SetTextColor(0.95, 0.92, 0.84)
  row.title = title
  local detail = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  detail:SetPoint("TOPLEFT", 8, -18)
  detail:SetPoint("TOPRIGHT", -8, -18)
  detail:SetJustifyH("LEFT")
  detail:SetWordWrap(false)
  row.detail = detail
  row:SetScript("OnEnter", function(self)
    if self.bg and self.bg.SetColorTexture then
      self.bg:SetColorTexture(0.9, 0.75, 0.35, 0.12)
    end
  end)
  row:SetScript("OnLeave", function(self)
    if self.bg and self.bg.SetColorTexture then
      self.bg:SetColorTexture(1, 1, 1, 0.04)
    end
  end)
  row:SetScript("OnClick", function(self)
    if self.quest then
      Track(self.quest)
    end
  end)
  row:EnableMouseWheel(true)
  row:SetScript("OnMouseWheel", function(_, delta)
    ScrollBy(delta)
  end)
  window.rows[index] = row
  return row
end

local function Paint(entries)
  if not window then
    return
  end
  if not entries then
    entries = Collect()
  end
  local ready = ReadyOnly(entries)
  local player = PlayerPlace()
  local mode = FilterMode()
  local shown, applied = FilterQuests(ready, mode, player)
  local groups = GroupQuests(shown)
  window.subtitle:SetText(Summary(#shown, #ready, applied, player.zone))
  MarkFilters(mode)
  if window.chat then
    window.chat:SetChecked(ChatOn())
  end

  local saved = 0
  if window.scroll.GetVerticalScroll then
    local ok, value = pcall(window.scroll.GetVerticalScroll, window.scroll)
    if ok and type(value) == "number" then
      saved = value
    end
  end

  local y = 0
  local headersUsed = 0
  local rowsUsed = 0
  local group
  for group = 1, #groups do
    headersUsed = headersUsed + 1
    local header = GetHeader(headersUsed)
    local count = #groups[group].quests
    header.text:SetText(groups[group].zone .. " (" .. count .. ")")
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", window.content, "TOPLEFT", 0, -y)
    header:Show()
    y = y + HEADER_H
    local questIndex
    for questIndex = 1, count do
      rowsUsed = rowsUsed + 1
      local row = GetRow(rowsUsed)
      local quest = groups[group].quests[questIndex]
      row.quest = quest
      row.title:SetText(quest.title or "Quest")
      local detail = DetailText(quest)
      if detail then
        row.detail:SetText(detail)
        row.detail:SetTextColor(0.78, 0.72, 0.62)
      else
        row.detail:SetText("NPC unknown")
        row.detail:SetTextColor(0.62, 0.5, 0.4)
      end
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", window.content, "TOPLEFT", 0, -y)
      row:Show()
      y = y + ROW_H + ROW_GAP
    end
    y = y + 6
  end
  HidePool(window.headers, headersUsed)
  HidePool(window.rows, rowsUsed)
  if y < 1 then
    y = 1
  end
  window.content:SetWidth(LIST_W)
  window.content:SetHeight(y)
  if window.scroll.UpdateScrollChildRect then
    pcall(window.scroll.UpdateScrollChildRect, window.scroll)
  end
  if window.empty then
    if #shown == 0 then
      window.empty:SetText(Summary(0, #ready, applied, player.zone))
      window.empty:Show()
    else
      window.empty:Hide()
    end
  end
  if window.scroll.GetVerticalScrollRange and window.scroll.SetVerticalScroll then
    local range = 0
    local ok, value = pcall(window.scroll.GetVerticalScrollRange, window.scroll)
    if ok and type(value) == "number" then
      range = value
    end
    if saved < 0 then
      saved = 0
    end
    if saved > range then
      saved = range
    end
    pcall(window.scroll.SetVerticalScroll, window.scroll, saved)
  end
end

function ScrollBy(delta)
  if not window or not window.scroll then
    return
  end
  pcall(function()
    local range = window.scroll:GetVerticalScrollRange() or 0
    local cur = window.scroll:GetVerticalScroll() or 0
    local y = cur - (delta * 40)
    if y < 0 then
      y = 0
    end
    if y > range then
      y = range
    end
    window.scroll:SetVerticalScroll(y)
  end)
end

local function Ensure()
  if window then
    return window
  end
  local target = MakeFrame("ForeverForgeReadyTurnins", UIParent, FRAME_W, FRAME_H)
  target:Hide()
  target:SetFrameStrata("DIALOG")
  target:SetToplevel(true)
  target:SetMovable(true)
  target:EnableMouse(true)
  target:SetClampedToScreen(true)
  WithBackdrop(target)
  target.headers = {}
  target.rows = {}
  target.filters = {}
  window = target

  if type(UISpecialFrames) == "table" then
    local found = false
    local index
    for index = 1, #UISpecialFrames do
      if UISpecialFrames[index] == "ForeverForgeReadyTurnins" then
        found = true
        break
      end
    end
    if not found then
      UISpecialFrames[#UISpecialFrames + 1] = "ForeverForgeReadyTurnins"
    end
  end

  local drag = CreateFrame("Frame", nil, target)
  drag:SetPoint("TOPLEFT", 8, -6)
  drag:SetPoint("TOPRIGHT", -36, -6)
  drag:SetHeight(28)
  drag:EnableMouse(true)
  drag:RegisterForDrag("LeftButton")
  drag:SetScript("OnDragStart", function()
    target:StartMoving()
  end)
  drag:SetScript("OnDragStop", function()
    target:StopMovingOrSizing()
    SavePosition(target)
  end)

  local close
  local closeOk, created = pcall(CreateFrame, "Button", nil, target, "UIPanelCloseButton")
  if closeOk and type(created) == "table" then
    close = created
    close:SetPoint("TOPRIGHT", 2, 2)
  else
    close = MakeButton(target, "X", 24)
    close:SetPoint("TOPRIGHT", -8, -8)
    close:SetScript("OnClick", function()
      target:Hide()
    end)
  end
  close:SetFrameLevel(drag:GetFrameLevel() + 5)

  local title = target:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -12)
  title:SetWidth(FRAME_W - 64)
  title:SetJustifyH("LEFT")
  title:SetWordWrap(false)
  title:SetTextColor(0.93, 0.8, 0.45)
  title:SetText("Ready Turn-ins")

  local subtitle = target:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  subtitle:SetPoint("TOPLEFT", 16, -36)
  subtitle:SetWidth(FRAME_W - 32)
  subtitle:SetJustifyH("LEFT")
  subtitle:SetWordWrap(true)
  subtitle:SetTextColor(0.75, 0.7, 0.6)
  target.subtitle = subtitle

  local function AddFilter(key, label, x)
    local button = MakeButton(target, label, 132)
    button:SetPoint("TOPLEFT", x, -64)
    local bar = button:CreateTexture(nil, "OVERLAY")
    bar:SetPoint("BOTTOMLEFT", 8, 1)
    bar:SetPoint("BOTTOMRIGHT", -8, 1)
    bar:SetHeight(2)
    if bar.SetColorTexture then
      bar:SetColorTexture(0.9, 0.75, 0.35, 0.9)
    end
    bar:Hide()
    button.bar = bar
    button:SetScript("OnClick", function()
      Config().filter = key
      Paint()
    end)
    target.filters[key] = button
  end
  AddFilter("all", "All", 16)
  AddFilter("here", "This zone", 156)
  AddFilter("away", "Other zones", 296)

  local chat = CreateFrame("CheckButton", nil, target)
  chat:SetSize(24, 24)
  chat:SetPoint("TOPLEFT", 16, -94)
  chat:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
  chat:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
  chat:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
  chat:SetChecked(ChatOn())
  chat:SetScript("OnClick", function(self)
    local checked = self:GetChecked()
    Config().chat = checked == true or checked == 1
  end)
  target.chat = chat
  local chatLabel = target:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  chatLabel:SetPoint("LEFT", chat, "RIGHT", 4, 0)
  chatLabel:SetText("Chat when a quest becomes ready")

  local rule = target:CreateTexture(nil, "ARTWORK")
  rule:SetPoint("TOPLEFT", 14, -126)
  rule:SetPoint("TOPRIGHT", -14, -126)
  rule:SetHeight(1)
  if rule.SetColorTexture then
    rule:SetColorTexture(0.78, 0.64, 0.32, 0.75)
  end

  local scroll
  local scrollOk, scrollFrame = pcall(CreateFrame, "ScrollFrame", "ForeverForgeReadyTurninsScroll", target, "UIPanelScrollFrameTemplate")
  if scrollOk and type(scrollFrame) == "table" then
    scroll = scrollFrame
  else
    scroll = CreateFrame("ScrollFrame", nil, target)
  end
  scroll:SetPoint("TOPLEFT", PAD, -136)
  scroll:SetPoint("BOTTOMRIGHT", -PAD, PAD)
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(_, delta)
    ScrollBy(delta)
  end)
  target.scroll = scroll

  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(LIST_W, 1)
  scroll:SetScrollChild(content)
  target.content = content

  local empty = target:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  empty:SetPoint("TOPLEFT", scroll, "TOPLEFT", 12, -28)
  empty:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", -28, -28)
  empty:SetJustifyH("CENTER")
  empty:SetWordWrap(true)
  empty:SetTextColor(0.8, 0.75, 0.64)
  target.empty = empty
  return target
end

local function Open()
  local target = Ensure()
  if not target:IsShown() then
    RestorePosition(target)
  end
  target:Show()
  if target.Raise then
    target:Raise()
  end
  Paint()
end

local function Toggle()
  local target = Ensure()
  if target:IsShown() then
    target:Hide()
    return
  end
  Open()
end

function Scan()
  if not FTK:IsEnabled(MODULE_ID) then
    return
  end
  local entries = Collect()
  Note(entries)
  if window and window:IsShown() then
    Paint(entries)
  end
end

local function RequestScan()
  if not FTK:IsEnabled(MODULE_ID) then
    return
  end
  if scanPending then
    return
  end
  scanPending = true
  local function run()
    scanPending = false
    if FTK:IsEnabled(MODULE_ID) then
      Scan()
    end
  end
  if C_Timer and C_Timer.After then
    C_Timer.After(0.15, run)
  else
    run()
  end
end

frame:SetScript("OnEvent", function()
  RequestScan()
end)

FTK:RegisterModule({
  id = MODULE_ID,
  name = "Ready Turn-ins",
  description = "Quests ready to turn in, grouped by zone, with the turn-in NPC. Click a row to track it. A chat line can fire when one becomes ready. Filter the list to this zone or to other zones.",
  defaultEnabled = true,
  onConfigure = function()
    Open()
  end,
  onEnable = function()
    state = {}
    local names = {
      "QUEST_LOG_UPDATE",
      "ZONE_CHANGED",
      "ZONE_CHANGED_INDOORS",
      "ZONE_CHANGED_NEW_AREA",
      "PLAYER_ENTERING_WORLD",
    }
    local index
    for index = 1, #names do
      pcall(frame.RegisterEvent, frame, names[index])
    end
    RequestScan()
    -- Questie may finish loading after we do. One later pass picks up its
    -- turn-in names if the log does not update on its own.
    if C_Timer and C_Timer.After then
      C_Timer.After(2, function()
        if FTK:IsEnabled(MODULE_ID) then
          Scan()
        end
      end)
    end
  end,
  onDisable = function()
    state = {}
    frame:UnregisterAllEvents()
    if window then
      window:Hide()
    end
  end,
})

if FTK.RegisterSlash then
  FTK:RegisterSlash("turnins", function()
    if not FTK:IsEnabled(MODULE_ID) then
      FTK:Print("Turn Ready Turn-ins on in the Forever Forge menu first.")
      return
    end
    Toggle()
  end)
end

if type(_G.FOREVERFORGE_TEST) == "table" then
  _G.FOREVERFORGE_TEST.ReadyTurnins = {
    ParseTurnIn = ParseTurnIn,
    BareNpcName = BareNpcName,
    ResolveTurnIn = ResolveTurnIn,
    GroupQuests = GroupQuests,
    FilterQuests = FilterQuests,
    ZonesMatch = ZonesMatch,
    ReadyLine = ReadyLine,
    Summary = Summary,
    Transitions = Transitions,
    ZoneFromMap = ZoneFromMap,
    FillTurnIn = FillTurnIn,
    QuestIsReady = QuestIsReady,
    ReadEntry = ReadEntry,
    ApplyLogHeader = ApplyLogHeader,
    UNKNOWN_ZONE = UNKNOWN_ZONE,
  }
end
