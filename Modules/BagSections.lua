--[[
  Splits the combined backpack into labeled groups:
  Quest Items, Munitions, Reagents, Crafting, one section per saved equipment set,
  Gear, General, Junk (poor quality), then Empty.

  Only runs while the combined backpack is the bag UI.
  Item buttons stay Blizzard's buttons, so click, drag, and tooltips
  keep working. A secret item id is left in General.

  On a mouse client the combined grid still stops at the fourth bag.
  The reagent bag (bag 5) is then drawn on buttons this addon owns.
  Forever's gamepad bags, and retail once 12.1.7 ships, already put
  that bag in the combined grid. Those buttons stay Blizzard's.

  Either way the click stays ContainerFrameItemButton_OnClick. That
  click sells while the merchant buy tab is open, and uses the item
  otherwise. Initialize stores the bag id as the secure "bagid"
  attribute. Replacing GetBagID or OnClick taints that click, so
  UseContainerItem never sells. Do not call OpenBag for the reagent
  bag. On this client that opens the combined backpack.

  Grouping taints the combined frame. A tainted frame will not open
  from this addon's own button during combat, but Blizzard's bag
  button still can. B and the other bag keys click that button, so
  the bags open in combat and an item can be used. Out of combat the
  same click opens the combined backpack, and the groups are applied
  once that click has returned.
]]

local FTK = ForeverForge
if not FTK then
  error("ForeverForge: Core.lua must load before Modules/BagSections.lua")
end

local MODULE_ID = "BagSections"
local ITEM_GAP_X = 5
local ITEM_GAP_Y = 5
local HEADER_H = 20
local SECTION_GAP = 8
local TOP_OFFSET = 68
local BOTTOM_PAD = 28

local hooked = false
local layingOut = false
local restoring = false
local openingReagent = false
local closingReagent = false
local reagentOpenTried = false
local layoutAfterCombat = false
local layoutQueued = false
local layoutFollowUp = false
local parkedReagentButtons = {}
local reagentHolder
local ownedReagentButtons = {}
local layoutPoints
local bagKey
local combatBags
local combatButtons = {}
local combatHeaders = {}
local combatHeaderUsed = 0
local releaseBagKey = false
local reagentReturnAfterCombat = false
local DeferLayout
local StoreFrameRef
local headerPool = {}
local headerUsed = 0

local SECTIONS = {
  { id = "quest", title = "Quest Items" },
  { id = "consumable", title = "Consumables" },
  { id = "munitions", title = "Munitions" },
  { id = "junk", title = "Junk" },
  { id = "spellreagent", title = "Reagents" },
  { id = "reagent", title = "Crafting" },
  { id = "gear", title = "Gear" },
  { id = "other", title = "General" },
  { id = "empty", title = "Empty" },
}

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

local function UsingCombinedBags()
  if ContainerFrameSettingsManager and ContainerFrameSettingsManager.IsUsingCombinedBags then
    local ok, value = pcall(ContainerFrameSettingsManager.IsUsingCombinedBags, ContainerFrameSettingsManager)
    if ok and not IsSecret(value) then
      return value == true
    end
  end
  if GetCVarBool then
    local ok, value = pcall(GetCVarBool, "combinedBags")
    if ok and not IsSecret(value) then
      return value == true
    end
  end
  return false
end

local function CombinedFrame()
  local frame = _G.ContainerFrameCombinedBags
  if frame and frame.IsCombinedBagContainer and frame:IsCombinedBagContainer() then
    return frame
  end
  return nil
end

-- Forever's fifth bag slot. Retail's reagent bag uses this same id, and
-- Blizzard's combined grid does not include it.
local function ReagentBagId()
  local id = Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag
  id = PlainNumber(id)
  if id then
    return id
  end
  return 5
end

local function ReagentSlotCount()
  if not (C_Container and C_Container.GetContainerNumSlots) then
    return 0
  end
  local ok, count = pcall(C_Container.GetContainerNumSlots, ReagentBagId())
  count = ok and PlainNumber(count) or nil
  if not count or count < 1 then
    return 0
  end
  return count
end

local function HiddenFrameForBag(bagId)
  if not bagId then
    return nil
  end
  local limit = PlainNumber(_G.NUM_CONTAINER_FRAMES) or 13
  local index
  for index = 1, limit do
    local frame = _G["ContainerFrame" .. index]
    if frame and frame.GetBagID then
      local ok, id = pcall(frame.GetBagID, frame)
      id = ok and PlainNumber(id) or nil
      if id == bagId then
        return frame
      end
    end
  end
  return nil
end

local function ShownFrameForBag(bagId)
  if not bagId then
    return nil
  end
  if ContainerFrameUtil_GetShownFrameForID then
    local ok, frame = pcall(ContainerFrameUtil_GetShownFrameForID, bagId)
    if ok and frame then
      return frame
    end
  end
  local limit = PlainNumber(_G.NUM_CONTAINER_FRAMES) or 13
  local index
  for index = 1, limit do
    local frame = _G["ContainerFrame" .. index]
    if frame and frame.GetBagID and frame.IsShown and frame:IsShown() then
      local ok, id = pcall(frame.GetBagID, frame)
      id = ok and PlainNumber(id) or nil
      if id == bagId then
        return frame
      end
    end
  end
  return nil
end

local function ItemClass(itemID)
  if not itemID or not (C_Item and C_Item.GetItemInfoInstant) then
    return nil
  end
  local ok, _, _, _, _, _, classID = pcall(C_Item.GetItemInfoInstant, itemID)
  if not ok then
    return nil
  end
  return PlainNumber(classID)
end

local function ItemTypeName(itemID)
  if not itemID or not (C_Item and C_Item.GetItemInfoInstant) then
    return nil
  end
  local ok, _, itemType = pcall(C_Item.GetItemInfoInstant, itemID)
  if not ok then
    return nil
  end
  return PlainString(itemType)
end

local function MaterialKind(itemID)
  local classID = ItemClass(itemID)
  local itemClass = Enum and Enum.ItemClass
  local reagentClass = (itemClass and itemClass.Reagent) or 5
  local tradeClass = (itemClass and itemClass.Tradegoods) or 7
  if classID == reagentClass then
    return "spellreagent"
  end
  if classID == tradeClass then
    return "reagent"
  end
  local itemType = ItemTypeName(itemID)
  if itemType == "Reagent" then
    return "spellreagent"
  end
  if itemType == "Trade Goods" then
    return "reagent"
  end
  return nil
end

local function IsConsumable(itemID)
  local classID = ItemClass(itemID)
  local consumableClass = (Enum and Enum.ItemClass and Enum.ItemClass.Consumable) or 0
  if classID == consumableClass then
    return true
  end
  return ItemTypeName(itemID) == "Consumable"
end

local function IsMunition(itemID)
  local classID = ItemClass(itemID)
  local itemClass = Enum and Enum.ItemClass
  local projectile = (itemClass and itemClass.Projectile) or 6
  local quiver = (itemClass and itemClass.Quiver) or 11
  if classID == projectile or classID == quiver then
    return true
  end
  local itemType = ItemTypeName(itemID)
  return itemType == "Projectile" or itemType == "Quiver"
end

