--[[
  Menus for own bag categories.

  Alt+right-click on an item in the backpack (Clean Bags) or the bank
  (Clean Bank) opens a small menu next to the item:
    - the existing own categories (a click puts the item there),
    - "New category..." (type a name, the item goes in at once),
    - "Back to default" (only for an item that is in a category).

  Right-click on the label of any section, own or default, opens a menu
  at the mouse with "Move up" and "Move down". A move steps past the
  neighbouring section in the same window.

  Blizzard's click handler treats an Alt click as a modified click, so the
  item is neither used nor moved. This file hooks the button's PostClick
  with HookScript: it runs after every click handler, keeps OnClick
  untouched, and survives a SetScript on OnClick (the reagent-bag slots
  set their own). On a reagent-bag slot the secure use overlay hands a
  modified right-click to the item button, so the hook runs there too.
]]

local FTK = ForeverForge
if not FTK or not FTK.BagCategoryStore then
  error("ForeverForge: BagCategoryStore.lua must load before Modules/BagCategoryMenu.lua")
end

local Store = FTK.BagCategoryStore

local FRAME_NAME = "ForeverForgeBagCategoryMenu"
local POPUP_ID = "FOREVERFORGE_BAG_CATEGORY_NEW"
local MENU_WIDTH = 220
local ROW_HEIGHT = 20
local PAD = 10
local TITLE_HEIGHT = 18
local DIVIDER_GAP = 6

local TEXTS = {
  enUS = {
    newCategory = "New category...",
    backToDefault = "Back to default",
    moveUp = "Move up",
    moveDown = "Move down",
    popup = "Name of the new category for %s:",
    unknownItem = "Item",
    errors = {
      item = "This item cannot be put in a category.",
      empty = "The category name must not be empty.",
      pipe = "The category name must not contain \"|\".",
      length = "The category name may be at most " .. Store.MAX_NAME_LENGTH .. " characters long.",
    },
  },
  deDE = {
    newCategory = "Neue Kategorie...",
    backToDefault = "Zurück in Standard",
    moveUp = "Nach oben",
    moveDown = "Nach unten",
    popup = "Name der neuen Kategorie für %s:",
    unknownItem = "Item",
    errors = {
      item = "Dieses Item lässt sich keiner Kategorie zuordnen.",
      empty = "Der Kategoriename darf nicht leer sein.",
      pipe = "Der Kategoriename darf kein \"|\" enthalten.",
      length = "Der Kategoriename darf höchstens " .. Store.MAX_NAME_LENGTH .. " Zeichen lang sein.",
    },
  },
}

local L = TEXTS[GetLocale and GetLocale() or "enUS"] or TEXTS.enUS

local Menu = {}

-- Hooked item buttons: button -> { moduleID, itemIDOf }. Weak keys, so no
-- fields are written into Blizzard's frames.
local attached = setmetatable({}, { __mode = "k" })

-- Hooked section headers: header -> { moduleID, id, title, visibleIDs }.
-- Headers are pooled, so every layout sets the entry again.
local headers = setmetatable({}, { __mode = "k" })

local menuFrame

-- Rebuilds Clean Bags and Clean Bank so a change shows at once.
local function RefreshLayouts()
  if type(FTK.CleanBagsRefresh) == "function" then
    FTK.CleanBagsRefresh()
  end
  if type(FTK.CleanBankRefresh) == "function" then
    FTK.CleanBankRefresh()
  end
end

-- Display name of an item type, or a placeholder while the client does
-- not know it yet.
local function ItemName(itemID)
  local name
  if C_Item and C_Item.GetItemNameByID then
    local ok, value = pcall(C_Item.GetItemNameByID, itemID)
    if ok and type(value) == "string" then
      name = value
    end
  end
  if (not name or name == "") and GetItemInfo then
    local ok, value = pcall(GetItemInfo, itemID)
    if ok and type(value) == "string" then
      name = value
    end
  end
  if not name or name == "" then
    return L.unknownItem .. " " .. itemID
  end
  return name
end

