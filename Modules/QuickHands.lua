--[[
  Ninjee Loot. When the loot window opens in auto-loot mode, every slot
  is taken immediately instead of one item at a time.

  The auto-loot key follows the normal window: if auto-loot is on, holding
  the key leaves the window alone, and if auto-loot is off, holding the
  key takes everything. A second corpse opened too quickly is picked up
  once the client will accept another loot.
]]

local FTK = ForeverForge
if not FTK then
  error("ForeverForge: Core.lua must load before Modules/QuickHands.lua")
end

local MODULE_ID = "QuickHands"
local GAP = 0.3

local lastTake = 0
local waitToken = 0

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

local function AsFlag(value)
  if IsSecret(value) then
    return nil
  end
  if value == true or value == 1 then
    return true
  end
  if value == false or value == 0 or value == nil then
    return false
  end
  return nil
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

local function CancelWait()
  waitToken = waitToken + 1
end

local function Wait(seconds, callback)
  waitToken = waitToken + 1
  local token = waitToken
  if not (C_Timer and C_Timer.After) then
    return false
  end
  C_Timer.After(seconds, function()
    if token == waitToken and FTK:IsEnabled(MODULE_ID) then
      callback()
    end
  end)
  return true
end

-- Auto-loot is on when the saved setting and the auto-loot key disagree.
-- That is the same choice the normal loot window makes.
local function AutoLootWanted(eventFlag)
  local auto = nil
  if GetCVarBool then
    local ok, value = pcall(GetCVarBool, "autoLootDefault")
    if ok then
      auto = AsFlag(value)
    end
  end
  local held = nil
  if IsModifiedClick then
    local ok, value = pcall(IsModifiedClick, "AUTOLOOTTOGGLE")
    if ok then
      held = AsFlag(value)
    end
  end
  if auto ~= nil and held ~= nil then
    return auto ~= held
  end
  local fromEvent = AsFlag(eventFlag)
  if fromEvent ~= nil then
    return fromEvent
  end
  return false
end

local function SlotCount()
  if not GetNumLootItems then
    return nil
  end
  local ok, value = pcall(GetNumLootItems)
  if not ok then
    return nil
  end
  return PlainNumber(value)
end

local function SlotHasItem(slot)
  if not LootSlotHasItem then
    return true
  end
  local ok, value = pcall(LootSlotHasItem, slot)
  if not ok or IsSecret(value) then
    return true
  end
  return value == true
end

-- Higher slots first so taking one entry does not renumber the rest.
local function TakeAll()
  local count = SlotCount()
  if not count or count < 1 or not LootSlot then
    return 0
  end
  local taken = 0
  local slot = count
  while slot >= 1 do
    if SlotHasItem(slot) then
      local ok = pcall(LootSlot, slot)
      if ok then
        taken = taken + 1
      end
    end
    slot = slot - 1
  end
  return taken
end

local function TryTake(wanted, lookedAgain)
  if wanted ~= true or not FTK:IsEnabled(MODULE_ID) then
    return
  end
  local now = Now()
  local since = now - lastTake
  if lastTake > 0 and since < GAP then
    Wait(GAP - since, function()
      TryTake(true, lookedAgain)
    end)
    return
  end
  local taken = TakeAll()
  if taken > 0 then
    lastTake = Now()
    return
  end
  if not lookedAgain then
    Wait(0, function()
      TryTake(true, true)
    end)
  end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, autoFlag)
  if not FTK:IsEnabled(MODULE_ID) then
    return
  end
  if event == "LOOT_CLOSED" then
    CancelWait()
    return
  end
  if event == "LOOT_READY" then
    CancelWait()
    TryTake(AutoLootWanted(autoFlag), false)
  end
end)

FTK:RegisterModule({
  id = MODULE_ID,
  name = "Ninjee Loot",
  description = "Takes every loot slot immediately when auto-loot is on. The auto-loot key follows the same rule as the normal loot window.",
  defaultEnabled = true,
  onEnable = function()
    events:RegisterEvent("LOOT_READY")
    events:RegisterEvent("LOOT_CLOSED")
  end,
  onDisable = function()
    events:UnregisterAllEvents()
    CancelWait()
  end,
})