local function EquipLoc(itemID)
  if not itemID or not (C_Item and C_Item.GetItemInfoInstant) then
    return nil
  end
  local ok, _, _, _, equipLoc = pcall(C_Item.GetItemInfoInstant, itemID)
  if not ok then
    return nil
  end
  return PlainString(equipLoc)
end

local function IsGear(itemID)
  local classID = ItemClass(itemID)
  local itemClass = Enum and Enum.ItemClass
  local weapon = (itemClass and itemClass.Weapon) or 2
  local armor = (itemClass and itemClass.Armor) or 4
  if classID ~= weapon and classID ~= armor then
    return false
  end
  local loc = EquipLoc(itemID)
  if loc == "INVTYPE_BAG" or loc == "INVTYPE_QUIVER" or loc == "INVTYPE_AMMO" then
    return false
  end
  return true
end

local function IsQuestClass(classID)
  local itemClass = Enum and Enum.ItemClass
  if itemClass and itemClass.Questitem and classID == itemClass.Questitem then
    return true
  end
  return classID == 12
end

local function LocationBagSlot(location)
  location = PlainNumber(location)
  if not location or location <= 1 then
    return nil, nil
  end
  if EquipmentManager_UnpackLocation then
    local ok, player, bank, bags, fourth, fifth, sixth = pcall(EquipmentManager_UnpackLocation, location)
    if ok and bags == true and not IsSecret(bags) then
      local slot, bag
      if type(fourth) == "boolean" then
        slot = PlainNumber(fifth)
        bag = PlainNumber(sixth)
      else
        slot = PlainNumber(fourth)
        bag = PlainNumber(fifth)
      end
      if bag and slot then
        return bag, slot
      end
    end
  end
  if not (bit and bit.band and bit.rshift and bit.lshift) then
    return nil, nil
  end
  local bagsFlag = _G.ITEM_INVENTORY_LOCATION_BAGS or 0x400000
  local bankFlag = _G.ITEM_INVENTORY_LOCATION_BANK or 0x200000
  local playerFlag = _G.ITEM_INVENTORY_LOCATION_PLAYER or 0x100000
  local shift = _G.ITEM_INVENTORY_BAG_BIT_OFFSET or 8
  if bit.band(location, bagsFlag) == 0 or bit.band(location, bankFlag) ~= 0 then
    return nil, nil
  end
  local packed = location - bagsFlag
  if bit.band(location, playerFlag) ~= 0 then
    packed = packed - playerFlag
  end
  local bag = bit.rshift(packed, shift)
  local slot = packed - bit.lshift(bag, shift)
  bag = PlainNumber(bag)
  slot = PlainNumber(slot)
  if bag and slot then
    return bag, slot
  end
  return nil, nil
end

local function RememberItemID(map, itemID, setName)
  itemID = PlainNumber(itemID)
  if itemID and itemID > 0 and not map[itemID] then
    map[itemID] = setName
  end
end

