--[[
  Sells poor-quality junk when a merchant window opens.
  Quest items are kept. Slots with a secret or missing item id are skipped.
]]

local FTK = ForeverToolkit
if not FTK then
  error("ForeverToolkit: Core.lua must load before Modules/AutoSellJunk.lua")
end

local MODULE_ID = "AutoSellJunk"

local frame = CreateFrame("Frame")
local queue
local selling = false
local session = 0

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

local function MerchantOpen()
  if not MerchantFrame or not MerchantFrame.IsShown then
    return false
  end
  local ok, shown = pcall(MerchantFrame.IsShown, MerchantFrame)
  return ok and shown == true
end

local function BagCount()
  local last = 4
  if _G.NUM_BAG_SLOTS then
    local count = PlainNumber(_G.NUM_BAG_SLOTS)
    if count and count > last then
      last = count
    end
  end
  local reagent = Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag
  reagent = PlainNumber(reagent)
  if reagent and reagent > last then
    last = reagent
  end
  return last
end

local function SlotCount(bag)
  if not (C_Container and C_Container.GetContainerNumSlots) then
    return 0
  end
  local ok, count = pcall(C_Container.GetContainerNumSlots, bag)
  return ok and PlainNumber(count) or 0
end

local function ItemRecord(bag, slot)
  if not (C_Container and C_Container.GetContainerItemInfo) then
    return nil
  end
  local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
  if not ok or type(info) ~= "table" then
    return nil
  end
  local itemID = PlainNumber(info.itemID)
  if not itemID then
    return nil
  end
  local quality = PlainNumber(info.quality)
  if quality == nil and C_Item and C_Item.GetItemQualityByID then
    local qualityOk, qualityValue = pcall(C_Item.GetItemQualityByID, itemID)
    if qualityOk then
      quality = PlainNumber(qualityValue)
    end
  end
  if quality == nil then
    local link = PlainString(info.hyperlink)
    if link and link:find("cff9d9d9d", 1, true) then
      quality = 0
    end
  end
  local locked = info.isLocked
  if IsSecret(locked) then
    locked = true
  end
  local noValue = info.hasNoValue
  if IsSecret(noValue) then
    return nil
  end
  local quest = false
  if C_Container.GetContainerItemQuestInfo then
    local questOk, questInfo = pcall(C_Container.GetContainerItemQuestInfo, bag, slot)
    if questOk and type(questInfo) == "table" then
      local questID = PlainNumber(questInfo.questID)
      local isQuest = questInfo.isQuestItem
      if IsSecret(isQuest) then
        quest = true
      elseif isQuest == true or (questID and questID > 0) then
        quest = true
      end
    end
  end
  return {
    itemID = itemID,
    quality = quality,
    locked = locked == true,
    noValue = noValue == true,
    quest = quest,
  }
end

local function IsJunk(record)
  if not record or record.quest or record.noValue or record.quality == nil then
    return false
  end
  local poor = Enum and Enum.ItemQuality and Enum.ItemQuality.Poor
  return record.quality == 0 or (poor ~= nil and record.quality == poor)
end

local function BuildQueue()
  local list = {}
  local bag
  for bag = 0, BagCount() do
    local slots = SlotCount(bag)
    local slot
    for slot = 1, slots do
      local record = ItemRecord(bag, slot)
      if IsJunk(record) then
        list[#list + 1] = { bag = bag, slot = slot, tries = 0 }
      end
    end
  end
  return list
end

local function SellSlot(bag, slot)
  if ShowMerchantSellCursor then
    pcall(ShowMerchantSellCursor, 1)
  elseif SetCursor then
    pcall(SetCursor, "BUY_CURSOR")
  end
  local sold = false
  if C_Container and C_Container.UseContainerItem then
    sold = pcall(C_Container.UseContainerItem, bag, slot)
  elseif UseContainerItem then
    sold = pcall(UseContainerItem, bag, slot)
  end
  if ResetCursor then
    pcall(ResetCursor)
  end
  return sold
end

local function Later(delay, callback)
  if C_Timer and C_Timer.After then
    C_Timer.After(delay, callback)
    return true
  end
  return false
end

local function SellNext()
  if not selling or not queue or not FTK:IsEnabled(MODULE_ID) or not MerchantOpen() then
    selling = false
    queue = nil
    return
  end
  while queue[1] do
    local entry = queue[1]
    local record = ItemRecord(entry.bag, entry.slot)
    if not IsJunk(record) then
      table.remove(queue, 1)
    elseif record.locked then
      entry.tries = entry.tries + 1
      if entry.tries > 5 then
        table.remove(queue, 1)
      elseif not Later(0.2, SellNext) then
        table.remove(queue, 1)
      else
        return
      end
    else
      SellSlot(entry.bag, entry.slot)
      table.remove(queue, 1)
      if not Later(0.15, SellNext) then
        SellNext()
      end
      return
    end
  end
  selling = false
  queue = nil
end

local function StartSelling(attempt)
  attempt = attempt or 0
  if attempt == 0 then
    session = session + 1
    selling = false
    queue = nil
  end
  local token = session
  if not FTK:IsEnabled(MODULE_ID) then
    return
  end
  if not MerchantOpen() then
    if attempt < 10 then
      Later(0.1, function()
        if session == token then
          StartSelling(attempt + 1)
        end
      end)
    else
      FTK:Print("Auto-sell junk: the merchant window was not ready.")
    end
    return
  end
  queue = BuildQueue()
  if #queue == 0 then
    queue = nil
    selling = false
    FTK:Print("Auto-sell junk: no grey items to sell.")
    return
  end
  selling = true
  FTK:Print("Auto-sell junk: selling " .. #queue .. " grey items.")
  if not Later(0.1, SellNext) then
    SellNext()
  end
end

local function HookMerchantFrame()
  local merchant = _G.MerchantFrame
  if not merchant or merchant.ftkAutoSellHook or not merchant.HookScript then
    return
  end
  merchant.ftkAutoSellHook = true
  merchant:HookScript("OnShow", function()
    StartSelling(0)
  end)
end

frame:SetScript("OnEvent", function(_, event)
  if event == "MERCHANT_CLOSED" then
    session = session + 1
    selling = false
    queue = nil
    return
  end
  if event == "MERCHANT_SHOW" then
    HookMerchantFrame()
    StartSelling(0)
  end
end)

FTK:RegisterModule({
  id = MODULE_ID,
  name = "Auto-sell junk",
  description = "Sells grey junk items when you open a merchant. Quest items are kept.",
  defaultEnabled = true,
  onEnable = function()
    frame:RegisterEvent("MERCHANT_SHOW")
    frame:RegisterEvent("MERCHANT_CLOSED")
    HookMerchantFrame()
    if MerchantOpen() then
      StartSelling(0)
    end
  end,
  onDisable = function()
    frame:UnregisterAllEvents()
    selling = false
    queue = nil
  end,
})
