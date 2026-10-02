--[[
  Adds spell, item, NPC, and quest ids to the tooltip under the cursor.
  A bag slot that already has a quest id also shows that quest's name.
  Optional vendor sell price (unit and stack) on item tooltips.

  Buff and debuff mouseovers use the aura tooltip pane. Spell ids are added
  by this addon's tooltip hooks. The interface blocks addons from setting
  tooltipShowAuraSpellIDs, so that setting is left alone.

  Forever can hand back a secret id, especially for auras in combat.
  A secret or missing id is skipped. It is never compared, concatenated,
  or used as a table key. See ../FlowRider/docs/Forever-API-visibility.md.
]]

local FTK = ForeverForge
if not FTK then
  error("ForeverForge: Core.lua must load before Modules/SpellIdTooltip.lua")
end

local MODULE_ID = "SpellIdTooltip"
local LINE_R, LINE_G, LINE_B = 0.65, 0.78, 0.95

local installed = false
local adding = false
local shownText = {}
local containerSlot = {}
local pendingQuest = {}
local titleRequested = {}

local function ClearTooltipState(tooltip)
  shownText[tooltip] = nil
  containerSlot[tooltip] = nil
  pendingQuest[tooltip] = nil
end

local function IsSecret(value)
  if not issecretvalue then
    return false
  end
  local ok, secret = pcall(issecretvalue, value)
  return ok and secret == true
end

local function PlainId(value)
  if type(value) ~= "number" or IsSecret(value) then
    return nil
  end
  local ok, valid = pcall(function()
    return value == value and value >= 1
  end)
  if not ok or valid ~= true then
    return nil
  end
  return value
end

local function LineText(label, id)
  return string.format("%s: %d", label, id)
end

local function AlreadyShown(tooltip, text)
  if not tooltip.GetName or not tooltip.NumLines then
    return false
  end
  local name = tooltip:GetName()
  if type(name) ~= "string" or name == "" or IsSecret(name) then
    return false
  end
  local count = tooltip:NumLines()
  if type(count) ~= "number" or IsSecret(count) then
    return false
  end
  if count < 1 then
    return false
  end
  if count > 60 then
    count = 60
  end
  local i
  for i = 1, count do
    local line = _G[name .. "TextLeft" .. i]
    if line and line.GetText then
      local existing = line:GetText()
      if type(existing) == "string" and not IsSecret(existing) then
        local sameOk, same = pcall(function()
          return existing == text
        end)
        if sameOk and same == true then
          return true
        end
      end
    end
  end
  return false
end

local function Watch(tooltip)
  if not tooltip or tooltip.ftkSpellIdWatch or not tooltip.HookScript then
    return
  end
  tooltip.ftkSpellIdWatch = true
  local function Clear(self)
    ClearTooltipState(self)
  end
  pcall(tooltip.HookScript, tooltip, "OnTooltipCleared", Clear)
  pcall(tooltip.HookScript, tooltip, "OnHide", Clear)
end

local function AppendText(tooltip, text, resize)
  if adding or not tooltip or not tooltip.AddLine then
    return
  end
  if type(text) ~= "string" or text == "" or IsSecret(text) then
    return
  end
  if shownText[tooltip] == text or AlreadyShown(tooltip, text) then
    shownText[tooltip] = text
    return
  end
  Watch(tooltip)
  adding = true
  local ok = pcall(tooltip.AddLine, tooltip, text, LINE_R, LINE_G, LINE_B, false)
  if not ok then
    ok = pcall(tooltip.AddLine, tooltip, text, LINE_R, LINE_G, LINE_B)
  end
  adding = false
  if not ok then
    return
  end
  shownText[tooltip] = text
  if resize and tooltip.IsShown and tooltip.Show then
    local shownOk, shown = pcall(tooltip.IsShown, tooltip)
    if shownOk and shown == true then
      pcall(tooltip.Show, tooltip)
    end
  end
end

local function Append(tooltip, id, label)
  id = PlainId(id)
  if not id or type(label) ~= "string" then
    return
  end
  local textOk, text = pcall(LineText, label, id)
  if not textOk or type(text) ~= "string" then
    return
  end
  AppendText(tooltip, text, false)
end

local function IdFromData(data)
  if type(data) ~= "table" then
    return nil
  end
  if TooltipUtil and TooltipUtil.SurfaceArgs then
    pcall(TooltipUtil.SurfaceArgs, data)
  end
  return PlainId(data.id)
end