-- Assigns an item, reports a problem in chat and refreshes the layouts.
-- Returns true on success.
local function AssignAndRefresh(itemID, rawName)
  local ok, problem = Store:Assign(itemID, rawName)
  if not ok then
    FTK:Print(L.errors[problem] or L.errors.item)
    return false
  end
  RefreshLayouts()
  return true
end

-- Edit box of a StaticPopup dialog.
local function EditBoxOf(dialog)
  if dialog and dialog.GetEditBox then
    local ok, box = pcall(dialog.GetEditBox, dialog)
    if ok and box then
      return box
    end
  end
  return dialog and dialog.editBox
end

-- Registers the dialog for a new category name once.
local function EnsurePopup()
  if not StaticPopupDialogs or StaticPopupDialogs[POPUP_ID] then
    return
  end
  StaticPopupDialogs[POPUP_ID] = {
    text = L.popup,
    button1 = (type(ACCEPT) == "string" and ACCEPT) or "OK",
    button2 = (type(CANCEL) == "string" and CANCEL) or "Cancel",
    hasEditBox = true,
    maxLetters = Store.MAX_NAME_LENGTH,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    preferredIndex = 3,
    OnShow = function(dialog)
      local box = EditBoxOf(dialog)
      if box then
        box:SetText("")
        box:SetFocus()
      end
    end,
    -- Returning true keeps the dialog open so an invalid name can be fixed.
    OnAccept = function(dialog, data)
      local box = EditBoxOf(dialog)
      if not box or type(data) ~= "table" then
        return false
      end
      return not AssignAndRefresh(data.itemID, box:GetText())
    end,
    EditBoxOnEnterPressed = function(editBox, data)
      if type(data) ~= "table" then
        editBox:GetParent():Hide()
        return
      end
      if AssignAndRefresh(data.itemID, editBox:GetText()) then
        editBox:GetParent():Hide()
      end
    end,
    EditBoxOnEscapePressed = function(editBox)
      editBox:GetParent():Hide()
    end,
  }
end

-- Asks for the name of a new category and puts the item there.
local function PromptNewCategory(itemID)
  EnsurePopup()
  if StaticPopup_Show and StaticPopupDialogs and StaticPopupDialogs[POPUP_ID] then
    StaticPopup_Show(POPUP_ID, ItemName(itemID), nil, { itemID = itemID })
  end
end