local function EquipmentSetMaps()
  local byItem = {}
  local bySlot = {}
  local api = C_EquipmentSet
  if not (api and api.GetEquipmentSetInfo) then
    return byItem, bySlot
  end
  local setIDs = {}
  if api.GetEquipmentSetIDs then
    local ok, ids = pcall(api.GetEquipmentSetIDs)
    if ok and type(ids) == "table" then
      local index
      for index = 1, #ids do
        local setID = PlainNumber(ids[index])
        if setID then
          setIDs[#setIDs + 1] = setID
        end
      end
    end
  end
  if #setIDs == 0 and api.GetNumEquipmentSets then
    local ok, count = pcall(api.GetNumEquipmentSets)
    count = ok and PlainNumber(count) or nil
    local index
    if count and count > 0 then
      for index = 0, count do
        setIDs[#setIDs + 1] = index
      end
    end
  end
  local sets = {}
  local index
  for index = 1, #setIDs do
    local infoOk, name, _, setID = pcall(api.GetEquipmentSetInfo, setIDs[index])
    name = infoOk and PlainString(name) or nil
    setID = infoOk and PlainNumber(setID) or PlainNumber(setIDs[index])
    if name and setID then
      local seen = false
      local existing
      for existing = 1, #sets do
        if sets[existing].id == setID then
          seen = true
        end
      end
      if not seen then
        sets[#sets + 1] = { name = name, id = setID }
      end
    end
  end
  table.sort(sets, function(a, b)
    return a.name < b.name
  end)
  for index = 1, #sets do
    local set = sets[index]
    if api.GetItemIDs then
      local idsOk, ids = pcall(api.GetItemIDs, set.id)
      if idsOk and type(ids) == "table" then
        local slot
        for slot = 0, 19 do
          RememberItemID(byItem, ids[slot], set.name)
        end
        for _, itemID in pairs(ids) do
          RememberItemID(byItem, itemID, set.name)
        end
      end
    end
    if api.GetItemLocations then
      local locOk, locations = pcall(api.GetItemLocations, set.id)
      if locOk and type(locations) == "table" then
        local slot
        for slot = 0, 19 do
          local bag, bagSlot = LocationBagSlot(locations[slot])
          if bag and bagSlot then
            local key = (bag * 100) + bagSlot
            if not bySlot[key] then
              bySlot[key] = set.name
            end
          end
        end
      end
    end
  end
  return byItem, bySlot
end

local function ContainerSetName(bag, slot)
  if not (C_Container and C_Container.GetContainerItemEquipmentSetInfo) then
    return nil
  end
  local ok, inSet, setList = pcall(C_Container.GetContainerItemEquipmentSetInfo, bag, slot)
  if not ok then
    return nil
  end
  if IsSecret(inSet) or (inSet ~= true and type(setList) ~= "table" and type(setList) ~= "string") then
    return nil
  end
  if type(setList) == "string" then
    local name = PlainString(setList)
    if not name then
      return nil
    end
    local first = name:match("^[^,]+")
    if first then
      first = first:gsub("^%s+", ""):gsub("%s+$", "")
    end
    return PlainString(first)
  end
  if type(setList) == "table" then
    local index
    for index = 1, #setList do
      local name = PlainString(setList[index])
      if name then
        return name
      end
    end
  end
  return nil
end

local function ButtonBagSlot(button)
  local bag, slot
  if button.GetBagID then
    local ok, value = pcall(button.GetBagID, button)
    if ok then
      bag = PlainNumber(value)
    end
  end
  if button.GetID then
    local ok, value = pcall(button.GetID, button)
    if ok then
      slot = PlainNumber(value)
    end
  end
  return bag, slot
end

local function ReadItem(bag, slot)
  if not bag or not slot or not (C_Container and C_Container.GetContainerItemInfo) then
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
  local quest = false
  if C_Container.GetContainerItemQuestInfo then
    local questOk, questInfo = pcall(C_Container.GetContainerItemQuestInfo, bag, slot)
    if questOk and type(questInfo) == "table" then
      local questID = PlainNumber(questInfo.questID)
      local isQuest = questInfo.isQuestItem
      if not IsSecret(isQuest) and isQuest == true then
        quest = true
      elseif questID and questID > 0 then
        quest = true
      end
    end
  end
  return {
    itemID = itemID,
    quality = quality,
    quest = quest,
  }
end

local function CategoryFor(item, bag, slot, setByItem, setBySlot)
  if item.quest or IsQuestClass(ItemClass(item.itemID)) then
    return "quest"
  end
  if IsConsumable(item.itemID) then
    return "consumable"
  end
  local poor = Enum and Enum.ItemQuality and Enum.ItemQuality.Poor
  if item.quality ~= nil and (item.quality == 0 or (poor ~= nil and item.quality == poor)) then
    return "junk"
  end
  if IsMunition(item.itemID) then
    return "munitions"
  end
  local material = MaterialKind(item.itemID)
  if material then
    return material
  end
  local setName = ContainerSetName(bag, slot)
  if not setName and bag and slot then
    setName = setBySlot[(bag * 100) + slot]
  end
  if not setName then
    setName = setByItem[item.itemID]
  end
  if setName then
    return "set:" .. setName, "Equipment Set: " .. setName
  end
  if IsGear(item.itemID) then
    return "gear"
  end
  return "other"
end

local function CollectButtons(frame)
  local buttons = {}
  if frame.EnumerateValidItems then
    local ok, iter, state, index = pcall(frame.EnumerateValidItems, frame)
    if ok and iter then
      for _, button in iter, state, index do
        if button then
          buttons[#buttons + 1] = button
        end
      end
      if #buttons > 0 then
        return buttons
      end
    end
  end
  if type(frame.Items) == "table" then
    local index
    for index = 1, #frame.Items do
      buttons[#buttons + 1] = frame.Items[index]
    end
  end
  return buttons
end

local function ButtonsIncludeBag(buttons, bagId)
  local index
  for index = 1, #buttons do
    local bag = ButtonBagSlot(buttons[index])
    if bag == bagId then
      return true
    end
  end
  return false
end

local function ParkReagentFrame(reagent)
  if not reagent or not reagent.ClearAllPoints or not reagent.SetPoint then
    return
  end
  if DeferLayout and DeferLayout(reagent) then
    return
  end
  if reagent.EnableMouse then
    reagent:EnableMouse(false)
  end
  reagent:ClearAllPoints()
  reagent:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -4000, 4000)
end

-- B hides the combined backpack and leaves every other open bag where
-- the anchor pass puts it. The reagent frame was only opened so its
-- buttons could move into the combined window, so close it too.
local function DismissReagentFrame()
  if closingReagent or openingReagent or restoring or layingOut then
    return
  end
  if not FTK:IsEnabled(MODULE_ID) or not UsingCombinedBags() then
    return
  end
  local reagentId = ReagentBagId()
  local reagent = ShownFrameForBag(reagentId)
  local combined = CombinedFrame()
  if not reagent or reagent == combined then
    return
  end
  closingReagent = true
  -- CloseBag(reagent) closes the whole combined backpack when that bag
  -- is part of it. Hide the separate window directly.
  local closesCombined = false
  if ContainerFrameSettingsManager and ContainerFrameSettingsManager.IsUsingCombinedBags then
    local ok, value = pcall(ContainerFrameSettingsManager.IsUsingCombinedBags, ContainerFrameSettingsManager, reagentId)
    closesCombined = ok and value == true
  end
  if not closesCombined and CloseBag then
    pcall(CloseBag, reagentId)
  elseif reagent.Hide then
    reagent:Hide()
  end
  closingReagent = false
end

local ReturnReagentButtons

local function RestoreReagentFrame()
  if ReturnReagentButtons then
    ReturnReagentButtons()
  end
  local reagent = ShownFrameForBag(ReagentBagId())
  if not reagent then
    return
  end
  local buttons = CollectButtons(reagent)
  local index
  for index = 1, #buttons do
    local button = buttons[index]
    if button.SetParent and not button.ftkOwnedReagent then
      pcall(button.SetParent, button, reagent)
    end
  end
  if reagent.EnableMouse then
    reagent:EnableMouse(true)
  end
  if reagent.UpdateItemLayout then
    pcall(reagent.UpdateItemLayout, reagent)
  end
end

local function PaintOwnedReagentButton(button, bag, slot)
  local info
  if C_Container and C_Container.GetContainerItemInfo then
    local ok, value = pcall(C_Container.GetContainerItemInfo, bag, slot)
    if ok and type(value) == "table" then
      info = value
    end
  end
  local texture = info and info.iconFileID
  if SetItemButtonTexture then
    SetItemButtonTexture(button, texture)
  end
  if SetItemButtonCount then
    SetItemButtonCount(button, info and info.stackCount or 0)
  end
  if SetItemButtonQuality then
    pcall(SetItemButtonQuality, button, info and info.quality, info and info.hyperlink, false, info and info.isBound)
  end
  if button.SetHasItem then
    pcall(button.SetHasItem, button, texture)
  end
  if button.UpdateQuestItem and C_Container and C_Container.GetContainerItemQuestInfo then
    local questOk, questInfo = pcall(C_Container.GetContainerItemQuestInfo, bag, slot)
    if questOk and type(questInfo) == "table" then
      pcall(button.UpdateQuestItem, button, questInfo.isQuestItem, questInfo.questID, questInfo.isActive)
    end
  end
end

-- Forever 1.60.1 and retail 12.1.7 take the container. Older retail
-- takes the bag and the slot. IsCombined arrived with the container
-- argument. A 3-arg call on the old function would store the frame
-- as the bag id.
local function InitializeReagentButton(button, holder, bag, slot)
  if type(button.Initialize) ~= "function" then
    if button.SetBagID then
      button:SetBagID(bag)
    end
    button:SetID(slot)
    if button.Show then
      button:Show()
    end
    return
  end
  local takesContainer = type(button.IsCombined) == "function"
  if not takesContainer and type(debug) == "table" and type(debug.getinfo) == "function" then
    local ok, info = pcall(debug.getinfo, button.Initialize, "u")
    if ok and type(info) == "table" then
      local params = PlainNumber(info.nparams)
      if params and params >= 4 then
        takesContainer = true
      end
    end
  end
  if takesContainer then
    button:Initialize(holder, bag, slot)
  else
    button:Initialize(bag, slot)
  end
end

-- Reagent slots that the combined grid did not draw. OpenBag(reagent)
-- opens the combined backpack on this client, so these buttons are
-- created here instead.
local function OwnedReagentButtons(combined)
  local bag = ReagentBagId()
  local count = ReagentSlotCount()
  if not bag or count < 1 then
    local index
    for index = 1, #ownedReagentButtons do
      ownedReagentButtons[index]:Hide()
    end
    return {}
  end
  if not reagentHolder then
    reagentHolder = CreateFrame("Frame", "ForeverForgeReagentHolder", UIParent)
    reagentHolder:SetSize(1, 1)
    reagentHolder:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -3000, 3000)
    reagentHolder:SetID(bag)
    reagentHolder.GetBagID = function()
      return ReagentBagId()
    end
    reagentHolder.IsCombinedBagContainer = function()
      return false
    end
    reagentHolder:Hide()
  end
  local width, height = 37, 37
  local sample = combined and type(combined.Items) == "table" and combined.Items[1]
  if sample and sample.GetWidth then
    local sampleWidth = PlainNumber(sample:GetWidth())
    local sampleHeight = PlainNumber(sample:GetHeight())
    if sampleWidth and sampleWidth >= 20 then
      width = sampleWidth
    end
    if sampleHeight and sampleHeight >= 20 then
      height = sampleHeight
    end
  end
  local shown = {}
  local slot
  for slot = 1, count do
    local button = ownedReagentButtons[slot]
    if not button then
      local name = "ForeverForgeReagentButton" .. slot
      local created, made = pcall(CreateFrame, "ItemButton", name, reagentHolder, "ContainerFrameItemButtonTemplate")
      if created and type(made) == "table" then
        button = made
      elseif type(_G[name]) == "table" then
        button = _G[name]
      else
        local fallbackOk, fallback = pcall(CreateFrame, "ItemButton", name, reagentHolder, "ItemButtonTemplate")
        if fallbackOk and type(fallback) == "table" then
          button = fallback
        end
      end
      if button then
        button.ftkOwnedReagent = true
        ownedReagentButtons[slot] = button
      end
    end
    if button then
      button.ftkOwnedReagent = true
      local overlay = button.ftkUseOverlay
      if overlay and overlay.Hide then
        overlay:Hide()
      end
      -- Forever 1.60 and retail 12.1.7: Initialize(container, bag, slot).
      -- Older retail: Initialize(bag, slot). The container is only asked
      -- whether the slot is combined. The bag id has to go through
      -- SetBagID so the template click stays untainted and can sell.
      InitializeReagentButton(button, reagentHolder, bag, slot)
      button:SetSize(width, height)
      PaintOwnedReagentButton(button, bag, slot)
      shown[#shown + 1] = button
    end
  end
  local extra
  for extra = count + 1, #ownedReagentButtons do
    ownedReagentButtons[extra]:Hide()
  end
  return shown
end

local function HideOwnedReagentButtons()
  local index
  for index = 1, #ownedReagentButtons do
    local button = ownedReagentButtons[index]
    if button then
      parkedReagentButtons[button] = nil
      if reagentHolder and button.SetParent then
        pcall(button.SetParent, button, reagentHolder)
      end
      if button.Hide then
        button:Hide()
      end
    end
  end
end

local function AttachReagentButtons(combined, buttons)
  local reagentId = ReagentBagId()
  if not reagentId then
    return
  end
  if ButtonsIncludeBag(buttons, reagentId) then
    -- The combined grid already has this bag. A second set of slots
    -- would sell the wrong stack, and reparenting Blizzard's buttons
    -- is what blocks the backpack during combat.
    HideOwnedReagentButtons()
    local already = ShownFrameForBag(reagentId)
    if already and already ~= combined then
      ParkReagentFrame(already)
    end
    return
  end
  local owned = OwnedReagentButtons(combined)
  local index
  for index = 1, #owned do
    buttons[#buttons + 1] = owned[index]
  end
  local reagent = ShownFrameForBag(reagentId)
  if reagent and reagent ~= combined then
    ParkReagentFrame(reagent)
  end
end

-- Labels and owned reagent buttons live on our own frame, not on the
-- protected backpack. Hiding that frame in combat does not call Show,
-- Raise, or SetSize on the backpack.
-- The backpack is a raised top-level window. A sibling at the same
-- strata stays under its background, so the labels are one strata up.
local bagChrome

local NEXT_STRATA = {
  WORLD = "BACKGROUND",
  BACKGROUND = "LOW",
  LOW = "MEDIUM",
  MEDIUM = "HIGH",
  HIGH = "DIALOG",
  DIALOG = "FULLSCREEN",
  FULLSCREEN = "FULLSCREEN_DIALOG",
  FULLSCREEN_DIALOG = "TOOLTIP",
  TOOLTIP = "TOOLTIP",
}

local function BagChrome()
  if not bagChrome then
    bagChrome = CreateFrame("Frame", "ForeverForgeBagChrome", UIParent)
    bagChrome:SetSize(1, 1)
    bagChrome:EnableMouse(false)
    if bagChrome.EnableMouseWheel then
      bagChrome:EnableMouseWheel(false)
    end
    bagChrome:Hide()
  end
  -- Reagent slots are parented here. Classic bag clicks read the
  -- parent's id, and the retail mixin asks the parent for its bag id.
  local bag = ReagentBagId()
  if bag and bagChrome.SetID then
    bagChrome:SetID(bag)
  end
  bagChrome.GetBagID = function()
    return ReagentBagId()
  end
  bagChrome.IsCombinedBagContainer = function()
    return false
  end
  return bagChrome
end

local function ShowBagChrome(frame)
  local chrome = BagChrome()
  if frame then
    chrome:ClearAllPoints()
    chrome:SetAllPoints(frame)
  end
  local strata = "DIALOG"
  if frame and frame.GetFrameStrata then
    local ok, value = pcall(frame.GetFrameStrata, frame)
    value = ok and PlainString(value) or nil
    if value and NEXT_STRATA[value] then
      strata = NEXT_STRATA[value]
    end
  end
  chrome:SetFrameStrata(strata)
  local level = 200
  if frame and frame.GetFrameLevel then
    local ok, value = pcall(frame.GetFrameLevel, frame)
    value = ok and PlainNumber(value) or nil
    if value and value + 20 > level then
      level = value + 20
    end
  end
  if level > 10000 then
    level = 10000
  end
  pcall(chrome.SetFrameLevel, chrome, level)
  chrome:EnableMouse(false)
  chrome:Show()
  pcall(chrome.SetFrameLevel, chrome, level)
end

local function AcquireHeader(parent)
  headerUsed = headerUsed + 1
  local host = BagChrome()
  local header = headerPool[headerUsed]
  if not header then
    header = CreateFrame("Frame", nil, host)
    header:SetHeight(HEADER_H)
    local bg = header:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    if bg.SetColorTexture then
      bg:SetColorTexture(0.16, 0.12, 0.05, 0.92)
    end
    local line = header:CreateTexture(nil, "BORDER")
    line:SetPoint("BOTTOMLEFT", 0, 0)
    line:SetPoint("BOTTOMRIGHT", 0, 0)
    line:SetHeight(1)
    if line.SetColorTexture then
      line:SetColorTexture(0.78, 0.64, 0.28, 0.9)
    end
    local label = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", 24, 0)
    label:SetPoint("RIGHT", -8, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetTextColor(0.95, 0.82, 0.4)
    header.label = label
    header:EnableMouse(false)
    if header.EnableMouseWheel then
      header:EnableMouseWheel(false)
    end
    headerPool[headerUsed] = header
  end
  header:EnableMouse(false)
  header:SetParent(BagChrome())
  header:Show()
  return header
end

local function HideUnusedHeaders()
  local index
  for index = headerUsed + 1, #headerPool do
    headerPool[index]:Hide()
  end
end

local function HideCleanBagsChrome()
  if bagChrome then
    bagChrome:Hide()
  end
end

local function ButtonSize(button)
  local width = button and PlainNumber(button:GetWidth()) or nil
  local height = button and PlainNumber(button:GetHeight()) or nil
  if not width or width < 20 then
    width = 37
  end
  if not height or height < 20 then
    height = 37
  end
  return width, height
end

local function LockedDown()
  if type(InCombatLockdown) ~= "function" then
    return false
  end
  local ok, value = pcall(InCombatLockdown)
  if not ok or IsSecret(value) then
    return true
  end
  return value == true
end

-- The bag frame and its item buttons are protected. Moving them during
-- combat is blocked, so the grouped layout waits until combat ends.
DeferLayout = function()
  if not LockedDown() then
    return false
  end
  layoutAfterCombat = true
  return true
end

-- Owned reagent buttons go back to their hidden holder when the
-- backpack closes. Blizzard's own reagent buttons stay on the
-- combined frame. Moving those is what blocks the bag in combat.
function ReturnReagentButtons()
  if LockedDown() then
    return
  end
  local button
  for button in pairs(parkedReagentButtons) do
    parkedReagentButtons[button] = nil
    if button.ftkOwnedReagent and reagentHolder and button.SetParent then
      pcall(button.SetParent, button, reagentHolder)
      if button.Hide then
        button:Hide()
      end
    end
  end
end

local function Place(button, parent, x, y)
  if DeferLayout(button) then
    return
  end
  local bag = ButtonBagSlot(button)
  local ownedReagent = button.ftkOwnedReagent and bag == ReagentBagId()
  if ownedReagent and button.SetParent then
    local host = BagChrome()
    local ok, current = pcall(button.GetParent, button)
    if not ok or current ~= host then
      pcall(button.SetParent, button, host)
    end
  end
  button:ClearAllPoints()
  button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  button:Show()
  if layoutPoints then
    layoutPoints[#layoutPoints + 1] = { button = button, x = x, y = y }
  end
  if ownedReagent then
    parkedReagentButtons[button] = true
    local overlay = button.ftkUseOverlay
    if overlay and overlay.Hide then
      overlay:Hide()
    end
  end
end

-- B is sent to Blizzard's bag button. That button can open the bags
-- during combat. This addon's own button cannot, once grouping has
-- tainted the combined frame.
local BAG_BINDINGS = {
  "TOGGLEBACKPACK",
  "OPENALLBAGS",
  "TOGGLEREAGENTBAG",
  "TOGGLEBAG1",
  "TOGGLEBAG2",
  "TOGGLEBAG3",
  "TOGGLEBAG4",
}

local BAG_BINDING_BUTTON = {
  TOGGLEBACKPACK = "MainMenuBarBackpackButton",
  OPENALLBAGS = "MainMenuBarBackpackButton",
  TOGGLEREAGENTBAG = "CharacterReagentBag0Slot",
  TOGGLEBAG1 = "CharacterBag0Slot",
  TOGGLEBAG2 = "CharacterBag1Slot",
  TOGGLEBAG3 = "CharacterBag2Slot",
  TOGGLEBAG4 = "CharacterBag3Slot",
}

local CombatBagsFrame

local function BindingButton(binding)
  local name = BAG_BINDING_BUTTON[binding]
  if type(name) == "string" and _G[name] then
    return name
  end
  if _G.MainMenuBarBackpackButton then
    return "MainMenuBarBackpackButton"
  end
  return nil
end

local ClearBagKey
local ApplyBagKey

local function PublishBagRefs(button)
  if not button or LockedDown() then
    return
  end
  local bags = CombinedFrame()
  if bags then
    StoreFrameRef(button, "bags", bags)
  end
  if combatBags then
    StoreFrameRef(button, "combat", combatBags)
  end
end

local function RememberCombinedFrame()
  if LockedDown() or not bagKey then
    return
  end
  PublishBagRefs(bagKey)
end

local function EnsureBagKey()
  if bagKey or LockedDown() then
    return bagKey
  end
  local button = CreateFrame("Button", "ForeverForgeBagKey", UIParent)
  if not button then
    return nil
  end
  button:EnableMouse(false)
  button:SetSize(1, 1)
  button:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -2000, 2000)
  button:Show()
  bagKey = button
  return bagKey
end

ClearBagKey = function()
  if not bagKey then
    releaseBagKey = false
    return
  end
  if LockedDown() then
    releaseBagKey = true
    return
  end
  if ClearOverrideBindings then
    pcall(ClearOverrideBindings, bagKey)
  end
  releaseBagKey = false
end

ApplyBagKey = function()
  if not FTK:IsEnabled(MODULE_ID) or not UsingCombinedBags() then
    ClearBagKey()
    return
  end
  if LockedDown() or not GetBindingKey or not SetOverrideBindingClick then
    return
  end
  local key = EnsureBagKey()
  if not key then
    return
  end
  CombatBagsFrame()
  RememberCombinedFrame()
  if ClearOverrideBindings then
    pcall(ClearOverrideBindings, key)
  end
  local index
  for index = 1, #BAG_BINDINGS do
    local binding = BAG_BINDINGS[index]
    local target = BindingButton(binding)
    if target then
      local first, second = GetBindingKey(binding)
      if type(first) == "string" and first ~= "" then
        pcall(SetOverrideBindingClick, key, true, first, target, "LeftButton")
      end
      if type(second) == "string" and second ~= "" then
        pcall(SetOverrideBindingClick, key, true, second, target, "LeftButton")
      end
    end
  end
end


StoreFrameRef = function(owner, label, ref)
  if SecureHandlerSetFrameRef then
    SecureHandlerSetFrameRef(owner, label, ref)
  elseif owner.SetFrameRef then
    owner:SetFrameRef(label, ref)
  end
end

local function RememberGroupedLayout()
end

local function InventoryBagIds()
  local last = 4
  local reagent = ReagentBagId()
  if reagent and reagent > last then
    last = reagent
  end
  local ids = {}
  local index
  for index = 0, last do
    ids[#ids + 1] = index
  end
  return ids
end

CombatBagsFrame = function()
  if combatBags then
    return combatBags
  end
  if LockedDown() then
    return nil
  end
  local frame = CreateFrame("Frame", "ForeverForgeCombatBags", UIParent)
  if not frame then
    return nil
  end
  frame:SetFrameStrata("DIALOG")
  frame:SetSize(429, 200)
  frame:SetPoint("RIGHT", UIParent, "RIGHT", -40, 40)
  frame:EnableMouse(true)
  local bg = frame:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  if bg.SetColorTexture then
    bg:SetColorTexture(0.07, 0.05, 0.02, 0.94)
  end
  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 12, -12)
  title:SetText("Clean Bags")
  frame:Hide()
  if UISpecialFrames then
    local found = false
    local index
    for index = 1, #UISpecialFrames do
      if UISpecialFrames[index] == "ForeverForgeCombatBags" then
        found = true
      end
    end
    if not found then
      UISpecialFrames[#UISpecialFrames + 1] = "ForeverForgeCombatBags"
    end
  end
  combatBags = frame
  if bagKey then
    StoreFrameRef(bagKey, "combat", frame)
  end
  return frame
end

local function CombatButton(parent, index)
  local button = combatButtons[index]
  if button then
    return button
  end
  if LockedDown() then
    return nil
  end
  button = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate")
  if not button then
    return nil
  end
  button:SetSize(36, 36)
  button:RegisterForClicks("AnyUp")
  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetAllPoints()
  button.icon = icon
  local count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  count:SetPoint("BOTTOMRIGHT", -1, 2)
  button.count = count
  button:HookScript("OnEnter", function(self)
    if not self.ftkBag or not self.ftkSlot or not GameTooltip or not GameTooltip.SetBagItem then
      return
    end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetBagItem(self.ftkBag, self.ftkSlot)
  end)
  button:HookScript("OnLeave", function()
    if GameTooltip and GameTooltip.Hide then
      GameTooltip:Hide()
    end
  end)
  combatButtons[index] = button
  return button
end

local function CombatHeader(parent)
  combatHeaderUsed = combatHeaderUsed + 1
  local header = combatHeaders[combatHeaderUsed]
  if not header then
    header = CreateFrame("Frame", nil, parent)
    header:SetHeight(HEADER_H)
    local label = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", 8, 0)
    label:SetJustifyH("LEFT")
    label:SetTextColor(0.95, 0.82, 0.4)
    header.label = label
    header:EnableMouse(false)
    combatHeaders[combatHeaderUsed] = header
  end
  header:Show()
  return header
end

-- The combined backpack cannot be shown in combat after grouping.
-- This window is ours, so the bag key can open it, and each slot is a
-- secure item button so a click uses that item.
local function RefreshCombatMirror()
  if LockedDown() or not FTK:IsEnabled(MODULE_ID) or not UsingCombinedBags() then
    return
  end
  local frame = CombatBagsFrame()
  if not frame then
    return
  end
  local setByItem, setBySlot = EquipmentSetMaps()
  local groups = {}
  local groupOrder = {}
  local function Group(id, title)
    local group = groups[id]
    if not group then
      group = { id = id, title = title, items = {} }
      groups[id] = group
      groupOrder[#groupOrder + 1] = id
    end
    return group
  end
  local index
  for index = 1, #SECTIONS do
    Group(SECTIONS[index].id, SECTIONS[index].title)
  end
  local bags = InventoryBagIds()
  local bagIndex
  for bagIndex = 1, #bags do
    local bag = bags[bagIndex]
    local slots = 0
    if C_Container and C_Container.GetContainerNumSlots then
      local ok, count = pcall(C_Container.GetContainerNumSlots, bag)
      slots = ok and PlainNumber(count) or 0
    end
    local slot
    if slots and slots > 0 then
      for slot = 1, slots do
        local item = ReadItem(bag, slot)
        if item then
          local icon, stack
          if C_Container.GetContainerItemInfo then
            local infoOk, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
            if infoOk and type(info) == "table" then
              icon = info.iconFileID
              stack = PlainNumber(info.stackCount)
            end
          end
          local category, setTitle = CategoryFor(item, bag, slot, setByItem, setBySlot)
          local title = setTitle or "General"
          if category == "quest" then
            title = "Quest Items"
          elseif category == "consumable" then
            title = "Consumables"
          elseif category == "munitions" then
            title = "Munitions"
          elseif category == "junk" then
            title = "Junk"
          elseif category == "spellreagent" then
            title = "Reagents"
          elseif category == "reagent" then
            title = "Crafting"
          elseif category == "gear" then
            title = "Gear"
          end
          local group = Group(category, title)
          group.items[#group.items + 1] = {
            bag = bag,
            slot = slot,
            itemID = item.itemID,
            quality = item.quality or 0,
            icon = icon,
            count = stack or 0,
          }
        end
      end
    end
  end
  local function SortEntries(list)
    table.sort(list, function(a, b)
      if a.quality ~= b.quality then
        return a.quality > b.quality
      end
      return a.itemID < b.itemID
    end)
  end
  local ordered = {}
  local prefix = { "quest", "consumable", "munitions", "spellreagent", "reagent" }
  for index = 1, #prefix do
    local group = groups[prefix[index]]
    if group and #group.items > 0 then
      SortEntries(group.items)
      ordered[#ordered + 1] = group
    end
  end
  local setIDs = {}
  for index = 1, #groupOrder do
    local id = groupOrder[index]
    if id:find("^set:") and groups[id] and #groups[id].items > 0 then
      setIDs[#setIDs + 1] = id
    end
  end
  table.sort(setIDs, function(a, b)
    return groups[a].title < groups[b].title
  end)
  for index = 1, #setIDs do
    SortEntries(groups[setIDs[index]].items)
    ordered[#ordered + 1] = groups[setIDs[index]]
  end
  local gear = groups.gear
  if gear and #gear.items > 0 then
    SortEntries(gear.items)
    ordered[#ordered + 1] = gear
  end
  local general = groups.other
  if general and #general.items > 0 then
    SortEntries(general.items)
    ordered[#ordered + 1] = general
  end
  local junk = groups.junk
  if junk and #junk.items > 0 then
    SortEntries(junk.items)
    ordered[#ordered + 1] = junk
  end

  local columns = 10
  local buttonSize = 36
  local gridWidth = (columns * buttonSize) + ((columns - 1) * ITEM_GAP_X)
  local cursor = 36
  local buttonIndex = 0
  combatHeaderUsed = 0
  for index = 1, #ordered do
    local group = ordered[index]
    local header = CombatHeader(frame)
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 9, -cursor)
    header.label:SetText(group.title .. " (" .. #group.items .. ")")
    local textWidth = 120
    if header.label.GetStringWidth then
      local widthOk, value = pcall(header.label.GetStringWidth, header.label)
      if widthOk and type(value) == "number" and value == value and value > 0 then
        textWidth = value
      end
    end
    local headerWidth = textWidth + 20
    if headerWidth > gridWidth then
      headerWidth = gridWidth
    end
    header:SetWidth(headerWidth)
    cursor = cursor + HEADER_H + 4
    local itemIndex
    for itemIndex = 1, #group.items do
      buttonIndex = buttonIndex + 1
      local entry = group.items[itemIndex]
      local button = CombatButton(frame, buttonIndex)
      if button then
        button.ftkBag = entry.bag
        button.ftkSlot = entry.slot
        button:SetAttribute("type", "item")
        button:SetAttribute("item", entry.bag .. " " .. entry.slot)
        if button.icon and button.icon.SetTexture then
          button.icon:SetTexture(entry.icon)
        end
        if button.count and button.count.SetText then
          if entry.count > 1 then
            button.count:SetText(entry.count)
          else
            button.count:SetText("")
          end
        end
        local column = (itemIndex - 1) % columns
        local row = math.floor((itemIndex - 1) / columns)
        local x = 9 + (column * (buttonSize + ITEM_GAP_X))
        local y = -(cursor + (row * (buttonSize + ITEM_GAP_Y)))
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
        button:Show()
      end
    end
    local rows = math.ceil(#group.items / columns)
    if rows < 1 then
      rows = 1
    end
    cursor = cursor + (rows * buttonSize) + ((rows - 1) * ITEM_GAP_Y) + SECTION_GAP
  end
  local extra
  for extra = combatHeaderUsed + 1, #combatHeaders do
    combatHeaders[extra]:Hide()
  end
  for extra = buttonIndex + 1, #combatButtons do
    combatButtons[extra]:Hide()
  end
  local height = cursor + 16
  if height < 80 then
    height = 80
  end
  frame:SetSize(gridWidth + 18, height)
end

local function Layout(frame, allowHidden)
  if layingOut or not FTK:IsEnabled(MODULE_ID) or not UsingCombinedBags() then
    return
  end
  if not frame or (not frame:IsShown() and not allowHidden) then
    return
  end
  if DeferLayout(frame) then
    HideCleanBagsChrome()
    return
  end
  layingOut = true
  ShowBagChrome(frame)
  local buttons = CollectButtons(frame)
  AttachReagentButtons(frame, buttons)
  if #buttons == 0 then
    layingOut = false
    return
  end
  layoutPoints = {}

  headerUsed = 0

  local setByItem, setBySlot = EquipmentSetMaps()
  local groups = {}
  local groupOrder = {}
  local function Group(id, title)
    local group = groups[id]
    if not group then
      group = { id = id, title = title, items = {}, empties = {} }
      groups[id] = group
      groupOrder[#groupOrder + 1] = id
    end
    return group
  end

  local index
  for index = 1, #SECTIONS do
    Group(SECTIONS[index].id, SECTIONS[index].title)
  end

  for index = 1, #buttons do
    local button = buttons[index]
    local bag, slot = ButtonBagSlot(button)
    local item = ReadItem(bag, slot)
    if not item then
      Group("empty", "Empty").empties[#Group("empty", "Empty").empties + 1] = button
    else
      local category, setTitle = CategoryFor(item, bag, slot, setByItem, setBySlot)
      local title = setTitle or "General"
      if category == "quest" then
        title = "Quest Items"
      elseif category == "consumable" then
        title = "Consumables"
      elseif category == "munitions" then
        title = "Munitions"
      elseif category == "junk" then
        title = "Junk"
      elseif category == "spellreagent" then
        title = "Reagents"
      elseif category == "reagent" then
        title = "Crafting"
      elseif category == "gear" then
        title = "Gear"
      end
      local group = Group(category, title)
      group.items[#group.items + 1] = { button = button, itemID = item.itemID, quality = item.quality or 0 }
    end
  end

  local function SortEntries(list)
    table.sort(list, function(a, b)
      if a.quality ~= b.quality then
        return a.quality > b.quality
      end
      return a.itemID < b.itemID
    end)
  end

  local ordered = {}
  local prefix = { "quest", "consumable", "munitions", "spellreagent", "reagent" }
  for index = 1, #prefix do
    local group = groups[prefix[index]]
    if group and #group.items > 0 then
      SortEntries(group.items)
      ordered[#ordered + 1] = group
    end
  end
  local setIDs = {}
  for index = 1, #groupOrder do
    local id = groupOrder[index]
    if id:find("^set:") and groups[id] and #groups[id].items > 0 then
      setIDs[#setIDs + 1] = id
    end
  end
  table.sort(setIDs, function(a, b)
    return groups[a].title < groups[b].title
  end)
  for index = 1, #setIDs do
    SortEntries(groups[setIDs[index]].items)
    ordered[#ordered + 1] = groups[setIDs[index]]
  end
  local gear = groups.gear
  if gear and #gear.items > 0 then
    SortEntries(gear.items)
    ordered[#ordered + 1] = gear
  end
  local general = groups.other
  if general and #general.items > 0 then
    SortEntries(general.items)
    ordered[#ordered + 1] = general
  end
  local junk = groups.junk
  if junk and #junk.items > 0 then
    SortEntries(junk.items)
    ordered[#ordered + 1] = junk
  end
  local empty = groups.empty
  if empty and #empty.empties > 0 then
    ordered[#ordered + 1] = empty
  end

  local columns = 10
  if frame.GetColumns then
    local ok, count = pcall(frame.GetColumns, frame)
    count = ok and PlainNumber(count) or nil
    if count and count >= 4 and count <= 20 then
      columns = count
    end
  end
  local buttonWidth, buttonHeight = ButtonSize(buttons[1])
  local gridWidth = (columns * buttonWidth) + ((columns - 1) * ITEM_GAP_X)
  local cursor = TOP_OFFSET

  for index = 1, #ordered do
    local group = ordered[index]
    local header = AcquireHeader(frame)
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 9, -cursor)
    local count = #group.items
    if count == 0 then
      count = #group.empties
    end
    header.label:ClearAllPoints()
    header.label:SetPoint("LEFT", header, "LEFT", 24, 0)
    header.label:SetText(group.title .. " (" .. count .. ")")
    local textWidth = 120
    if header.label.GetStringWidth then
      local widthOk, value = pcall(header.label.GetStringWidth, header.label)
      if widthOk and type(value) == "number" and value == value and value > 0 then
        textWidth = value
      end
    end
    local headerWidth = textWidth + 36
    local half = gridWidth * 0.5
    if headerWidth > half then
      headerWidth = half
    end
    header:SetWidth(headerWidth)
    if FTK.QuickDrop and FTK.QuickDrop.Attach then
      FTK.QuickDrop:Attach(header, group.items, "deposit", group.title, ButtonBagSlot)
    end
    cursor = cursor + HEADER_H + 4

    local placed = {}
    local itemIndex
    for itemIndex = 1, #group.items do
      placed[#placed + 1] = group.items[itemIndex].button
    end
    for itemIndex = 1, #group.empties do
      placed[#placed + 1] = group.empties[itemIndex]
    end
    for itemIndex = 1, #placed do
      local column = (itemIndex - 1) % columns
      local row = math.floor((itemIndex - 1) / columns)
      local x = 9 + (column * (buttonWidth + ITEM_GAP_X))
      local y = -(cursor + (row * (buttonHeight + ITEM_GAP_Y)))
      Place(placed[itemIndex], frame, x, y)
    end
    local rows = math.ceil(#placed / columns)
    if rows < 1 then
      rows = 1
    end
    cursor = cursor + (rows * buttonHeight) + ((rows - 1) * ITEM_GAP_Y) + SECTION_GAP
  end

  HideUnusedHeaders()
  local height = cursor + BOTTOM_PAD
  if height < 160 then
    height = 160
  end
  if not DeferLayout(frame) then
    frame:SetHeight(height)
    -- Remembering the positions must not abort the grouping. A failure
    -- here used to leave the pass marked in progress, so later opens
    -- kept Blizzard's grid under the group labels.
    pcall(RememberGroupedLayout, frame, height)
  end
  -- The bag can raise itself while it resizes. Put the labels back
  -- above that background after the height is set.
  ShowBagChrome(frame)
  layoutPoints = nil
  layingOut = false
  RefreshCombatMirror()
end

local function RequestLayout()
  if not FTK:IsEnabled(MODULE_ID) or not UsingCombinedBags() then
    return
  end
  local frame = CombinedFrame()
  if frame and frame:IsShown() then
    Layout(frame)
    return
  end
  RefreshCombatMirror()
end

-- The bag key places the saved groups inside its own secure press.
-- A fresh grouping from here waits until that press has returned.
local function ScheduleLayout()
  if not FTK:IsEnabled(MODULE_ID) then
    return
  end
  if not (C_Timer and C_Timer.After) then
    if LockedDown() then
      layoutAfterCombat = true
    else
      RequestLayout()
    end
    return
  end
  if not layoutQueued then
    layoutQueued = true
    C_Timer.After(0, function()
      layoutQueued = false
      RequestLayout()
    end)
  end
  if not layoutFollowUp then
    layoutFollowUp = true
    C_Timer.After(0.1, function()
      layoutFollowUp = false
      RequestLayout()
    end)
  end
end

local function HookBagOpen()
  local frame = _G.ContainerFrameCombinedBags
  if not frame or frame.ftkBagManagerShow or not frame.HookScript then
    return
  end
  frame.ftkBagManagerShow = true
  frame:HookScript("OnShow", function()
    reagentOpenTried = false
    RememberCombinedFrame()
    ScheduleLayout()
  end)
  frame:HookScript("OnHide", function()
    reagentOpenTried = false
    DismissReagentFrame()
    if not (C_Timer and C_Timer.After) then
      return
    end
    C_Timer.After(0, function()
      local combined = CombinedFrame()
      if combined and combined:IsShown() then
        return
      end
      HideCleanBagsChrome()
      if LockedDown() then
        reagentReturnAfterCombat = true
        return
      end
      ReturnReagentButtons()
    end)
  end)
end

local function PrimeCombined()
  if LockedDown() or not FTK:IsEnabled(MODULE_ID) or not UsingCombinedBags() then
    return
  end
  local frame = CombinedFrame()
  if not frame or frame:IsShown() or frame.ftkBagPrimed then
    return
  end
  if type(frame.Items) ~= "table" or #frame.Items == 0 then
    return
  end
  Layout(frame, true)
  frame.ftkBagPrimed = true
end

local function RestoreBlizzardLayout()
  restoring = true
  local frame = CombinedFrame()
  if not frame then
    RestoreReagentFrame()
    if UpdateContainerFrameAnchors then
      pcall(UpdateContainerFrameAnchors)
    end
    HideUnusedHeaders()
    headerUsed = 0
    HideUnusedHeaders()
    restoring = false
    return
  end
  headerUsed = 0
  HideUnusedHeaders()
  RestoreReagentFrame()
  if frame.UpdateFrameSize then
    pcall(frame.UpdateFrameSize, frame)
  end
  if frame.UpdateItemLayout then
    pcall(frame.UpdateItemLayout, frame)
  end
  if UpdateContainerFrameAnchors then
    pcall(UpdateContainerFrameAnchors)
  end
  restoring = false
end

local function InstallHook()
  if hooked or not hooksecurefunc or not ContainerFrameMixin or not ContainerFrameMixin.UpdateItemLayout then
    return hooked
  end
  hooksecurefunc(ContainerFrameMixin, "UpdateItemLayout", function(self)
    if layingOut or restoring or not FTK:IsEnabled(MODULE_ID) then
      return
    end
    if self and self.IsCombinedBagContainer and self:IsCombinedBagContainer() and UsingCombinedBags() then
      ScheduleLayout()
      return
    end
    if UsingCombinedBags() and self and self.GetBagID then
      local ok, id = pcall(self.GetBagID, self)
      id = ok and PlainNumber(id) or nil
      if id and id == ReagentBagId() then
        ScheduleLayout()
      end
    end
  end)
  if UpdateContainerFrameAnchors then
    hooksecurefunc("UpdateContainerFrameAnchors", function()
      if layingOut or restoring or not FTK:IsEnabled(MODULE_ID) or not UsingCombinedBags() then
        return
      end
      local combined = CombinedFrame()
      if not combined or not combined:IsShown() then
        return
      end
      local reagent = ShownFrameForBag(ReagentBagId())
      if reagent and reagent ~= combined then
        if C_Timer and C_Timer.After then
          C_Timer.After(0, function()
            if combined:IsShown() and ShownFrameForBag(ReagentBagId()) == reagent then
              ParkReagentFrame(reagent)
            end
          end)
        else
          ParkReagentFrame(reagent)
        end
      end
    end)
  end
  HookBagOpen()
  if OpenAllBags then
    hooksecurefunc("OpenAllBags", ScheduleLayout)
  end
  if ToggleBackpack then
    hooksecurefunc("ToggleBackpack", ScheduleLayout)
  end
  hooked = true
  return true
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_REGEN_ENABLED" and releaseBagKey then
    ClearBagKey()
    if not FTK:IsEnabled(MODULE_ID) then
      events:UnregisterEvent("PLAYER_REGEN_ENABLED")
      return
    end
  end
  if not FTK:IsEnabled(MODULE_ID) then
    return
  end
  InstallHook()
  HookBagOpen()
  if event == "PLAYER_REGEN_DISABLED" then
    layoutAfterCombat = true
    HideCleanBagsChrome()
    return
  end
  if event == "PLAYER_REGEN_ENABLED" then
    if combatBags then
      combatBags:Hide()
    end
    if reagentReturnAfterCombat then
      reagentReturnAfterCombat = false
      local combined = CombinedFrame()
      if not combined or not combined:IsShown() then
        ReturnReagentButtons()
      end
    end
    ApplyBagKey()
    if layoutAfterCombat then
      layoutAfterCombat = false
      ScheduleLayout()
    end
    if C_Timer and C_Timer.After then
      C_Timer.After(0, function()
        PrimeCombined()
        ApplyBagKey()
      end)
    else
      PrimeCombined()
      ApplyBagKey()
    end
    return
  end
  if event == "UPDATE_BINDINGS" then
    ApplyBagKey()
    return
  end
  if event == "USE_COMBINED_BAGS_CHANGED" and not UsingCombinedBags() then
    ClearBagKey()
    RestoreBlizzardLayout()
    return
  end
  if C_Timer and C_Timer.After then
    C_Timer.After(0, function()
      PrimeCombined()
      RequestLayout()
      ApplyBagKey()
    end)
  else
    PrimeCombined()
    RequestLayout()
    ApplyBagKey()
  end
end)

FTK.CleanBagRules = {
  CategoryFor = CategoryFor,
  EquipmentSetMaps = EquipmentSetMaps,
  ReadItem = ReadItem,
  PlainNumber = PlainNumber,
}

FTK.CleanBagsRefresh = ScheduleLayout

FTK:RegisterModule({
  id = MODULE_ID,
  name = "Clean Bags",
  description = "Groups the combined backpack, including the reagent bag, into Quest Items, Munitions, Reagents, Crafting, equipment sets, Gear, General, Junk, and Empty.",
  defaultEnabled = true,
  onEnable = function()
    InstallHook()
    events:RegisterEvent("BAG_UPDATE")
    events:RegisterEvent("BAG_UPDATE_DELAYED")
    events:RegisterEvent("EQUIPMENT_SETS_CHANGED")
    events:RegisterEvent("USE_COMBINED_BAGS_CHANGED")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:RegisterEvent("PLAYER_REGEN_DISABLED")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:RegisterEvent("UPDATE_BINDINGS")
    events:RegisterEvent("BAG_CONTAINER_UPDATE")
    if C_Timer and C_Timer.After then
      C_Timer.After(0, function()
        PrimeCombined()
        RequestLayout()
        ApplyBagKey()
      end)
    else
      PrimeCombined()
      RequestLayout()
      ApplyBagKey()
    end
  end,
  onDisable = function()
    events:UnregisterAllEvents()
    if LockedDown() then
      releaseBagKey = true
      events:RegisterEvent("PLAYER_REGEN_ENABLED")
    else
      ClearBagKey()
    end
    if combatBags then
      combatBags:Hide()
    end
    RestoreBlizzardLayout()
  end,
})
