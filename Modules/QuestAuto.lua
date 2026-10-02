--[[
  Quest Auto. Accepts and turns in quests at NPCs. Hold Shift to handle
  the quest yourself. Refuses quests that cost gold to accept, and
  turn-ins that offer multiple item rewards (player must choose).
]]

local FTK = ForeverForge
if not FTK then
  error("ForeverForge: Core.lua must load before Modules/QuestAuto.lua")
end

local MODULE_ID = "QuestAuto"

local frame = CreateFrame("Frame")

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

-- Older clients return 1 for a yes flag. Retail returns true.
local function ApiTrue(value)
  if IsSecret(value) then
    return false
  end
  return value == true or value == 1
end

local function ShiftHeld()
  if type(IsShiftKeyDown) ~= "function" then
    return false
  end
  local ok, down = pcall(IsShiftKeyDown)
  if not ok then
    return false
  end
  return ApiTrue(down)
end

local function Later(callback)
  if C_Timer and C_Timer.After then
    C_Timer.After(0.05, callback)
    return
  end
  callback()
end

local function QuestMoneyCost()
  if type(GetQuestMoneyToGet) ~= "function" then
    return 0
  end
  local ok, copper = pcall(GetQuestMoneyToGet)
  if not ok or IsSecret(copper) then
    return nil
  end
  copper = PlainNumber(copper)
  if copper == nil then
    return nil
  end
  return copper
end

local function RewardChoices()
  if type(GetNumQuestChoices) ~= "function" then
    return nil
  end
  local ok, n = pcall(GetNumQuestChoices)
  if not ok or IsSecret(n) then
    return nil
  end
  return PlainNumber(n)
end

local function Accept()
  if not FTK:IsEnabled(MODULE_ID) or ShiftHeld() then
    return
  end
  local cost = QuestMoneyCost()
  if cost == nil or cost > 0 then
    -- Player must confirm paid quests. A secret cost is also left alone.
    return
  end
  if type(AcceptQuest) == "function" then
    pcall(AcceptQuest)
  end
end

local function Progress()
  if not FTK:IsEnabled(MODULE_ID) or ShiftHeld() then
    return
  end
  local complete = false
  if type(IsQuestCompletable) == "function" then
    local ok, value = pcall(IsQuestCompletable)
    if ok then
      complete = ApiTrue(value)
    end
  end
  if complete and type(CompleteQuest) == "function" then
    pcall(CompleteQuest)
  end
end

local function Complete()
  if not FTK:IsEnabled(MODULE_ID) or ShiftHeld() then
    return
  end
  local choices = RewardChoices()
  if choices == nil or choices > 1 then
    -- Unknown or multi-reward: player must pick.
    return
  end
  if type(GetQuestReward) ~= "function" then
    return
  end
  if choices == 1 then
    pcall(GetQuestReward, 1)
    return
  end
  -- No item choice. Retail accepts no argument; some clients want 0 or 1.
  if pcall(GetQuestReward) then
    return
  end
  if pcall(GetQuestReward, 0) then
    return
  end
  pcall(GetQuestReward, 1)
end

-- Same taxi marker as NPC Assist. When that module is on, it owns the flight option.
local TAXI_ICON = 132057

local function NameLooksLikeTaxi(name)
  name = string.lower(PlainString(name) or "")
  return name:find("fly ", 1, true) or name:find("flight", 1, true) or name:find("taxi", 1, true)
end

local function TaxiPresent()
  if C_GossipInfo and C_GossipInfo.GetOptions then
    local ok, options = pcall(C_GossipInfo.GetOptions)
    if ok and type(options) == "table" then
      local i
      for i = 1, #options do
        local opt = options[i]
        if type(opt) == "table" then
          local gtype = string.lower(PlainString(opt.type) or "")
          local status = PlainNumber(opt.status)
          local blocked = status == 1 or status == 2
          if gtype ~= "binder" and not blocked then
            local icon = PlainNumber(opt.icon)
            local overrideIcon = PlainNumber(opt.overrideIconID)
            if gtype == "taxi" or icon == TAXI_ICON or overrideIcon == TAXI_ICON or NameLooksLikeTaxi(opt.name) then
              return true
            end
          end
        end
      end
    end
  end
  if type(GetGossipOptions) == "function" then
    local ok, values = pcall(function()
      return { GetGossipOptions() }
    end)
    if ok and type(values) == "table" then
      local i = 1
      while values[i] do
        local gtype = string.lower(PlainString(values[i + 1]) or "")
        if gtype == "taxi" or NameLooksLikeTaxi(values[i]) then
          return true
        end
        i = i + 2
      end
    end
  end
  return false