-- Background and border in the style of the Forever Forge menu.
local function ApplyBackdrop(frame)
  if frame.SetBackdrop then
    frame:SetBackdrop({
      bgFile = "Interface\\Buttons\\WHITE8x8",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true,
      tileSize = 16,
      edgeSize = 14,
      insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0.07, 0.05, 0.04, 0.96)
    frame:SetBackdropBorderColor(0.78, 0.64, 0.32, 1)
    return
  end
  local background = frame:CreateTexture(nil, "BACKGROUND")
  background:SetAllPoints()
  background:SetColorTexture(0.07, 0.05, 0.04, 0.96)
end

-- A click on a menu row runs its action and closes the menu.
local function OnRowClick(row)
  local action = row.action
  if menuFrame then
    menuFrame:Hide()
  end
  if type(action) == "function" then
    action()
  end
end

-- Menu row at `index`, created on first use.
local function AcquireRow(index)
  local row = menuFrame.rows[index]
  if row then
    return row
  end
  row = CreateFrame("Button", nil, menuFrame)
  row:SetSize(MENU_WIDTH - (PAD * 2), ROW_HEIGHT)
  local highlight = row:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetAllPoints()
  highlight:SetColorTexture(0.9, 0.75, 0.35, 0.15)
  local check = row:CreateTexture(nil, "ARTWORK")
  check:SetSize(16, 16)
  check:SetPoint("LEFT", 0, 0)
  check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
  row.check = check
  local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  label:SetPoint("LEFT", 20, 0)
  label:SetPoint("RIGHT", -2, 0)
  label:SetJustifyH("LEFT")
  label:SetWordWrap(false)
  row.label = label
  row:SetScript("OnClick", OnRowClick)
  menuFrame.rows[index] = row
  return row
end

-- Creates the menu frame once. It closes on Escape, on a click outside,
-- and as soon as its item is no longer visible (bag or bank closed).
local function EnsureMenuFrame()
  if menuFrame then
    return menuFrame
  end
  local ok, created = pcall(CreateFrame, "Frame", FRAME_NAME, UIParent, "BackdropTemplate")
  if ok and type(created) == "table" then
    menuFrame = created
  else
    menuFrame = CreateFrame("Frame", FRAME_NAME, UIParent)
  end
  menuFrame:Hide()
  menuFrame:SetWidth(MENU_WIDTH)
  menuFrame:SetFrameStrata("DIALOG")
  menuFrame:SetToplevel(true)
  menuFrame:SetClampedToScreen(true)
  menuFrame:EnableMouse(true)
  ApplyBackdrop(menuFrame)
  menuFrame.rows = {}

  local title = menuFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", PAD, -PAD)
  title:SetPoint("TOPRIGHT", -PAD, -PAD)
  title:SetHeight(TITLE_HEIGHT)
  title:SetJustifyH("LEFT")
  title:SetWordWrap(false)
  title:SetTextColor(0.93, 0.8, 0.45)
  menuFrame.title = title

  local divider = menuFrame:CreateTexture(nil, "ARTWORK")
  divider:SetHeight(1)
  divider:SetColorTexture(0.78, 0.64, 0.32, 0.6)
  menuFrame.divider = divider

  menuFrame:SetScript("OnShow", function(self)
    pcall(self.RegisterEvent, self, "GLOBAL_MOUSE_DOWN")
  end)
  menuFrame:SetScript("OnHide", function(self)
    pcall(self.UnregisterEvent, self, "GLOBAL_MOUSE_DOWN")
    self.anchor = nil
  end)
  menuFrame:SetScript("OnEvent", function(self, event)
    if event == "GLOBAL_MOUSE_DOWN" and not self:IsMouseOver() then
      self:Hide()
    end
  end)
  menuFrame:SetScript("OnUpdate", function(self)
    if self.anchor and not self.anchor:IsVisible() then
      self:Hide()
    end
  end)

  if type(UISpecialFrames) == "table" then
    table.insert(UISpecialFrames, FRAME_NAME)
  end
  return menuFrame
end

-- Menu entries for an item: label, checked, dividerBefore and action.
local function BuildEntries(itemID)
  local _, currentName = Store:CategoryOf(itemID)
  local entries = {}
  local names = Store:Names()
  for index = 1, #names do
    local name = names[index]
    entries[#entries + 1] = {
      label = name,
      checked = name == currentName,
      action = function()
        AssignAndRefresh(itemID, name)
      end,
    }
  end
  entries[#entries + 1] = {
    label = L.newCategory,
    dividerBefore = #names > 0,
    action = function()
      PromptNewCategory(itemID)
    end,
  }
  if currentName then
    entries[#entries + 1] = {
      label = L.backToDefault,
      action = function()
        Store:Reset(itemID)
        RefreshLayouts()
      end,
    }
  end
  return entries
end

-- Moves a section, then refreshes the layouts.
local function MoveAndRefresh(id, direction, visibleIDs)
  if Store:MoveSection(id, direction, visibleIDs) then
    RefreshLayouts()
  end
end

-- Menu entries for a section header: "Move up" unless it is the first
-- section shown, "Move down" unless it is the last one shown.
local function BuildHeaderEntries(id, visibleIDs)
  local position
  for index = 1, #visibleIDs do
    if visibleIDs[index] == id then
      position = index
      break
    end
  end
  local entries = {}
  if not position then
    return entries
  end
  if position > 1 then
    entries[#entries + 1] = {
      label = L.moveUp,
      action = function()
        MoveAndRefresh(id, -1, visibleIDs)
      end,
    }
  end
  if position < #visibleIDs then
    entries[#entries + 1] = {
      label = L.moveDown,
      action = function()
        MoveAndRefresh(id, 1, visibleIDs)
      end,
    }
  end
  return entries
end

-- Fills the menu with entries and shows it, at the mouse when atCursor
-- is true, else next to the anchor. The menu closes once the anchor is
-- hidden.
local function ShowMenu(anchor, title, entries, atCursor)
  local frame = EnsureMenuFrame()
  frame:Hide()
  frame.title:SetText(title)

  local offset = PAD + TITLE_HEIGHT + 4
  frame.divider:Hide()
  for index = 1, #entries do
    local entry = entries[index]
    if entry.dividerBefore then
      frame.divider:ClearAllPoints()
      frame.divider:SetPoint("TOPLEFT", PAD, -(offset + (DIVIDER_GAP / 2)))
      frame.divider:SetPoint("TOPRIGHT", -PAD, -(offset + (DIVIDER_GAP / 2)))
      frame.divider:Show()
      offset = offset + DIVIDER_GAP
    end
    local row = AcquireRow(index)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", PAD, -offset)
    row.label:SetText(entry.label)
    row.check:SetShown(entry.checked == true)
    row.action = entry.action
    row:Show()
    offset = offset + ROW_HEIGHT
  end
  for index = #entries + 1, #frame.rows do
    frame.rows[index]:Hide()
    frame.rows[index].action = nil
  end

  frame:SetHeight(offset + PAD)
  frame:ClearAllPoints()
  if atCursor and GetCursorPosition then
    local x, y = GetCursorPosition()
    local scale = frame:GetEffectiveScale()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
  else
    frame:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 4, 0)
  end
  frame.anchor = anchor
  frame:Show()
  frame:Raise()
