--[[
  Clean Bank. Groups the open bank with the same sections as Clean Bags,
  in the same section order. Default order: the player's own categories
  first, then
  Quest Items, Munitions, Reagents, Crafting, equipment sets, Gear, General, Junk, Empty.

  Uses the bank's own item buttons. A secret item id is left in General.
  Alt+right-click on an item opens the own-category menu, right-click on
  a section label the move menu (BagCategoryMenu.lua). Small sections
  share a row when they fit (BagSectionFlow.lua). A grip in the bottom
  right corner sets the window size, and items beyond the window height
  scroll (BagWindow.lua).
]]

local FTK = ForeverForge
if not FTK or not FTK.CleanBagRules then
  error("ForeverForge: BagSections.lua must load before Modules/CleanBank.lua")
end

local Rules = FTK.CleanBagRules
-- The player's own categories: storage and the Alt+right-click menu.
local Categories = FTK.BagCategoryStore
local CategoryMenu = FTK.BagCategoryMenu
-- Sections side by side, and the scrolling, resizable window.
local Flow = FTK.BagSectionFlow
local BagWindow = FTK.BagWindow
local MODULE_ID = "CleanBank"
local ITEM_GAP_X = 5
local ITEM_GAP_Y = 5
local ITEM_LEFT = 12
local HEADER_H = 20
local HEADER_GAP = 4
local SECTION_GAP = 8
local BLOCK_GAP = 12
local TOP_OFFSET = 40
local BOTTOM_PAD = 100
local PANEL_MARGIN = 24
local MIN_COLUMNS = 8
local MAX_COLUMNS = 20
local MIN_PANEL_HEIGHT = TOP_OFFSET + BOTTOM_PAD + HEADER_H + HEADER_GAP + 37

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

local hooked = false
local layingOut = false
local warned = false
local headerPool = {}
local headerUsed = 0
-- Scroll and size of the bank window (BagWindow.lua), the frame that
-- carries its widgets, and the heights that show every item, used when
-- items are revealed for combat.
local bankView
local bankChrome
local revealPanelHeight
local revealChrome = 0

local function BankPanel()
  local frame = _G.BankFrame
  if frame and frame.BankPanel and frame.BankPanel.EnumerateValidItems then
    return frame, frame.BankPanel
  end
  return frame, nil
end

local function ButtonBagSlot(button, panel)
  local bag, slot
  if type(button) ~= "table" then
    return nil, nil
  end
  if button.GetBankTabID then
    local ok, value = pcall(button.GetBankTabID, button)
    if ok then
      bag = Rules.PlainNumber(value)
    end
  end
  if not bag and button.bankTabID then
    bag = Rules.PlainNumber(button.bankTabID)
  end
  if not bag and panel and panel.GetSelectedTabID then
    local ok, value = pcall(panel.GetSelectedTabID, panel)
    if ok then
      bag = Rules.PlainNumber(value)
    end
  end
  if button.GetContainerSlotID then
    local ok, value = pcall(button.GetContainerSlotID, button)
    if ok then
      slot = Rules.PlainNumber(value)
    end
  end
  if not slot and button.GetID then
    local ok, value = pcall(button.GetID, button)
    if ok then
      slot = Rules.PlainNumber(value)
    end
  end
  if not bag then
    local bankBag = Enum and Enum.BagIndex and Enum.BagIndex.Bank
    bag = Rules.PlainNumber(bankBag) or -1
  end
  return bag, slot
end