end

local function GossipQuests()
  if not FTK:IsEnabled(MODULE_ID) or ShiftHeld() then
    return
  end
  -- Flight master with a quest: NPC Assist opens the taxi map. Do not steal it.
  if FTK:IsEnabled("NpcAssist") and TaxiPresent() then
    return
  end
  -- Prefer turning in active completable quests, then accepting available.
  if C_GossipInfo then
    if C_GossipInfo.GetActiveQuests and C_GossipInfo.SelectActiveQuest then
      local ok, list = pcall(C_GossipInfo.GetActiveQuests)
      if ok and type(list) == "table" then
        local i
        for i = 1, #list do
          local q = list[i]
          if type(q) == "table" then
            local done = q.isComplete
            if IsSecret(done) then
              done = false
            end
            -- SelectActiveQuest takes a quest id. The loop index is not an id.
            if ApiTrue(done) then
              local id = PlainNumber(q.questID) or PlainNumber(q.questId)
              if id then
                pcall(C_GossipInfo.SelectActiveQuest, id)
                return
              end
            end
          end
        end
      end
    end
    if C_GossipInfo.GetAvailableQuests and C_GossipInfo.SelectAvailableQuest then
      local ok, list = pcall(C_GossipInfo.GetAvailableQuests)
      if ok and type(list) == "table" and #list == 1 then
        local q = list[1]
        local id = type(q) == "table" and (PlainNumber(q.questID) or PlainNumber(q.questId)) or nil
        if type(q) == "table" then
          local cost = PlainNumber(q.cost) or PlainNumber(q.moneyToGet)
          if cost and cost > 0 then
            return
          end
        end
        if id then
          pcall(C_GossipInfo.SelectAvailableQuest, id)
          return
        end
      elseif ok and type(list) == "table" and #list > 1 then
        -- Multiple available: do not auto-pick.
        return
      end
    end
  end

  if type(GetNumGossipActiveQuests) == "function" and type(SelectGossipActiveQuest) == "function" then
    local ok, n = pcall(GetNumGossipActiveQuests)
    n = ok and PlainNumber(n) or 0
    -- Classic lacks per-quest complete on gossip; if exactly one active, select it.
    if n == 1 then
      pcall(SelectGossipActiveQuest, 1)
      return
    end
  end
  if type(GetNumGossipAvailableQuests) == "function" and type(SelectGossipAvailableQuest) == "function" then
    local ok, n = pcall(GetNumGossipAvailableQuests)
    n = ok and PlainNumber(n) or 0
    if n == 1 then
      pcall(SelectGossipAvailableQuest, 1)
      return
    end
  end
end

local function Greeting()
  if not FTK:IsEnabled(MODULE_ID) or ShiftHeld() then
    return
  end
  -- QUEST_GREETING: select single available or single active when unambiguous.
  local avail, active = 0, 0
  if type(GetNumAvailableQuests) == "function" then
    local ok, n = pcall(GetNumAvailableQuests)
    avail = ok and PlainNumber(n) or 0
  end
  if type(GetNumActiveQuests) == "function" then
    local ok, n = pcall(GetNumActiveQuests)
    active = ok and PlainNumber(n) or 0
  end
  if active == 1 and type(SelectActiveQuest) == "function" then
    pcall(SelectActiveQuest, 1)
    return
  end
  if avail == 1 and active == 0 and type(SelectAvailableQuest) == "function" then
    pcall(SelectAvailableQuest, 1)
  end
end

frame:SetScript("OnEvent", function(_, event)
  if event == "QUEST_DETAIL" then
    Later(Accept)
  elseif event == "QUEST_PROGRESS" then
    Later(Progress)
  elseif event == "QUEST_COMPLETE" then
    Later(Complete)
  elseif event == "GOSSIP_SHOW" then
    Later(GossipQuests)
  elseif event == "QUEST_GREETING" then
    Later(Greeting)
  end
end)

FTK:RegisterModule({
  id = MODULE_ID,
  name = "Quest Auto",
  description = "Accepts and turns in quests. Hold Shift to handle them yourself. Skips gold-cost quests and multi-reward turn-ins.",
  defaultEnabled = true,
  onEnable = function()
    local names = {
      "QUEST_DETAIL",
      "QUEST_PROGRESS",
      "QUEST_COMPLETE",
      "GOSSIP_SHOW",
      "QUEST_GREETING",
    }
    local i
    for i = 1, #names do
      pcall(frame.RegisterEvent, frame, names[i])
    end
  end,
  onDisable = function()
    frame:UnregisterAllEvents()
  end,
})
