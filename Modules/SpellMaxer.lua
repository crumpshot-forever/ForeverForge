--[[
  SpellMaxer. On login, instance entry, and group changes, checks this
  character's action bars 1-8. A lower rank than the best rank already
  known for their level posts the catchline in the local chat window.

  Other players are not checked. Their bars are not readable, and comparing
  their casts to this character's spellbook only works for the same class.
  A secret id, name, or rank is skipped.
  See ../FlowRider/docs/Forever-API-visibility.md.
]]

local FTK = ForeverToolkit
if not FTK then
  error("ForeverToolkit: Core.lua must load before Modules/SpellMaxer.lua")
end

local MODULE_ID = "SpellMaxer"

-- Blizzard bars 1-8, in the order the default UI names them.
-- Button .action is the live slot (bar 1 follows the current page).
-- The fallback start slot is used when that button does not exist.
local BARS = {
  { prefix = "ActionButton", fallback = 1 },
  { prefix = "MultiBarBottomLeftButton", fallback = 61 },
  { prefix = "MultiBarBottomRightButton", fallback = 49 },
  { prefix = "MultiBarRightButton", fallback = 25 },
  { prefix = "MultiBarLeftButton", fallback = 37 },
  { prefix = "MultiBar5Button", fallback = 145 },
  { prefix = "MultiBar6Button", fallback = 157 },
  { prefix = "MultiBar7Button", fallback = 169 },
}

local frame = CreateFrame("Frame")
local ready = false
local scheduled = false
local pendingSelf = false
local told = {}
local bookSpells = {}
local groupKey = nil

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
  if type(value) ~= "string" or value == "" or IsSecret(value) then
    return nil
  end
  return value
end

local function SpellName(spellId)
  if not (C_Spell and C_Spell.GetSpellInfo) then
    return nil
  end
  local ok, info = pcall(C_Spell.GetSpellInfo, spellId)
  if ok and type(info) == "table" then
    local name = PlainString(info.name)
    if name then
      return name
    end
  end
  if C_Spell.GetSpellName then
    local nameOk, name = pcall(C_Spell.GetSpellName, spellId)
    if nameOk then
      return PlainString(name)
    end
  end
  return nil
end

local function SpellSubtext(spellId)
  if not (C_Spell and C_Spell.GetSpellSubtext) then
    return nil
  end
  local ok, subtext = pcall(C_Spell.GetSpellSubtext, spellId)
  if not ok then
    return nil
  end
  return PlainString(subtext)
end

local function RankOf(spellId)
  local subtext = SpellSubtext(spellId)
  if not subtext then
    return nil
  end
  local digits = subtext:match("(%d+)")
  if not digits then
    return nil
  end
  return PlainNumber(tonumber(digits))
end

local function LearnedLevel(spellId)
  if not (C_Spell and C_Spell.GetSpellLevelLearned) then
    return nil
  end
  local ok, level = pcall(C_Spell.GetSpellLevelLearned, spellId)
  if not ok then
    return nil
  end
  return PlainNumber(level)
end

local function PlayerLevel()
  if not UnitLevel then
    return nil
  end
  local ok, level = pcall(UnitLevel, "player")
  if not ok then
    return nil
  end
  return PlainNumber(level)
end

local function PlayerName()
  if not UnitName then
    return nil
  end
  local ok, name = pcall(UnitName, "player")
  if not ok then
    return nil
  end
  return PlainString(name)
end

local function PlayerInCombat()
  if not UnitAffectingCombat then
    return false
  end
  local ok, combat = pcall(UnitAffectingCombat, "player")
  if not ok or IsSecret(combat) then
    return false
  end
  return combat == true
end

local function BookSpellId(name)
  if not (C_Spell and C_Spell.GetSpellInfo) then
    return nil
  end
  local ok, info = pcall(C_Spell.GetSpellInfo, name)
  if not ok or type(info) ~= "table" then
    return nil
  end
  return PlainNumber(info.spellID or info.spellId)
end

local function EachBookSpell(visitor)
  local book = C_SpellBook
  if not (book and book.GetSpellBookItemInfo and book.GetNumSpellBookSkillLines and book.GetSpellBookSkillLineInfo) then
    return
  end
  local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
  local ok, lineCount = pcall(book.GetNumSpellBookSkillLines)
  lineCount = ok and PlainNumber(lineCount) or nil
  if not lineCount or lineCount < 1 then
    return
  end
  local line
  for line = 1, lineCount do
    local infoOk, lineInfo = pcall(book.GetSpellBookSkillLineInfo, line)
    if infoOk and type(lineInfo) == "table" then
      local offset = PlainNumber(lineInfo.itemIndexOffset) or 0
      local count = PlainNumber(lineInfo.numSpellBookItems) or 0
      local index
      for index = 1, count do
        local itemOk, item = pcall(book.GetSpellBookItemInfo, offset + index, bank)
        if itemOk and type(item) == "table" then
          local spellId = PlainNumber(item.spellID or item.spellId)
          if spellId then
            visitor(spellId)
          end
        end
      end
    end
  end
end

local function ActionSlot(bar, index)
  local button = _G[bar.prefix .. index]
  if button then
    local action = PlainNumber(button.action)
    if action and action >= 1 then
      return action
    end
  end
  if bar.prefix == "ActionButton" and GetActionBarPage then
    local ok, page = pcall(GetActionBarPage)
    page = ok and PlainNumber(page) or nil
    if page and page >= 1 then
      return (page - 1) * 12 + index
    end
  end
  return bar.fallback + index - 1
end

