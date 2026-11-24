--[[
  Ready Turn-ins parsing, grouping, and the "became ready" chat rule.
  Run with: node tests/run-ready-turnins.js
]]

local failures = 0
local function check(cond, message)
  if not cond then
    failures = failures + 1
    print("FAIL: " .. tostring(message))
  end
end

local function noop()
end

function CreateFrame()
  local widget = {}
  setmetatable(widget, {
    __index = function()
      return noop
    end,
  })
  return widget
end

local saved = {}
ForeverForge = {
  RegisterModule = function(_, def)
    ForeverForge.mod = def
    return def
  end,
  RegisterSlash = function(_, word, handler)
    ForeverForge.slash = ForeverForge.slash or {}
    ForeverForge.slash[word] = handler
  end,
  GetConfig = function()
    return saved
  end,
  IsEnabled = function()
    return true
  end,
  Print = function()
  end,
  Plain = function(text)
    return tostring(text or "")
  end,
}

FOREVERFORGE_TEST = {}

local function loadSource(name, source)
  local chunk, err = load(source, "@" .. name)
  if not chunk then
    error(err)
  end
  chunk()
end

loadSource("Modules/ReadyTurnins.lua", TURNIN_SRC)

local api = FOREVERFORGE_TEST.ReadyTurnins
check(type(api) == "table", "test hooks exported")
check(ForeverForge.mod.name == "Ready Turn-ins", "module name")
check(ForeverForge.mod.defaultEnabled == true, "on by default")
check(type(ForeverForge.slash.turnins) == "function", "slash word registered")

local npc, place = api.ParseTurnIn("Return to Gazlowe at Ratchet")
check(npc == "Gazlowe" and place == "Ratchet", "return to at")

npc, place = api.ParseTurnIn("|cffffffffReturn to Gazlowe in Ratchet: 1/1|r")
check(npc == "Gazlowe" and place == "Ratchet", "colored return to in, with count")

npc, place = api.ParseTurnIn("Return to Theldurin the Lost")
check(npc == "Theldurin the Lost" and place == nil, "return to name only")

npc, place = api.ParseTurnIn("Baros Alexston spoken to: 0/1")
check(npc == "Baros Alexston" and place == nil, "spoken to")

npc, place = api.ParseTurnIn("Speak with Guard Thomas in Elwynn Forest")
check(npc == "Guard Thomas" and place == "Elwynn Forest", "speak with in")

npc, place = api.ParseTurnIn("Deliver the documents to Elling Trias in Stormwind")
check(npc == "Elling Trias" and place == "Stormwind", "deliver to in")

npc, place = api.ParseTurnIn("Bring the mug to Innkeeper Belm at Kharanos (1/1)")
check(npc == "Innkeeper Belm" and place == "Kharanos", "bring to at, parenthetical count")

npc, place = api.ParseTurnIn("Bring 10 Red Silk Bandanas to Captain Thalo'thas Brightsun in Ratchet.")
check(npc == "Captain Thalo'thas Brightsun" and place == "Ratchet", "bring items to an NPC in a town")

local region
npc, place, region = api.ParseTurnIn("Escort OOX-17/TN to Steamwheedle Port, then report to Oglethorpe Obnoticus in Booty Bay.")
check(npc == "Oglethorpe Obnoticus" and place == "Booty Bay" and region == nil, "the last report-to in a sentence is the turn-in")

npc, place, region = api.ParseTurnIn("Return to Gryphon Master Talonaxe at Aerie Peak in the Hinterlands.")
check(npc == "Gryphon Master Talonaxe" and place == "Aerie Peak" and region == "The Hinterlands", "town and zone from one return line")

npc, place = api.ParseTurnIn("Hogger slain: 1/1")
check(npc == nil and place == nil, "kill objectives are not a turn-in")

check(api.BareNpcName("Warden Thelwater", "The Stockade Riots") == "Warden Thelwater", "bare waypoint name")
check(api.BareNpcName("Hogger slain", "Wanted") == nil, "bare name rejects a kill line")
check(api.BareNpcName("The Stockade Riots", "The Stockade Riots") == nil, "bare name rejects the quest title")
check(api.BareNpcName("Go to the top of the tower", "A Tall Order") == nil, "bare name rejects a travel sentence")
check(api.BareNpcName("Go to Goldshire", "A Tall Order") == nil, "bare name rejects a go-to line")