end

-- Opens the item menu next to an item button.
function Menu:Open(anchor, itemID)
  ShowMenu(anchor, ItemName(itemID), BuildEntries(itemID), false)
end

-- True for Alt+right-click without Shift or Ctrl.
local function IsCategoryClick(mouseButton)
  return mouseButton == "RightButton"
    and IsAltKeyDown() == true
    and not IsShiftKeyDown()
    and not IsControlKeyDown()
end

-- PostClick of an item button: runs after its click handler.
local function OnItemButtonClick(button, mouseButton)
  if not IsCategoryClick(mouseButton) then
    return
  end
  local entry = attached[button]
  if not entry or not FTK:IsEnabled(entry.moduleID) then
    return
  end
  local ok, itemID = pcall(entry.itemIDOf, button)
  if not ok or type(itemID) ~= "number" then
    return
  end
  Menu:Open(button, itemID)
end

-- Connects a bag or bank item button to the menu. Calling it again is
-- safe: the hook is made once, module and item reader are updated.
-- moduleID is the module that must be on (BagSections or CleanBank);
-- itemIDOf returns the button's item id at click time, or nil.
function Menu:Attach(button, moduleID, itemIDOf)
  if type(button) ~= "table" or not button.HookScript or type(itemIDOf) ~= "function" then
    return
  end
  local entry = attached[button]
  if entry then
    entry.moduleID = moduleID
    entry.itemIDOf = itemIDOf
    return
  end
  attached[button] = { moduleID = moduleID, itemIDOf = itemIDOf }
  button:HookScript("PostClick", OnItemButtonClick)
end

-- Right-click on a header opens the move menu of its section.
local function OnHeaderMouseUp(header, mouseButton)
  if mouseButton ~= "RightButton" then
    return
  end
  local entry = headers[header]
  if not entry or not entry.id or not FTK:IsEnabled(entry.moduleID) then
    return
  end
  local entries = BuildHeaderEntries(entry.id, entry.visibleIDs)
  if #entries == 0 then
    return
  end
  ShowMenu(header, entry.title, entries, true)
end

-- Connects a section header to the move menu and lets it take the mouse.
-- Call it for every header of a layout: id and title name the section
-- the header shows, visibleIDs lists the group ids of that layout from
-- top to bottom.
function Menu:AttachHeader(header, moduleID, id, title, visibleIDs)
  if type(header) ~= "table" or not header.HookScript then
    return
  end
  local entry = headers[header]
  if not entry then
    entry = {}
    headers[header] = entry
    header:HookScript("OnMouseUp", OnHeaderMouseUp)
  end
  entry.moduleID = moduleID
  entry.id = id
  entry.title = title
  entry.visibleIDs = visibleIDs or {}
  header:EnableMouse(true)
end

FTK.BagCategoryMenu = Menu
