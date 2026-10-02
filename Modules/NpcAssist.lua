--[[
  NPC Assist. Gossip Skip and Flight Direct as one feature.
  - Flight master gossip → open the taxi map (select taxi option).
  - Exactly one non-quest gossip and no quest gossip lines → select it.
  Hold Shift for normal talk (no auto).
]]

local FTK = ForeverForge
if not FTK then
  error("ForeverForge: Core.lua must load before Modules/NpcAssist.lua")
end

local MODULE_ID = "NpcAssist"

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

local function GossipQuestCount()
  local available = 0
  local active = 0
  if C_GossipInfo then
    if C_GossipInfo.GetAvailableQuests then
      local ok, list = pcall(C_GossipInfo.GetAvailableQuests)
      if ok and type(list) == "table" then
        available = #list
      end
    end
    if C_GossipInfo.GetActiveQuests then
      local ok, list = pcall(C_GossipInfo.GetActiveQuests)
      if ok and type(list) == "table" then
        active = #list
      end
    end
  end
  if available == 0 and type(GetNumGossipAvailableQuests) == "function" then
    local ok, n = pcall(GetNumGossipAvailableQuests)
    available = ok and PlainNumber(n) or 0
  end
  if active == 0 and type(GetNumGossipActiveQuests) == "function" then
    local ok, n = pcall(GetNumGossipActiveQuests)
    active = ok and PlainNumber(n) or 0
  end
  return available + active
end

-- Returns list of { index=1-based classic index, optionID=, gossipOptionID=, name=, gtype= }
local function GossipOptions()
  local list = {}
  if C_GossipInfo and C_GossipInfo.GetOptions then
    local ok, options = pcall(C_GossipInfo.GetOptions)
    if ok and type(options) == "table" and #options > 0 then
      local i
      for i = 1, #options do
        local opt = options[i]
        if type(opt) == "table" then
          local gtype = PlainString(opt.type) or ""
          list[#list + 1] = {
            index = i,
            orderIndex = PlainNumber(opt.orderIndex),
            optionID = PlainNumber(opt.gossipOptionID) or PlainNumber(opt.optionID),
            name = PlainString(opt.name) or "",
            gtype = string.lower(gtype),
            icon = PlainNumber(opt.icon),
            overrideIcon = PlainNumber(opt.overrideIconID),
            status = PlainNumber(opt.status),
          }
        end
      end
      return list
    end
  end
  if type(GetGossipOptions) == "function" then
    local ok, values = pcall(function()
      return { GetGossipOptions() }
    end)
    if ok and type(values) == "table" then
      local i = 1
      local index = 1
      while values[i] do
        local name = PlainString(values[i])
        local gtype = PlainString(values[i + 1]) or ""
        list[#list + 1] = {
          index = index,
          name = name or "",
          gtype = string.lower(gtype),
        }
        i = i + 2
        index = index + 1
      end
    end
  end
  return list
end

local function SelectOption(entry)
  if not entry then
    return false
  end
  if entry.optionID and C_GossipInfo and C_GossipInfo.SelectOption then
    local ok = pcall(C_GossipInfo.SelectOption, entry.optionID)
    if ok then
      return true
    end
  end
  -- 10.0+ SelectOption needs gossipOptionID, which can be nil. orderIndex can be 0.
  if entry.orderIndex ~= nil and C_GossipInfo and C_GossipInfo.SelectOptionByIndex then
    local ok = pcall(C_GossipInfo.SelectOptionByIndex, entry.orderIndex)
    if ok then
      return true
    end
  end
  if type(SelectGossipOption) == "function" and entry.index then
    return pcall(SelectGossipOption, entry.index)
  end
  return false
end

-- Interface/GossipFrame/TaxiGossipIcon.blp. GetOptions dropped the type field in 10.0.
local TAXI_ICON = 132057

local function OptionBlocked(entry)
  -- GossipOptionStatus: 1 Unavailable, 2 Locked.
  return entry.status == 1 or entry.status == 2
end

local function IsTaxiEntry(entry)
  if not entry or OptionBlocked(entry) then
    return false
  end
  local gtype = entry.gtype or ""
  if gtype == "binder" then
    return false
  end
  if gtype == "taxi" or entry.icon == TAXI_ICON or entry.overrideIcon == TAXI_ICON then
    return true
  end
  local name = string.lower(entry.name or "")
  if name:find("fly ", 1, true) or name:find("flight", 1, true) or name:find("taxi", 1, true) then
    return true
  end
  return false
end

local function GossipOpen()
  local gossip = _G.GossipFrame
  if not gossip or not gossip.IsShown then
    return true
  end
  local ok, shown = pcall(gossip.IsShown, gossip)
  if not ok or IsSecret(shown) then
    return true
  end
  return shown == true or shown == 1
end

local function HandleGossip(attempt)
  attempt = attempt or 0
  if not FTK:IsEnabled(MODULE_ID) or ShiftHeld() then
    return
  end
  if not GossipOpen() then
    if attempt < 4 and C_Timer and C_Timer.After then
      C_Timer.After(0.1, function()
        HandleGossip(attempt + 1)
      end)
    end
    return
  end
  local options = GossipOptions()
  local quests = GossipQuestCount()

  -- Flight Direct: any taxi gossip option → select it.
  local i
  for i = 1, #options do
    local entry = options[i]
    if IsTaxiEntry(entry) then
      SelectOption(entry)
      return
    end
  end

  -- Gossip Skip: exactly one non-quest option and no quest lines on this gossip.
  if quests == 0 and #options == 1 and not OptionBlocked(options[1]) then
    SelectOption(options[1])
    return
  end

  -- Forever sometimes fires GOSSIP_SHOW before the option list is filled.
  if #options == 0 and attempt < 4 and C_Timer and C_Timer.After then
    C_Timer.After(0.1, function()
      HandleGossip(attempt + 1)
    end)
  end
end

frame:SetScript("OnEvent", function(_, event)
  if event == "GOSSIP_SHOW" then
    -- Brief delay so gossip option APIs populate on Forever.
    if C_Timer and C_Timer.After then
      C_Timer.After(0.05, HandleGossip)
    else
      HandleGossip()
    end
  end
end)

FTK:RegisterModule({
  id = MODULE_ID,
  name = "NPC Assist",
  description = "Skips single non-quest gossip and opens the flight map at flight masters. Hold Shift for normal talk.",
  defaultEnabled = true,
  onEnable = function()
    pcall(frame.RegisterEvent, frame, "GOSSIP_SHOW")
  end,
  onDisable = function()
    frame:UnregisterAllEvents()
  end,
})