local function IdFromTooltip(tooltip)
  if not tooltip or not tooltip.GetSpell then
    return nil
  end
  local ok, _, spellId = pcall(tooltip.GetSpell, tooltip)
  if not ok then
    return nil
  end
  return PlainId(spellId)
end

local function OnSpellTooltip(tooltip, data)
  if not FTK:IsEnabled(MODULE_ID) then
    return
  end
  local spellId = IdFromData(data)
  if not spellId then
    spellId = IdFromTooltip(tooltip)
  end
  Append(tooltip, spellId, "Spell ID")
end

local function IdFromItemLink(link)
  if type(link) ~= "string" or IsSecret(link) then
    return nil
  end
  local ok, digits = pcall(string.match, link, "item:(%d+)")
  if not ok or type(digits) ~= "string" then
    return nil
  end
  return PlainId(tonumber(digits))
end

local function IdFromItemTooltip(tooltip)
  if not tooltip or not tooltip.GetItem then
    return nil
  end
  local ok, _, link = pcall(tooltip.GetItem, tooltip)
  if not ok then
    return nil
  end
  return IdFromItemLink(link)
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

local function FrameName(frame)
  if type(frame) ~= "table" or not frame.GetName then
    return nil
  end
  local ok, name = pcall(frame.GetName, frame)
  if not ok or type(name) ~= "string" or name == "" or IsSecret(name) then
    return nil
  end
  return name
end

local function LooksLikeItemButton(frame)
  if type(frame) ~= "table" then
    return false
  end
  if frame.GetBagID or frame.GetBankTabID or frame.icon or frame.Icon then
    return true
  end
  local name = FrameName(frame)
  if name and (name:find("Item", 1, true) or name:find("Container", 1, true)) then
    return true
  end
  return false
end

local function FrameContainerSlot(frame)
  if not LooksLikeItemButton(frame) then
    return nil, nil
  end
  local bag = nil
  if frame.GetBagID then
    local bagOk, value = pcall(frame.GetBagID, frame)
    if bagOk then
      bag = PlainNumber(value)
    end
  end
  if bag == nil and frame.GetBankTabID then
    local bagOk, value = pcall(frame.GetBankTabID, frame)
    if bagOk then
      bag = PlainNumber(value)
    end
  end
  if bag == nil and frame.GetParent then
    local parentOk, parent = pcall(frame.GetParent, frame)
    if parentOk and type(parent) == "table" and parent.GetID then
      local bagOk, value = pcall(parent.GetID, parent)
      if bagOk then
        bag = PlainNumber(value)
      end
    end
  end
  if bag == nil then
    local bankBag = Enum and Enum.BagIndex and Enum.BagIndex.Bank
    local name = FrameName(frame)
    if name and name:find("Bank", 1, true) then
      bag = PlainNumber(bankBag) or -1
    end
  end
  if bag == nil then
    return nil, nil
  end
  local slot = nil
  if frame.GetContainerSlotID then
    local slotOk, value = pcall(frame.GetContainerSlotID, frame)
    if slotOk then
      slot = PlainNumber(value)
    end
  end
  if (slot == nil or slot < 1) and frame.GetID then
    local slotOk, value = pcall(frame.GetID, frame)
    if slotOk then
      slot = PlainNumber(value)
    end
  end
  if slot == nil or slot < 1 then
    return nil, nil
  end
  return bag, slot
end

local function TooltipOwner(tooltip)
  if not tooltip or not tooltip.GetOwner then
    return nil
  end
  local ok, owner = pcall(tooltip.GetOwner, tooltip)
  if ok and type(owner) == "table" then
    return owner
  end
  return nil
end

local function MouseFrame()
  if GetMouseFoci then
    local ok, foci = pcall(GetMouseFoci)
    if ok and type(foci) == "table" and type(foci[1]) == "table" then
      return foci[1]
    end
  end
  if GetMouseFocus then
    local ok, frame = pcall(GetMouseFocus)
    if ok and type(frame) == "table" then
      return frame
    end
  end
  return nil
end

local function ContainerSlot(tooltip)
  local bag, slot = FrameContainerSlot(TooltipOwner(tooltip))
  if bag ~= nil and slot ~= nil then
    return bag, slot
  end
  bag, slot = FrameContainerSlot(MouseFrame())
  if bag ~= nil and slot ~= nil then
    return bag, slot
  end
  local noted = containerSlot[tooltip]
  if type(noted) ~= "table" or noted.bag == nil or noted.slot == nil or noted.slot < 1 then
    return nil, nil
  end
  return noted.bag, noted.slot