local function ActionSpellId(slot)
  if not GetActionInfo then
    return nil
  end
  local ok, actionType, id = pcall(GetActionInfo, slot)
  if not ok or IsSecret(actionType) or type(actionType) ~= "string" or actionType ~= "spell" then
    return nil
  end
  return PlainNumber(id)
end

local function WouldSay(who, spellName)
  return "Hey, " .. who .. ", you aren't Spellmaxing to the MAX! You're using a lower level of " .. spellName .. "! Check yoself!"
end

local function Announce(who, spellName)
  local key = who .. "|" .. spellName
  if told[key] then
    return
  end
  told[key] = true
  local text = WouldSay(who, spellName)
  local chat = _G.DEFAULT_CHAT_FRAME
  if chat and chat.AddMessage then
    chat:AddMessage(text)
  else
    FTK:Print(text)
  end
end

local function RefreshBook()
  local nextBook = {}
  local function add(spellId)
    local name = SpellName(spellId)
    local rank = RankOf(spellId)
    if not name or not rank then
      return
    end
    local index
    for index = 1, #nextBook do
      local spell = nextBook[index]
      if spell.name == name and spell.rank == rank then
        return
      end
    end
    nextBook[#nextBook + 1] = {
      name = name,
      id = spellId,
      rank = rank,
      learned = LearnedLevel(spellId),
    }
  end
  EachBookSpell(add)
  bookSpells = nextBook
end

local function BestFor(spellName, level)
  local function legal(learned)
    if learned and level and learned <= level then
      return true
    end
    if learned == nil or level == nil then
      return true
    end
    return false
  end
  local best
  local index
  for index = 1, #bookSpells do
    local spell = bookSpells[index]
    if spell.name == spellName and legal(spell.learned) and (not best or spell.rank > best.rank) then
      best = spell
    end
  end
  local fromName = BookSpellId(spellName)
  if fromName then
    local rank = RankOf(fromName)
    local learned = LearnedLevel(fromName)
    if rank and legal(learned) and (not best or rank > best.rank) then
      best = { name = spellName, id = fromName, rank = rank, learned = learned }
    end
  end
  return best
end

local function EachGroupUnit(visitor)
  local inRaid = false
  if IsInRaid then
    local ok, raid = pcall(IsInRaid)
    if ok and not IsSecret(raid) and raid == true then
      inRaid = true
    end
  end
  if inRaid and GetNumGroupMembers then
    local ok, count = pcall(GetNumGroupMembers)
    count = ok and PlainNumber(count) or 0
    local index
    for index = 1, count do
      visitor("raid" .. index)
    end
    return
  end
  local count = 0
  if GetNumSubgroupMembers then
    local ok, partyCount = pcall(GetNumSubgroupMembers)
    count = ok and PlainNumber(partyCount) or 0
  elseif GetNumPartyMembers then
    local ok, partyCount = pcall(GetNumPartyMembers)
    count = ok and PlainNumber(partyCount) or 0
  end
  local index
  for index = 1, count do
    visitor("party" .. index)
  end
end

local function GroupSignature()
  local names = {}
  EachGroupUnit(function(unit)
    local ok, name = pcall(UnitName, unit)
    name = ok and PlainString(name) or nil
    if name then
      names[#names + 1] = name
    end
  end)
  table.sort(names)
  return table.concat(names, ",")
end

local function NoteGroupChange()
  local signature = GroupSignature()
  if signature == groupKey then
    return false
  end
  groupKey = signature
  told = {}
  return true
end

local function CheckBars()
  if not FTK:IsEnabled(MODULE_ID) then
    return
  end
  if PlayerInCombat() then
    pendingSelf = true
    return
  end
  pendingSelf = false
  local player = PlayerName()
  if not player then
    return
  end
  local playerLevel = PlayerLevel()
  RefreshBook()

  local barIndex, buttonIndex
  for barIndex = 1, #BARS do
    local bar = BARS[barIndex]
    for buttonIndex = 1, 12 do
      local spellId = ActionSpellId(ActionSlot(bar, buttonIndex))
      if spellId then
        local name = SpellName(spellId)
        local rank = RankOf(spellId)
        local best = name and BestFor(name, playerLevel)
        if name and rank and best and rank < best.rank then
          Announce(player, name)
        end
      end
    end
  end
end

local function Schedule()
  if scheduled or not ready then
    return
  end
  scheduled = true
  if C_Timer and C_Timer.After then
    C_Timer.After(1.5, function()
      scheduled = false
      CheckBars()
    end)
    return
  end
  scheduled = false
  CheckBars()
end

frame:SetScript("OnEvent", function(_, event)
  if not FTK:IsEnabled(MODULE_ID) and event ~= "PLAYER_ENTERING_WORLD" then
    return
  end
  if event == "PLAYER_ENTERING_WORLD" then
    ready = true
    told = {}
    groupKey = GroupSignature()
    Schedule()
    return
  end
  if not ready then
    return
  end
  if event == "PLAYER_REGEN_ENABLED" then
    if pendingSelf then
      Schedule()
    end
    return
  end
  if event == "GROUP_ROSTER_UPDATE" or event == "GROUP_FORMED" then
    if NoteGroupChange() then
      Schedule()
    end
  end
end)

FTK:RegisterModule({
  id = MODULE_ID,
  name = "SpellMaxer",
  description = "Calls out a lower spell rank on your action bars when you log in, change instance, or the group changes.",
  defaultEnabled = true,
  onEnable = function()
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("GROUP_ROSTER_UPDATE")
    frame:RegisterEvent("GROUP_FORMED")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    if ready then
      told = {}
      groupKey = GroupSignature()
      Schedule()
    end
  end,
  onDisable = function()
    frame:UnregisterAllEvents()
    scheduled = false
  end,
})
