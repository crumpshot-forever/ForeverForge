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

local function ShiftHeld()
  if type(IsShiftKeyDown) ~= "function" then
    return false
  end
  local ok, down = pcall(IsShiftKeyDown)
  if not ok or IsSecret(down) then
    return false
  end
  return down == true
end

local function Later(callback)
  if C_Timer and C_Timer.After then
    C_Timer.After(0.05, callback)
    return
  end
  callback()
end

local function QuestMoneyCost()
  if type(GetQuestMoneyToGet) == "function" then
    local ok, copper = pcall(GetQuestMoneyToGet)
    copper = ok and PlainNumber(copper) or nil
    if copper and copper > 0 then
      return copper
    end
  end
  return 0
end

local function RewardChoices()
  if type(GetNumQuestChoices) == "function" then
    local ok, n = pcall(GetNumQuestChoices)
    return ok and PlainNumber(n) or 0
  end
  return 0
end

local function Accept()
  if not FTK:IsEnabled(MODULE_ID) or ShiftHeld() then
    return
  end
  if QuestMoneyCost() > 0 then
    -- Player must confirm paid quests.
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
    if ok and not IsSecret(value) then
      complete = value == true
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
  if choices and choices > 1 then
    -- Multi-reward: player must pick.
    return
  end
  if type(GetQuestReward) == "function" then
    if choices == 0 then
      if not pcall(GetQuestReward, 1) then
        pcall(GetQuestReward)
      end
      return
    end
    pcall(GetQuestReward, 1)
  end
end

local function GossipQuests()
  if not FTK:IsEnabled(MODULE_ID) or ShiftHeld() then
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
            if done == true then
              local id = PlainNumber(q.questID) or PlainNumber(q.questId)
              if id and C_GossipInfo.SelectActiveQuest then
                pcall(C_GossipInfo.SelectActiveQuest, id)
                return
              end
              pcall(C_GossipInfo.SelectActiveQuest, i)
              return
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
        else
          pcall(C_GossipInfo.SelectAvailableQuest, 1)
        end
        return
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