end

local function QuestIdForSlot(bag, slot)
  if bag == nil or slot == nil then
    return nil
  end
  local reader = C_Container and C_Container.GetContainerItemQuestInfo
  if type(reader) ~= "function" and GetContainerItemQuestInfo then
    reader = GetContainerItemQuestInfo
  end
  if type(reader) ~= "function" then
    return nil
  end
  local ok, first, second = pcall(reader, bag, slot)
  if not ok then
    return nil
  end
  if type(first) == "table" then
    return PlainId(first.questID)
  end
  return PlainId(second)
end

local function PlainTitle(value)
  if type(value) ~= "string" or value == "" or IsSecret(value) then
    return nil
  end
  return value
end

local function IsHeader(value)
  if IsSecret(value) then
    return true
  end
  return value == true or value == 1
end

local function QuestTitle(questId)
  if not questId or not (C_QuestLog and C_QuestLog.GetTitleForQuestID) then
    return nil
  end
  local ok, title = pcall(C_QuestLog.GetTitleForQuestID, questId)
  if not ok then
    return nil
  end
  return PlainTitle(title)
end

local questsByItem = nil
local titleByQuest = nil
local rebuildingQuests = false

local function LogCount()
  if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
    local ok, value = pcall(C_QuestLog.GetNumQuestLogEntries)
    if ok then
      local count = PlainNumber(value)
      if count then
        return count
      end
    end
  end
  if GetNumQuestLogEntries then
    local ok, value = pcall(GetNumQuestLogEntries)
    if ok then
      return PlainNumber(value) or 0
    end
  end
  return 0
end

local function ReadLogEntry(index)
  if C_QuestLog and C_QuestLog.GetInfo then
    local ok, info = pcall(C_QuestLog.GetInfo, index)
    if ok and type(info) == "table" and not IsHeader(info.isHeader) then
      local questId = PlainId(info.questID)
      local title = PlainTitle(info.title)
      if questId and title then
        return questId, title
      end
    end
  end
  if GetQuestLogTitle then
    local ok, title, _, _, isHeader, _, _, _, questId = pcall(GetQuestLogTitle, index)
    if ok and not IsHeader(isHeader) then
      questId = PlainId(questId)
      title = PlainTitle(title)
      if questId and title then
        return questId, title
      end
    end
  end
  return nil, nil
end

local function ItemIdFromSpecial(value)
  if type(value) == "string" then
    return IdFromItemLink(value)
  end
  if type(value) == "table" then
    return PlainId(value.itemID) or IdFromItemLink(value.itemLink or value.link)
  end
  return nil
end

local function SpecialItemId(index)
  if C_QuestLog and C_QuestLog.GetQuestLogSpecialItemInfo then
    local ok, value = pcall(C_QuestLog.GetQuestLogSpecialItemInfo, index)
    if ok then
      local itemId = ItemIdFromSpecial(value)
      if itemId then
        return itemId
      end
    end
  end
  if GetQuestLogSpecialItemInfo then
    local ok, link = pcall(GetQuestLogSpecialItemInfo, index)
    if ok then
      return ItemIdFromSpecial(link)
    end
  end
  return nil
end