local function CollectButtons(panel)
  local buttons = {}
  if panel and panel.EnumerateValidItems then
    local ok, iter, state, index = pcall(panel.EnumerateValidItems, panel)
    if ok and type(iter) == "function" then
      -- The bank iterator returns the button first and a validity flag second.
      local itemButton, isValid
      for itemButton, isValid in iter, state, index do
        if type(itemButton) == "table" and isValid ~= false then
          buttons[#buttons + 1] = itemButton
        end
      end
    end
  end
  if #buttons == 0 then
    local index = 1
    while true do
      local button = _G["BankFrameItem" .. index]
      if not button then
        break
      end
      buttons[#buttons + 1] = button
      index = index + 1
    end
  end
  return buttons
end

local function AcquireHeader(parent)
  headerUsed = headerUsed + 1
  local header = headerPool[headerUsed]
  if not header then
    header = CreateFrame("Frame", nil, parent)
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
    headerPool[headerUsed] = header
  end
  header:EnableMouse(false)
  header:SetParent(parent)
  header:Show()
  return header
end

local function HideUnusedHeaders()
  local index
  for index = headerUsed + 1, #headerPool do
    headerPool[index]:Hide()
  end
end

local function ButtonSize(button)
  local width = button and Rules.PlainNumber(button:GetWidth()) or nil
  local height = button and Rules.PlainNumber(button:GetHeight()) or nil
  if not width or width < 20 then
    width = 37
  end
  if not height or height < 20 then
    height = 37
  end
  return width, height
end

local function Place(button, parent, x, y)
  button:ClearAllPoints()
  button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  button:Show()
end

-- Frame for the bank's grip and scroll bar, above the bank's item buttons.
local function BankChrome(panel)
  if not bankChrome then
    bankChrome = CreateFrame("Frame", nil, panel)
    bankChrome:SetAllPoints(panel)
    bankChrome:EnableMouse(false)
  end
  local level = Rules.PlainNumber(panel:GetFrameLevel()) or 1
  bankChrome:SetFrameLevel(level + 40)
  bankChrome:Show()
  return bankChrome
end

-- Combat lockdown starts after PLAYER_REGEN_DISABLED. From that event,
-- every item goes back to its unscrolled place and shows.
local function RevealScrolledItems()
  local frame, panel = BankPanel()
  if not frame or not panel or not bankView or not revealPanelHeight then
    return
  end
  local revealed = bankView:Reveal(function(button, x, top)
    Place(button, panel, x, -top)
  end)
  if revealed then
    panel:SetHeight(revealPanelHeight)
    frame:SetHeight(revealPanelHeight + revealChrome)
  end
end

local function Layout(frame, panel)
  if layingOut or not FTK:IsEnabled(MODULE_ID) or not frame or not panel or not panel:IsShown() then
    return
  end
  local buttons = CollectButtons(panel)
  if #buttons == 0 then
    return
  end
  layingOut = true
  headerUsed = 0
  if not panel.ftkBaseHeight then
    panel.ftkBaseHeight = Rules.PlainNumber(panel:GetHeight())
    frame.ftkBaseHeight = Rules.PlainNumber(frame:GetHeight())
    panel.ftkBaseWidth = Rules.PlainNumber(panel:GetWidth())
    frame.ftkBaseWidth = Rules.PlainNumber(frame:GetWidth())
  end

  local setByItem, setBySlot = Rules.EquipmentSetMaps()
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
  -- Item id of a bank button at click time, for the category menu.
  local function ItemIDOf(button)
    local bag, slot = ButtonBagSlot(button, panel)
    local item = Rules.ReadItem(bag, slot)
    return item and item.itemID
  end

  local index
  for index = 1, #SECTIONS do
    Group(SECTIONS[index].id, SECTIONS[index].title)
  end
  for index = 1, #buttons do
    local button = buttons[index]
    CategoryMenu:Attach(button, MODULE_ID, ItemIDOf)
    local bag, slot = ButtonBagSlot(button, panel)
    local item = Rules.ReadItem(bag, slot)
    if not item then
      Group("empty", "Empty").empties[#Group("empty", "Empty").empties + 1] = button
    else
      local category, setTitle = Rules.CategoryFor(item, bag, slot, setByItem, setBySlot)
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
  -- By default own categories come first, in the order they were created.
  local customIDs = Categories:OrderedGroupIDs(groupOrder, groups)
  for index = 1, #customIDs do
    SortEntries(groups[customIDs[index]].items)
    ordered[#ordered + 1] = groups[customIDs[index]]
  end
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
  -- The player's section order wins over the default order built above.
  Categories:SortGroups(ordered)
  local orderedIDs = {}
  for index = 1, #ordered do
    orderedIDs[index] = ordered[index].id
  end

  local buttonWidth, buttonHeight = ButtonSize(buttons[1])
  local metrics = {
    columns = MIN_COLUMNS,
    buttonWidth = buttonWidth,
    buttonHeight = buttonHeight,
    gapX = ITEM_GAP_X,
    gapY = ITEM_GAP_Y,
    headerHeight = HEADER_H,
    headerGap = HEADER_GAP,
    rowGap = SECTION_GAP,
    blockGap = BLOCK_GAP,
  }
  -- The frame parts around the panel, from the sizes Blizzard gave both.
  local chromeHeight = 0
  if frame.ftkBaseHeight and panel.ftkBaseHeight then
    chromeHeight = frame.ftkBaseHeight - panel.ftkBaseHeight
  end
  if chromeHeight < 0 or chromeHeight > 180 then
    chromeHeight = 36
  end
  local chromeWidth = 0
  if frame.ftkBaseWidth and panel.ftkBaseWidth then
    chromeWidth = frame.ftkBaseWidth - panel.ftkBaseWidth
  end
  if chromeWidth < 0 or chromeWidth > 180 then
    chromeWidth = 0
  end
  local savedWidth, savedHeight = bankView:SavedSize()
  if savedWidth then
    metrics.columns = Flow.ColumnsForWidth(savedWidth - chromeWidth, PANEL_MARGIN, metrics, MIN_COLUMNS, MAX_COLUMNS)
  else
    local panelWidth = panel.ftkBaseWidth or Rules.PlainNumber(panel:GetWidth()) or 400
    local columns = math.floor((panelWidth - PANEL_MARGIN) / (buttonWidth + ITEM_GAP_X))
    if columns < MIN_COLUMNS then
      columns = MIN_COLUMNS
    end
    if columns > 16 then
      columns = 16
    end
    metrics.columns = columns
  end
  local gridWidth = Flow.GridWidth(metrics.columns, metrics)

  -- Labels first: a label can make its section wider than its items.
  local sections = {}
  local headers = {}
  for index = 1, #ordered do
    local group = ordered[index]
    local header = AcquireHeader(panel)
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
    if FTK.QuickDrop and FTK.QuickDrop.Attach then
      FTK.QuickDrop:Attach(header, group.items, "withdraw", group.title, function(button)
        return ButtonBagSlot(button, panel)
      end)
    end
    CategoryMenu:AttachHeader(header, MODULE_ID, group.id, group.title, orderedIDs)

    local placed = {}
    local itemIndex
    for itemIndex = 1, #group.items do
      placed[#placed + 1] = group.items[itemIndex].button
    end
    for itemIndex = 1, #group.empties do
      placed[#placed + 1] = group.empties[itemIndex]
    end
    headers[index] = header
    sections[index] = { count = #placed, headerWidth = headerWidth, buttons = placed }
  end

  -- The panel is as tall as its content (at least Blizzard's height), at
  -- most the saved window height and the room on screen; the rest scrolls.
  local blocks, contentHeight = Flow.Arrange(sections, metrics)
  local fullHeight = TOP_OFFSET + contentHeight + SECTION_GAP + BOTTOM_PAD
  if panel.ftkBaseHeight and fullHeight < panel.ftkBaseHeight then
    fullHeight = panel.ftkBaseHeight
  end
  local height = fullHeight
  if savedHeight and savedHeight - chromeHeight < height then
    height = savedHeight - chromeHeight
  end
  local available = bankView:AvailableHeight(frame)
  if available and available - chromeHeight < height then
    height = available - chromeHeight
  end
  if height < MIN_PANEL_HEIGHT then
    height = MIN_PANEL_HEIGHT
  end
  bankView:Begin(BankChrome(panel), frame, panel, TOP_OFFSET, height - TOP_OFFSET - BOTTOM_PAD,
    contentHeight + SECTION_GAP, buttonHeight + ITEM_GAP_Y)

  for index = 1, #ordered do
    local block = blocks[index]
    local header = headers[index]
    local section = sections[index]
    local headerTop = bankView:Locate(block.y, HEADER_H)
    header:ClearAllPoints()
    if headerTop then
      header:SetPoint("TOPLEFT", panel, "TOPLEFT", ITEM_LEFT + block.x, -headerTop)
      header:SetWidth(math.min(section.headerWidth, block.width))
    else
      header:Hide()
    end
    for itemIndex = 1, #section.buttons do
      local button = section.buttons[itemIndex]
      local x, y = Flow.ItemOffset(block, itemIndex, metrics)
      local top = bankView:Track(button, ITEM_LEFT + x, y, buttonHeight)
      if top then
        Place(button, panel, ITEM_LEFT + x, -top)
      else
        button:Hide()
      end
    end
  end

  HideUnusedHeaders()
  revealPanelHeight = fullHeight
  revealChrome = chromeHeight
  panel:SetHeight(height)
  frame:SetHeight(height + chromeHeight)
  local barRoom = bankView:BarRoom()
  if savedWidth or barRoom > 0 then
    local width = gridWidth + PANEL_MARGIN + barRoom
    panel:SetWidth(width)
    frame:SetWidth(width + chromeWidth)
  elseif panel.ftkBaseWidth and frame.ftkBaseWidth then
    panel:SetWidth(panel.ftkBaseWidth)
    frame:SetWidth(frame.ftkBaseWidth)
  end
  if UpdateUIPanelPositions then
    pcall(UpdateUIPanelPositions, frame)
  end
  layingOut = false
end

local function RequestLayout()
  if not FTK:IsEnabled(MODULE_ID) then
    return
  end
  local frame, panel = BankPanel()
  if not panel then
    if frame and frame:IsShown() and not warned then
      warned = true
      FTK:Print("Clean Bank: the bank item panel was not found.")
    end
    return
  end
  if panel:IsShown() then
    Layout(frame, panel)
  end
end

local function ScheduleLayout()
  RequestLayout()
  if C_Timer and C_Timer.After then
    C_Timer.After(0, RequestLayout)
    C_Timer.After(0.1, RequestLayout)
  end
end

local function RestoreBank()
  headerUsed = 0
  HideUnusedHeaders()
  if bankView then
    bankView:Reveal(function(button)
      button:Show()
    end)
    bankView:HideWidgets()
  end
  local frame, panel = BankPanel()
  if panel and panel.RefreshBankPanel then
    pcall(panel.RefreshBankPanel, panel)
  end
  if frame and frame.ftkBaseHeight then
    frame:SetHeight(frame.ftkBaseHeight)
  end
  if panel and panel.ftkBaseHeight then
    panel:SetHeight(panel.ftkBaseHeight)
  end
  if frame and frame.ftkBaseWidth then
    frame:SetWidth(frame.ftkBaseWidth)
  end
  if panel and panel.ftkBaseWidth then
    panel:SetWidth(panel.ftkBaseWidth)
  end
  if frame and UpdateUIPanelPositions then
    pcall(UpdateUIPanelPositions, frame)
  end
end

local function InstallHook()
  if hooked or not hooksecurefunc then
    return hooked
  end
  local _, panel = BankPanel()
  if not panel then
    return false
  end
  local methods = {
    "GenerateItemSlotsForSelectedTab",
    "RefreshAllItemsForSelectedTab",
    "RefreshBankPanel",
  }
  local index
  for index = 1, #methods do
    local name = methods[index]
    if type(panel[name]) == "function" then
      hooksecurefunc(panel, name, function()
        if layingOut or not FTK:IsEnabled(MODULE_ID) then
          return
        end
        ScheduleLayout()
      end)
    end
  end
  local frame = _G.BankFrame
  if frame and frame.HookScript and not frame.ftkCleanBankShow then
    frame.ftkCleanBankShow = true
    frame:HookScript("OnShow", function()
      ScheduleLayout()
    end)
  end
  hooked = true
  return true
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
  if not FTK:IsEnabled(MODULE_ID) then
    return
  end
  if event == "PLAYER_REGEN_DISABLED" then
    RevealScrolledItems()
    return
  end
  InstallHook()
  ScheduleLayout()
end)

FTK.CleanBankRefresh = ScheduleLayout

-- The bank window is anchored at its top left, so the grip sits bottom
-- right.
bankView = BagWindow.NewView({
  moduleID = MODULE_ID,
  corner = "BOTTOMRIGHT",
  minWidth = PANEL_MARGIN + (MIN_COLUMNS * (37 + ITEM_GAP_X)),
  minHeight = MIN_PANEL_HEIGHT,
  onChange = ScheduleLayout,
})

FTK:RegisterModule({
  id = MODULE_ID,
  name = "Clean Bank",
  description = "Groups the bank into Quest Items, Munitions, Reagents, Crafting, equipment sets, Gear, General, Junk, and Empty. Alt+right-click an item to put it in a category of your own. Right-click a section label to move it up or down. Drag the bottom right grip to resize.",
  defaultEnabled = true,
  onEnable = function()
    InstallHook()
    events:RegisterEvent("BANKFRAME_OPENED")
    events:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
    events:RegisterEvent("PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED")
    events:RegisterEvent("BAG_UPDATE")
    events:RegisterEvent("EQUIPMENT_SETS_CHANGED")
    events:RegisterEvent("PLAYER_REGEN_DISABLED")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    ScheduleLayout()
  end,
  onDisable = function()
    events:UnregisterAllEvents()
    RestoreBank()
  end,
})