npc, place = api.ResolveTurnIn("Return to Marshal Dughan", { "Wolves slain: 8/8" }, "Elwynn Forest", "Riverpaw Gnoll Bounty")
local zone
npc, zone, place = api.ResolveTurnIn(
  "Return to Marshal Dughan",
  { "Wolves slain: 8/8", "Return to Marshal Dughan at Goldshire: 1/1" },
  "Elwynn Forest",
  "Riverpaw Gnoll Bounty"
)
check(npc == "Marshal Dughan", "waypoint npc wins")
check(zone == "Elwynn Forest", "map zone is the group zone")
check(place == "Goldshire", "objective keeps the town")

npc, zone, place = api.ResolveTurnIn(nil, { "Speak to Draz'Zilb in Brackenwall Village" }, nil, "The Brood of Onyxia")
check(npc == "Draz'Zilb" and zone == "Brackenwall Village" and place == "Brackenwall Village", "objective supplies zone when the map does not")

local groups = api.GroupQuests({
  { title = "Zulu", zone = "Stormwind City", questID = 2 },
  { title = "Alpha", zone = "Elwynn Forest", questID = 3 },
  { title = "Beta", zone = "Elwynn Forest", questID = 1 },
  { title = "Lost", questID = 9 },
})
check(#groups == 3, "three zone groups")
check(groups[1].zone == "Elwynn Forest" and groups[1].quests[1].title == "Alpha", "zones and quests sort")
check(groups[1].quests[2].title == "Beta", "second quest in the zone")
check(groups[2].zone == "Stormwind City", "second zone")
check(groups[3].zone == api.UNKNOWN_ZONE and groups[3].quests[1].title == "Lost", "unknown zone is last")

local quests = {
  { title = "A", zone = "Elwynn Forest", mapID = 12 },
  { title = "B", zone = "Stormwind City", mapID = 84 },
  { title = "C" },
}
local player = { mapID = 12, zone = "Elwynn Forest", subzone = "Goldshire" }
local shown, applied = api.FilterQuests(quests, "here", player)
check(applied == "here" and #shown == 1 and shown[1].title == "A", "this zone keeps the matching map")
shown, applied = api.FilterQuests(quests, "away", player)
check(applied == "away" and #shown == 2, "other zones keeps the rest, including an unknown zone")
shown, applied = api.FilterQuests(quests, "here", {})
check(applied == "unknown" and #shown == 3, "unknown player zone shows every quest")
shown, applied = api.FilterQuests(quests, "all", player)
check(applied == "all" and shown == quests, "all returns the same list")

check(api.ZonesMatch({ zone = "Stormwind City" }, { zone = "Stormwind" }) == true, "Stormwind matches Stormwind City")
check(api.ZonesMatch({ zone = "Hillsbrad Foothills" }, { zone = "Hills" }) == false, "a short name does not match a longer zone")
check(api.ZonesMatch({ place = "Goldshire" }, { subzone = "Goldshire" }) == true, "town matches the player's subzone")

check(api.ReadyLine({ title = "Bounty", npc = "Marshal Dughan", place = "Goldshire", zone = "Elwynn Forest" }) == "Ready: Bounty - Marshal Dughan, Goldshire, Elwynn Forest.", "chat line names the town and the zone")
check(api.ReadyLine({ title = "Bounty", zone = "Elwynn Forest" }) == "Ready: Bounty - Elwynn Forest.", "chat line can be zone only")
check(api.ReadyLine({ title = "Bounty" }) == "Ready: Bounty.", "chat line can be the title only")
check(api.Summary(0, 0, "all", nil) == "No quests are ready to turn in.", "empty summary")
check(api.Summary(1, 1, "all", nil) == "1 quest is ready. Click a quest to track it.", "singular summary")
check(api.Summary(0, 2, "here", "Elwynn Forest") == "No ready turn-ins in Elwynn Forest.", "empty this-zone summary")

local headed = { npc = "Gazlowe", zone = "Ratchet", place = "Ratchet" }
api.ApplyLogHeader(headed, "The Barrens")
check(headed.zone == "The Barrens" and headed.place == "Ratchet", "log header replaces a town-only zone")
headed = { npc = "Marshal Dughan", zone = "Elwynn Forest", place = "Goldshire" }
api.ApplyLogHeader(headed, "Stormwind City")
check(headed.zone == "Elwynn Forest" and headed.place == "Goldshire", "a real zone is kept over the log header")
headed = {}
api.ApplyLogHeader(headed, "The Hinterlands")
check(headed.zone == "The Hinterlands", "a bare quest takes the log header as its zone")
local generic = {}
api.ApplyLogHeader(generic, "Miscellaneous")
check(generic.zone == nil, "a generic header is not a zone")

local nextState, announced = api.Transitions({}, { { questID = 5, ready = true, title = "Already" } }, true)
check(nextState[5] == true and #announced == 0, "already-ready quests stay quiet")
nextState, announced = api.Transitions({ [5] = false }, { { questID = 5, ready = true, title = "Now" } }, true)
check(#announced == 1 and announced[1].title == "Now", "in-progress to ready announces")
nextState, announced = api.Transitions({ [5] = false }, { { questID = 5, ready = true, title = "Now" } }, false)
check(#announced == 0 and nextState[5] == true, "chat off still records the quest")
nextState, announced = api.Transitions({ [5] = true, [8] = false }, { { questID = 5, ready = true } }, true)
check(#announced == 0 and nextState[8] == nil, "still ready is quiet, and a removed quest drops out")

C_Map = {
  GetMapInfo = function(id)
    if id == 10 then
      return { name = "Goldshire", mapType = 5, parentMapID = 12 }
    end
    if id == 12 then
      return { name = "Elwynn Forest", mapType = 3, parentMapID = 13 }
    end
    if id == 13 then
      return { name = "Eastern Kingdoms", mapType = 2, parentMapID = 0 }
    end
    return nil
  end,
}
local mapID, mapName = api.ZoneFromMap(10)
check(mapID == 12 and mapName == "Elwynn Forest", "micro map walks up to its zone")
mapID, mapName = api.ZoneFromMap(12)
check(mapID == 12 and mapName == "Elwynn Forest", "zone map stays the zone")

C_QuestLog = {
  ReadyForTurnIn = function(id)
    return id == 5
  end,
  IsComplete = function()
    return true
  end,
  IsFailed = function(id)
    return id == 9
  end,
  GetNextWaypoint = function()
    return 10, 0.4, 0.6
  end,
  GetNextWaypointText = function()
    return "Return to Marshal Dughan"
  end,
  GetQuestObjectives = function()
    return {
      { text = "Wolves slain: 8/8" },
      { text = "Return to Marshal Dughan at Goldshire: 1/1" },
    }
  end,
}
check(api.QuestIsReady(5, nil) == true, "ready for turn-in")
check(api.QuestIsReady(6, nil) == false, "not ready even if IsComplete would say yes")
check(api.QuestIsReady(9, nil) == false, "failed quests are not ready")
check(api.QuestIsReady(1, -1) == false, "classic failed flag")

local entry = { questID = 5, logIndex = 2, title = "Riverpaw Gnoll Bounty" }
api.FillTurnIn(entry)
check(entry.npc == "Marshal Dughan", "fill uses the waypoint npc")
check(entry.zone == "Elwynn Forest", "fill uses the zone map")
check(entry.place == "Goldshire", "fill keeps the town")
check(entry.mapID == 12, "fill stores the zone map id")

C_QuestLog.GetQuestObjectives = nil
C_QuestLog.GetNextWaypoint = function()
  return nil
end
C_QuestLog.GetNextWaypointText = function()
  return nil
end
GetNumQuestLeaderBoards = function()
  return 1
end
GetQuestLogLeaderBoard = function()
  return "Return to Gazlowe at Ratchet: 1/1"
end
entry = { questID = 4, logIndex = 3, title = "Kaboom" }
api.FillTurnIn(entry)
check(entry.npc == "Gazlowe" and entry.zone == "Ratchet", "leaderboard text supplies the turn-in")

C_QuestLog = {
  GetNumQuestLogEntries = function()
    return 2
  end,
  GetInfo = function(index)
    if index == 1 then
      return { title = "Elwynn Forest", isHeader = true, questID = 0 }
    end
    if index == 2 then
      return { title = "Riverpaw Gnoll Bounty", questID = 10, questLogIndex = 2 }
    end
    return nil
  end,
}
GetQuestLogTitle = function(index)
  if index == 2 then
    return "Riverpaw Gnoll Bounty", 5, nil, false, false, 1, nil, 10
  end
  return "Elwynn Forest", nil, nil, true
end
local classicEntry = api.ReadEntry(2)
check(classicEntry and classicEntry.ready == true and classicEntry.title == "Riverpaw Gnoll Bounty", "older log flag marks the quest ready")
check(api.ReadEntry(1) == nil, "zone headers are skipped")

C_QuestLog = nil
check(api.QuestIsReady(3, 1) == true, "classic complete flag when the new API is missing")
check(api.QuestIsReady(3, nil) == false, "classic incomplete flag")

if failures > 0 then
  error(failures .. " ready turn-in check(s) failed")
end
print("ready turn-in checks passed")