local function RememberItemQuest(itemId, questId, title)
  itemId = PlainId(itemId)
  questId = PlainId(questId)
  title = PlainTitle(title)
  if not itemId or not questId or not title then
    return
  end
  local list = questsByItem[itemId]
  if not list then
    list = {}
    questsByItem[itemId] = list
  end
  local index
  for index = 1, #list do
    if list[index].questId == questId then
      return
    end
  end
  list[#list + 1] = { questId = questId, title = title }
end

local function IsItemObjective(kind)
  if kind == nil or IsSecret(kind) then
    return false
  end
  if kind == "item" then
    return true
  end
  local itemType = Enum and Enum.QuestObjectiveType and Enum.QuestObjectiveType.Item
  if itemType ~= nil and not IsSecret(itemType) and kind == itemType then
    return true
  end
  return false
end

local function PlainName(value)
  if IsSecret(value) or type(value) ~= "string" or value == "" then
    return nil
  end
  return value
end

local function ItemIdByName(name)
  name = PlainName(name)
  if not name or not GetItemInfo then
    return nil
  end
  local ok, _, link = pcall(GetItemInfo, name)
  if not ok then
    return nil
  end
  return IdFromItemLink(link)
end

local function ItemNameById(itemId)
  if C_Item and C_Item.GetItemNameByID then
    local ok, name = pcall(C_Item.GetItemNameByID, itemId)
    name = ok and PlainName(name) or nil
    if name then
      return name
    end
  end
  if not GetItemInfo then
    return nil
  end
  local ok, name = pcall(GetItemInfo, itemId)
  if not ok then
    return nil
  end
  return PlainName(name)
end

-- Collect objectives name the item in the text, often with no item id.
-- "Bristleback Quilboar Tusk: 19/60" and "19/60 Bristleback Quilboar Tusk".
local function ItemIdFromObjectiveText(text)
  if IsSecret(text) or type(text) ~= "string" or text == "" then
    return nil
  end
  text = text:gsub("^%s*%-%s*", "")
  local names = { text }
  local stripped = text:match("^(.-):%s*%d+/%d+")
  if stripped and stripped ~= "" then
    names[#names + 1] = stripped
  end
  stripped = text:match("^%d+/%d+%s+(.+)$")
  if stripped and stripped ~= "" then
    names[#names + 1] = stripped
  end
  local index
  for index = 1, #names do
    local itemId = ItemIdByName(names[index])
    if itemId then
      return itemId
    end
  end
  return nil
end

local function ObjectiveNamesItem(text, itemName)
  if IsSecret(text) or type(text) ~= "string" or text == "" or not itemName then
    return false
  end
  text = text:gsub("^%s*%-%s*", "")
  if text == itemName then
    return true
  end
  if text:sub(1, #itemName) == itemName then
    local rest = text:sub(#itemName + 1)
    if rest:match("^:%s*%d+/%d+") or rest:match("^%s+%d+/%d+") then
      return true
    end
  end
  if text:sub(-#itemName) == itemName then
    local lead = text:sub(1, #text - #itemName)
    if lead:match("^%d+/%d+%s+$") then
      return true
    end
  end
  return false
end

local function RememberObjectiveItems(questId, title)
  if not (C_QuestLog and C_QuestLog.GetQuestObjectives) then
    return
  end
  local ok, objectives = pcall(C_QuestLog.GetQuestObjectives, questId)
  if not ok or type(objectives) ~= "table" then
    return
  end
  local index
  for index = 1, #objectives do
    local objective = objectives[index]
    if type(objective) == "table" then
      RememberItemQuest(objective.itemID, questId, title)
      RememberItemQuest(objective.itemId, questId, title)
      if IsItemObjective(objective.type) then
        RememberItemQuest(objective.assetID, questId, title)
      end
      RememberItemQuest(ItemIdFromObjectiveText(objective.text), questId, title)
    end
  end
end

local function RememberTurnInItems(questId, logIndex, title)
  if GetQuestLogTitle then
    pcall(GetQuestLogTitle, logIndex)
  end
  if GetQuestLogQuestText then
    pcall(GetQuestLogQuestText)
  end
  if not GetQuestLogItemLink then
    return
  end
  local index
  for index = 1, 10 do
    local ok, link = pcall(GetQuestLogItemLink, "required", index)
    if ok then
      RememberItemQuest(IdFromItemLink(link), questId, title)
    end
  end
end

local function SelectedQuestId()
  if C_QuestLog and C_QuestLog.GetSelectedQuest then
    local ok, value = pcall(C_QuestLog.GetSelectedQuest)
    if ok then
      return PlainId(value)
    end
  end
  return nil
end

local function SelectedLogIndex()
  if GetQuestLogSelection then
    local ok, value = pcall(GetQuestLogSelection)
    if ok then
      return PlainNumber(value)
    end
  end
  return nil
end

local function SelectLogQuest(questId, logIndex)
  local selected = false
  if questId and C_QuestLog and C_QuestLog.SetSelectedQuest then
    if pcall(C_QuestLog.SetSelectedQuest, questId) then
      selected = true
    end
  end
  -- GetQuestLogItemLink reads the classic log selection, not SetSelectedQuest.
  if logIndex and SelectQuestLogEntry then
    if pcall(SelectQuestLogEntry, logIndex) then
      selected = true
    end
  end
  return selected
end

local function RestoreLogSelection(questId, logIndex)
  if questId and C_QuestLog and C_QuestLog.SetSelectedQuest then
    pcall(C_QuestLog.SetSelectedQuest, questId)
    return
  end
  if SelectQuestLogEntry then
    pcall(SelectQuestLogEntry, logIndex or 0)
  end
end

local function TitleForQuest(questId)
  if titleByQuest and titleByQuest[questId] then
    return titleByQuest[questId]
  end
  local count = LogCount()
  local index
  for index = 1, count do
    local id, title = ReadLogEntry(index)
    if id == questId and title then
      if titleByQuest then
        titleByQuest[questId] = title
      end
      return title
    end
  end
  return QuestTitle(questId)
end

local builtSignature = nil

local function LogSignature()
  local parts = {}
  local count = LogCount()
  local index
  for index = 1, count do
    local questId = ReadLogEntry(index)
    if questId then
      parts[#parts + 1] = questId
    end
  end
  return table.concat(parts, ",")
end

local function RebuildQuestCache()
  if rebuildingQuests then
    return
  end
  rebuildingQuests = true
  questsByItem = {}
  titleByQuest = {}
  local savedQuest = SelectedQuestId()
  local savedIndex = SelectedLogIndex()
  local count = LogCount()
  local index
  for index = 1, count do
    local questId, title = ReadLogEntry(index)
    if questId and title then
      titleByQuest[questId] = title
      RememberItemQuest(SpecialItemId(index), questId, title)
      RememberObjectiveItems(questId, title)
      if SelectLogQuest(questId, index) then
        RememberTurnInItems(questId, index, title)
      end
    end
  end
  RestoreLogSelection(savedQuest, savedIndex)
  builtSignature = LogSignature()
  rebuildingQuests = false
end

local function NoteQuestLogChanged()
  if rebuildingQuests then
    return
  end
  if builtSignature ~= nil and LogSignature() == builtSignature then
    return
  end
  questsByItem = nil
  titleByQuest = nil
end

local function RequestTitle(questId)
  if titleRequested[questId] then
    return
  end
  if not (C_QuestLog and C_QuestLog.RequestLoadQuestByID) then
    return
  end
  titleRequested[questId] = true
  local ok = pcall(C_QuestLog.RequestLoadQuestByID, questId)
  if not ok then
    titleRequested[questId] = nil
  end
end

local function QuestLine(title)
  return "Quest: " .. title
end

local function ShowQuestLine(tooltip, title, resize)
  title = PlainTitle(title)
  if not title then
    return false
  end
  local textOk, text = pcall(QuestLine, title)
  if not textOk then
    return false
  end
  AppendText(tooltip, text, resize == true)
  return true
end

-- Usable quest items and turn-in items often have no quest id on the bag slot.
-- Match the item id to the quest log instead of guessing from the item name.
local function AppendQuestName(tooltip, itemId)
  if not FTK:IsEnabled(MODULE_ID) or not tooltip then
    return
  end
  if not questsByItem then
    RebuildQuestCache()
  end
  itemId = PlainId(itemId)
  local shown = {}
  local function show(title, questId)
    title = PlainTitle(title)
    if not title or shown[title] then
      return
    end
    if ShowQuestLine(tooltip, title, false) then
      shown[title] = true
      if questId then
        pendingQuest[tooltip] = questId
      end
    end
  end

  local bag, slot = ContainerSlot(tooltip)
  local slotQuest = QuestIdForSlot(bag, slot)
  if slotQuest then
    local title = TitleForQuest(slotQuest)
    if title then
      show(title, slotQuest)
    else
      RequestTitle(slotQuest)
      pendingQuest[tooltip] = slotQuest
    end
  end
  if itemId and questsByItem and not questsByItem[itemId] then
    local itemName = ItemNameById(itemId)
    local count = LogCount()
    local scan
    for scan = 1, count do
      local questId, title = ReadLogEntry(scan)
      if questId and title and C_QuestLog and C_QuestLog.GetQuestObjectives then
        local ok, objectives = pcall(C_QuestLog.GetQuestObjectives, questId)
        if ok and type(objectives) == "table" then
          local objIndex
          for objIndex = 1, #objectives do
            local objective = objectives[objIndex]
            if type(objective) == "table" and ObjectiveNamesItem(objective.text, itemName) then
              RememberItemQuest(itemId, questId, title)
            end
          end
        end
      end
    end
  end
  if itemId and questsByItem and questsByItem[itemId] then
    local list = questsByItem[itemId]
    local index
    for index = 1, #list do
      show(list[index].title, list[index].questId)
    end
  end
end

local function ShowLoadedQuestTitle(questId, title)
  local tooltips = { GameTooltip, ItemRefTooltip }
  local index
  for index = 1, #tooltips do
    local tooltip = tooltips[index]
    if tooltip and pendingQuest[tooltip] == questId and tooltip.IsShown then
      local shownOk, shown = pcall(tooltip.IsShown, tooltip)
      if shownOk and shown == true then
        local bag, slot = ContainerSlot(tooltip)
        if QuestIdForSlot(bag, slot) == questId then
          ShowQuestLine(tooltip, title, true)
        end
      end
    end
  end
end

local questData = CreateFrame("Frame")
questData:SetScript("OnEvent", function(_, event, questId, success)
  if not FTK:IsEnabled(MODULE_ID) then
    return
  end
  if event == "QUEST_LOG_UPDATE" or event == "QUEST_ACCEPTED" then
    NoteQuestLogChanged()
    return
  end
  questId = PlainId(questId)
  if not questId then
    return
  end
  if not IsSecret(success) and success == false then
    titleRequested[questId] = nil
    return
  end
  local title = QuestTitle(questId)
  if not title then
    return
  end
  ShowLoadedQuestTitle(questId, title)
end)

local function VendorPriceConfig()
  local cfg = FTK:GetConfig(MODULE_ID)
  if cfg.showVendorPrice == nil then
    cfg.showVendorPrice = true
  end
  return cfg
end

local function VendorPriceEnabled()
  if not FTK:IsEnabled(MODULE_ID) then
    return false
  end
  return VendorPriceConfig().showVendorPrice ~= false
end

local function CoinText(copper)
  copper = PlainNumber(copper)
  if not copper or copper < 1 then
    return nil
  end
  if type(GetCoinTextureString) == "function" then
    local ok, text = pcall(GetCoinTextureString, copper)
    if ok and type(text) == "string" and text ~= "" and not IsSecret(text) then
      return text
    end
  end
  local g = math.floor(copper / 10000)
  local s = math.floor((copper % 10000) / 100)
  local c = copper % 100
  local parts = {}
  if g > 0 then
    parts[#parts + 1] = g .. "g"
  end
  if s > 0 or g > 0 then
    parts[#parts + 1] = s .. "s"
  end
  parts[#parts + 1] = c .. "c"
  return table.concat(parts, " ")
end

-- Forever / retail: sellPrice is return 11 from GetItemInfo.
-- Prefer that; fall back to GetSellValue when an older client exposes it.
local function ItemSellPrice(itemId)
  itemId = PlainId(itemId)
  if not itemId then
    return nil
  end
  if type(GetItemInfo) == "function" then
    local ok, sellPrice = pcall(function()
      local _, _, _, _, _, _, _, _, _, _, price = GetItemInfo(itemId)
      return price
    end)
    sellPrice = ok and PlainNumber(sellPrice) or nil
    if sellPrice and sellPrice > 0 then
      return sellPrice
    end
  end
  if C_Item and C_Item.GetItemInfo then
    local ok, sellPrice = pcall(function()
      local info = C_Item.GetItemInfo(itemId)
      if type(info) == "table" then
        return info.sellPrice or info.itemSellPrice
      end
      -- Some builds return multiple values; recover sell price positionally.
      local a, b, c, d, e, f, g, h, i, j, price = C_Item.GetItemInfo(itemId)
      return price
    end)
    sellPrice = ok and PlainNumber(sellPrice) or nil
    if sellPrice and sellPrice > 0 then
      return sellPrice
    end
  end
  if type(GetSellValue) == "function" then
    local ok, value = pcall(GetSellValue, itemId)
    value = ok and PlainNumber(value) or nil
    if value and value > 0 then
      return value
    end
  end
  return nil
end

local function TooltipItemCount(tooltip)
  local bag, slot = ContainerSlot(tooltip)
  if bag ~= nil and slot ~= nil then
    if C_Container and C_Container.GetContainerItemInfo then
      local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
      if ok and type(info) == "table" then
        local count = PlainNumber(info.stackCount) or PlainNumber(info.quantity) or PlainNumber(info.count)
        if count and count >= 1 then
          return count
        end
      end
    end
    if type(GetContainerItemInfo) == "function" then
      local ok, texture, itemCount = pcall(GetContainerItemInfo, bag, slot)
      itemCount = ok and PlainNumber(itemCount) or nil
      if itemCount and itemCount >= 1 then
        return itemCount
      end
    end
  end
  return 1
end

local function AppendVendorPrice(tooltip, itemId)
  if not VendorPriceEnabled() or not tooltip then
    return
  end
  local unit = ItemSellPrice(itemId)
  if not unit then
    return
  end
  local unitText = CoinText(unit)
  if not unitText then
    return
  end
  local count = TooltipItemCount(tooltip)
  if not count or count < 1 then
    count = 1
  end
  local unitOk, unitLine = pcall(function()
    return "Vendor: " .. unitText
  end)
  if unitOk and type(unitLine) == "string" then
    AppendText(tooltip, unitLine, false)
  end
  if count > 1 then
    local stack = unit * count
    -- Guard against overflow / secret multiplication failures.
    stack = PlainNumber(stack)
    local stackText = stack and CoinText(stack) or nil
    if stackText then
      local stackOk, stackLine = pcall(function()
        return "Vendor stack (" .. count .. "): " .. stackText
      end)
      if stackOk and type(stackLine) == "string" then
        -- Keep resize off. tooltip:Show() from a coin-texture line can re-enter
        -- OnTooltipSetItem, and GetText() often does not match the |T string.
        AppendText(tooltip, stackLine, false)
      end
    end
  end
end

local function OnItemTooltip(tooltip, data)
  if not FTK:IsEnabled(MODULE_ID) then
    return
  end
  -- The item link is the unambiguous id. data.id covers tooltips that
  -- have not filled GetItem yet. Toy tooltips use the item id too.
  local itemId = IdFromItemTooltip(tooltip)
  if not itemId then
    itemId = IdFromData(data)
  end
  Append(tooltip, itemId, "Item ID")
  AppendQuestName(tooltip, itemId)
  AppendVendorPrice(tooltip, itemId)
end

-- Pet-action tooltips identify a bar slot in data.id, not a spell.
-- Only a spell id read back from the tooltip itself is safe to show.
local function OnPetAction(tooltip)
  if not FTK:IsEnabled(MODULE_ID) then
    return
  end
  Append(tooltip, IdFromTooltip(tooltip), "Spell ID")
end

local function OnLegacySpell(tooltip)
  if not FTK:IsEnabled(MODULE_ID) then
    return
  end
  Append(tooltip, IdFromTooltip(tooltip), "Spell ID")
end

local function OnLegacyItem(tooltip)
  if not FTK:IsEnabled(MODULE_ID) then
    return
  end
  local itemId = IdFromItemTooltip(tooltip)
  Append(tooltip, itemId, "Item ID")
  AppendQuestName(tooltip, itemId)
  AppendVendorPrice(tooltip, itemId)
end

local function NpcIdFromGuid(guid)
  guid = type(guid) == "string" and not IsSecret(guid) and guid or nil
  if not guid then
    return nil
  end
  local parts = {}
  local part
  for part in guid:gmatch("[^%-]+") do
    parts[#parts + 1] = part
  end
  local kind = parts[1]
  if kind ~= "Creature" and kind ~= "Vehicle" then
    return nil
  end
  return PlainId(tonumber(parts[6]))
end

local function OnUnitTooltip(tooltip, data)
  if not FTK:IsEnabled(MODULE_ID) then
    return
  end
  local guid
  if type(data) == "table" then
    if TooltipUtil and TooltipUtil.SurfaceArgs then
      pcall(TooltipUtil.SurfaceArgs, data)
    end
    guid = data.guid
  end
  local npcId = NpcIdFromGuid(guid)
  if not npcId and tooltip and tooltip.GetUnit then
    local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
    unit = ok and type(unit) == "string" and not IsSecret(unit) and unit or nil
    if unit and UnitGUID then
      local guidOk, unitGuid = pcall(UnitGUID, unit)
      if guidOk then
        npcId = NpcIdFromGuid(unitGuid)
      end
    end
  end
  Append(tooltip, npcId, "NPC ID")
end

local function OnQuestTooltip(tooltip, data)
  if not FTK:IsEnabled(MODULE_ID) then
    return
  end
  Append(tooltip, IdFromData(data), "Quest ID")
end

local function OnAuraTooltip(tooltip)
  if not FTK:IsEnabled(MODULE_ID) or not tooltip then
    return
  end
  Append(tooltip, IdFromTooltip(tooltip), "Spell ID")
end

local function TryPostCall(processor, dataType, handler)
  if not dataType then
    return false
  end
  local ok = pcall(processor.AddTooltipPostCall, dataType, handler)
  return ok
end

local function Install()
  if installed then
    return
  end
  installed = true

  local hooked = false
  local processor = TooltipDataProcessor
  local types = Enum and Enum.TooltipDataType
  if processor and processor.AddTooltipPostCall and types then
    if TryPostCall(processor, types.Spell, OnSpellTooltip) then
      hooked = true
    end
    if TryPostCall(processor, types.UnitAura, OnSpellTooltip) then
      hooked = true
    end
    if TryPostCall(processor, types.Item, OnItemTooltip) then
      hooked = true
    end
    if TryPostCall(processor, types.Unit, OnUnitTooltip) then
      hooked = true
    end
    if TryPostCall(processor, types.Quest, OnQuestTooltip) then
      hooked = true
    end
    TryPostCall(processor, types.Toy, OnItemTooltip)
    TryPostCall(processor, types.PetAction, OnPetAction)
  end

  if GameTooltip and GameTooltip.HookScript then
    local ok = pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetSpell", OnLegacySpell)
    if ok then
      hooked = true
    end
    local itemOk = pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetItem", OnLegacyItem)
    if itemOk then
      hooked = true
    end
  end
  if ItemRefTooltip and ItemRefTooltip.HookScript then
    pcall(ItemRefTooltip.HookScript, ItemRefTooltip, "OnTooltipSetSpell", OnLegacySpell)
    pcall(ItemRefTooltip.HookScript, ItemRefTooltip, "OnTooltipSetItem", OnLegacyItem)
  end

  if hooksecurefunc and GameTooltip and type(GameTooltip.SetBagItem) == "function" then
    local ok = pcall(hooksecurefunc, GameTooltip, "SetBagItem", function(tooltip, bag, slot)
      local plainBag = PlainNumber(bag)
      local plainSlot = PlainNumber(slot)
      if plainBag == nil or plainSlot == nil or plainSlot < 1 then
        containerSlot[tooltip] = nil
        return
      end
      containerSlot[tooltip] = { bag = plainBag, slot = plainSlot }
    end)
    if ok then
      hooked = true
    end
  end

  if hooksecurefunc and GameTooltip then
    local auraMethods = {
      "SetUnitAura",
      "SetUnitBuff",
      "SetUnitDebuff",
      "SetUnitAuraByAuraInstanceID",
      "SetUnitBuffByAuraInstanceID",
      "SetUnitDebuffByAuraInstanceID",
    }
    local i
    for i = 1, #auraMethods do
      local methodName = auraMethods[i]
      if type(GameTooltip[methodName]) == "function" then
        local ok = pcall(hooksecurefunc, GameTooltip, methodName, OnAuraTooltip)
        if ok then
          hooked = true
        end
      end
    end
  end

  if not hooked then
    FTK:Print("ID tooltips could not hook the tooltip.")
  end
end

local function CheckLine(parent, label, y, getter, setter)
  local box = CreateFrame("CheckButton", nil, parent)
  box:SetSize(24, 24)
  box:SetPoint("TOPLEFT", 0, y)
  box:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
  box:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
  box:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
  box:SetChecked(getter() == true)
  box:SetScript("OnClick", function(self)
    setter(self:GetChecked() == true)
  end)
  local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  text:SetPoint("LEFT", box, "RIGHT", 4, 0)
  text:SetText(label)
  return y - 28
end

local function BuildOptions(_, parent)
  local y = -4
  local note = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  note:SetPoint("TOPLEFT", 0, y)
  note:SetWidth(420)
  note:SetJustifyH("LEFT")
  note:SetWordWrap(true)
  note:SetText("Vendor price shows what a merchant would pay for one item, and for the whole stack when you hover a stack in your bags.")
  y = y - 40
  y = CheckLine(parent, "Vendor price", y, function()
    return VendorPriceConfig().showVendorPrice ~= false
  end, function(value)
    VendorPriceConfig().showVendorPrice = value == true
  end)
  parent:SetHeight(80)
end

FTK:RegisterModule({
  id = MODULE_ID,
  name = "ID Tooltips",
  description = "Shows spell, item, NPC, and quest IDs on the tooltip under your cursor. Bag quest items also show the quest name when that slot knows it. Optional vendor sell price for items.",
  defaultEnabled = true,
  BuildOptions = BuildOptions,
  onEnable = function()
    VendorPriceConfig()
    Install()
    questData:RegisterEvent("QUEST_DATA_LOAD_RESULT")
    questData:RegisterEvent("QUEST_LOG_UPDATE")
    questData:RegisterEvent("QUEST_ACCEPTED")
  end,
  -- Hooks stay installed. While the feature is off, the callbacks add nothing.
  onDisable = function()
    questData:UnregisterEvent("QUEST_DATA_LOAD_RESULT")
    questData:UnregisterEvent("QUEST_LOG_UPDATE")
    questData:UnregisterEvent("QUEST_ACCEPTED")
    questsByItem = nil
    titleByQuest = nil
  end,
})

