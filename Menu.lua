--[[
  Main menu. Lists every registered feature with an on/off switch and,
  when the feature defines one, a Configure button.
]]

local FTK = ForeverForge
if not FTK then
  error("ForeverForge: Core.lua must load before Menu.lua")
end

local Menu = {}

local FRAME_W = 500
local FRAME_H = 560
local PAD = 16
local BODY_W = FRAME_W - (PAD * 2)
local ROW_H = 58
local ROW_GAP = 8
local ROW_W = BODY_W - 22

local LIST_TITLE = "Forever Forge"
local LIST_SUB = "v" .. ForeverForge:AddonVersion() .. ". Enable, disable, and configure each tool."

local function WithBackdrop(frame, bgR, bgG, bgB, bgA, edgeR, edgeG, edgeB, edgeA)
  if not frame.SetBackdrop then
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    if bg.SetColorTexture then
      bg:SetColorTexture(bgR, bgG, bgB, bgA)
    end
    return
  end
  frame:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  frame:SetBackdropColor(bgR, bgG, bgB, bgA)
  frame:SetBackdropBorderColor(edgeR, edgeG, edgeB, edgeA)
end

local function MakeFrame(name, parent, w, h)
  local frame
  local ok, created = pcall(CreateFrame, "Frame", name, parent, "BackdropTemplate")
  if ok and type(created) == "table" then
    frame = created
  else
    frame = CreateFrame("Frame", name, parent)
  end
  if w and h then
    frame:SetSize(w, h)
  end
  return frame
end

local function MakeTextButton(parent, label, width)
  local button
  local ok, created = pcall(CreateFrame, "Button", nil, parent, "UIPanelButtonTemplate")
  if ok and type(created) == "table" then
    button = created
  else
    button = CreateFrame("Button", nil, parent)
    local text = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetAllPoints()
    button:SetFontString(text)
  end
  button:SetSize(width, 22)
  button:SetText(label)
  return button
end

local function ScrollBy(delta)
  local scroll = Menu.scroll
  if not scroll then
    return
  end
  pcall(function()
    local range = scroll:GetVerticalScrollRange() or 0
    local cur = scroll:GetVerticalScroll() or 0
    local y = cur - (delta * 40)
    if y < 0 then
      y = 0
    end
    if y > range then
      y = range
    end
    scroll:SetVerticalScroll(y)
  end)
end

local function SavePosition(frame)
  if not FTK.db or type(FTK.db.menu) ~= "table" then
    return
  end
  local ok, point, _, relPoint, x, y = pcall(frame.GetPoint, frame, 1)
  if not ok or type(point) ~= "string" or type(x) ~= "number" or type(y) ~= "number" then
    return
  end
  local menu = FTK.db.menu
  menu.point = point
  menu.relPoint = type(relPoint) == "string" and relPoint or point
  menu.x = x
  menu.y = y
end

local function RestorePosition(frame)
  local menu = FTK.db and FTK.db.menu
  local function center()
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
  end
  if type(menu) ~= "table" or type(menu.point) ~= "string" or type(menu.x) ~= "number" or type(menu.y) ~= "number" then
    center()
    return
  end
  local ok = pcall(function()
    frame:ClearAllPoints()
    frame:SetPoint(menu.point, UIParent, menu.relPoint or menu.point, menu.x, menu.y)
  end)
  if not ok then
    center()
  end
end

local TEXT_W = ROW_W - 156

local function MakeCheckBox(parent)
  local box = CreateFrame("CheckButton", nil, parent)
  box:SetSize(24, 24)
  box:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
  box:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
  box:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
  box:EnableMouse(false)
  return box
end

local function HasOptions(module)
  return type(module.onConfigure) == "function" or type(module.BuildOptions) == "function"
end

local function GetRow(index)
  local row = Menu.rows[index]
  if row then
    return row
  end
  row = CreateFrame("Button", nil, Menu.content)
  row:SetSize(ROW_W, ROW_H)
  row:RegisterForClicks("LeftButtonUp")

  local bg = row:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  if bg.SetColorTexture then
    bg:SetColorTexture(1, 1, 1, 0.04)
  end
  row.bg = bg

  local box = MakeCheckBox(row)
  box:SetPoint("LEFT", 8, 0)
  row.box = box

  local config = MakeTextButton(row, "Configure", 100)
  config:SetPoint("RIGHT", -8, 0)
  config:SetFrameLevel(row:GetFrameLevel() + 2)
  row.config = config

  local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  name:SetPoint("TOPLEFT", box, "TOPRIGHT", 6, -2)
  name:SetWidth(TEXT_W)
  name:SetJustifyH("LEFT")
  name:SetWordWrap(false)
  if name.SetMaxLines then
    name:SetMaxLines(1)
  end
  row.name = name

  local desc = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  desc:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -2)
  desc:SetWidth(TEXT_W)
  desc:SetJustifyH("LEFT")
  desc:SetJustifyV("TOP")
  desc:SetWordWrap(true)
  if desc.SetMaxLines then
    desc:SetMaxLines(2)
  end
  row.desc = desc

  row:SetScript("OnEnter", function(self)
    if self.bg and self.bg.SetColorTexture then
      self.bg:SetColorTexture(0.9, 0.75, 0.35, 0.1)
    end
  end)
  row:SetScript("OnLeave", function(self)
    if self.bg and self.bg.SetColorTexture then
      self.bg:SetColorTexture(1, 1, 1, 0.04)
    end
  end)
  row:SetScript("OnClick", function(self)
    local id = self.moduleId
    if not id then
      return
    end
    FTK:SetEnabled(id, not FTK:IsEnabled(id))
    Menu.Refresh()
  end)
  config:SetScript("OnClick", function(self)
    local id = self:GetParent().moduleId
    local module = id and FTK:GetModule(id)
    if not module then
      return
    end
    if type(module.onConfigure) == "function" then
      local ok, err = pcall(module.onConfigure, module)
      if not ok then
        FTK:Print(module.name .. " options failed: " .. tostring(err))
      end
      return
    end
    if type(module.BuildOptions) == "function" then
      Menu.ShowConfig(module)
    end
  end)

  Menu.rows[index] = row
  return row
end

function Menu.Refresh()
  if not Menu.content then
    return
  end
  local order = FTK.moduleOrder
  local count = #order
  local i
  for i = 1, count do
    local id = order[i]
    local module = FTK.modules[id]
    local row = GetRow(i)
    row.moduleId = id
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", Menu.content, "TOPLEFT", 0, -((i - 1) * (ROW_H + ROW_GAP)))
    row.name:SetText(FTK.Plain(module.name))
    local description = module.description or ""
    if module._error then
      local err = tostring(module._error):gsub("[\r\n].*", "")
      if description ~= "" then
        description = description .. " "
      end
      description = description .. "Could not turn on: " .. err
      row.desc:SetTextColor(1, 0.45, 0.35)
    elseif FTK:IsEnabled(id) then
      row.desc:SetTextColor(0.78, 0.72, 0.62)
    else
      row.desc:SetTextColor(0.55, 0.52, 0.46)
    end
    row.desc:SetText(FTK.Plain(description))
    local enabled = FTK:IsEnabled(id)
    row.box:SetChecked(enabled)
    if enabled then
      row.name:SetTextColor(0.95, 0.88, 0.72)
    else
      row.name:SetTextColor(0.65, 0.62, 0.55)
    end
    if HasOptions(module) then
      row.config:Show()
    else
      row.config:Hide()
    end
    row:Show()
  end
  for i = count + 1, #Menu.rows do
    Menu.rows[i]:Hide()
    Menu.rows[i].moduleId = nil
  end

  local height = 1
  if count > 0 then
    height = (count * (ROW_H + ROW_GAP)) - ROW_GAP
  end
  Menu.content:SetHeight(height)

  if Menu.empty and Menu.mode ~= "config" then
    if count == 0 then
      Menu.empty:Show()
      if Menu.scroll then
        Menu.scroll:Hide()
      end
    else
      Menu.empty:Hide()
      if Menu.scroll then
        Menu.scroll:Show()
      end
    end
  end
  if Menu.footer then
    Menu.footer:SetText(string.format("v%s | /ff | crumpshot-forever.github.io/ForeverForge", FTK:AddonVersion()))
  end
end

function Menu.ShowList()
  Menu.mode = "list"
  if Menu.configHost then
    Menu.configHost:Hide()
  end
  if Menu.back then
    Menu.back:Hide()
  end
  if Menu.scroll then
    Menu.scroll:Show()
  end
  if Menu.title then
    Menu.title:SetText(LIST_TITLE)
  end
  if Menu.subtitle then
    Menu.subtitle:SetText(LIST_SUB)
  end
  Menu.Refresh()
end

function Menu.ShowConfig(module)
  if not Menu.configHost or not module then
    return
  end
  Menu.mode = "config"
  Menu.scroll:Hide()
  if Menu.empty then
    Menu.empty:Hide()
  end
  Menu.back:Show()
  Menu.configHost:Show()
  Menu.title:SetText(FTK.Plain(module.name))
  local sub = module.description
  if type(sub) ~= "string" or sub == "" then
    sub = "Settings"
  end
  Menu.subtitle:SetText(FTK.Plain(sub))

  local page = Menu.configPages[module.id]
  if not page then
    page = CreateFrame("Frame", nil, Menu.configChild)
    page:SetPoint("TOPLEFT", Menu.configChild, "TOPLEFT", 0, 0)
    page:SetWidth(ROW_W)
    page:SetHeight(400)
    local ok, err = pcall(module.BuildOptions, module, page)
    if not ok then
      local fail = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      fail:SetPoint("TOPLEFT", 4, -4)
      fail:SetWidth(ROW_W - 8)
      fail:SetJustifyH("LEFT")
      fail:SetWordWrap(true)
      fail:SetTextColor(1, 0.45, 0.35)
      fail:SetText(FTK.Plain("Could not open settings: " .. tostring(err)))
    end
    local pageHeight = page:GetHeight()
    if type(pageHeight) ~= "number" or pageHeight < 40 then
      page:SetHeight(400)
      pageHeight = 400
    end
    Menu.configPages[module.id] = page
    Menu.configChild:SetHeight(pageHeight)
  end

  local id, other
  for id, other in pairs(Menu.configPages) do
    if id == module.id then
      other:Show()
      local pageHeight = other:GetHeight()
      if type(pageHeight) ~= "number" or pageHeight < 40 then
        pageHeight = 400
      end
      Menu.configChild:SetHeight(pageHeight)
    else
      other:Hide()
    end
  end
  pcall(Menu.configScroll.SetVerticalScroll, Menu.configScroll, 0)
end

function Menu.Ensure()
  if Menu.frame then
    return Menu.frame
  end

  local frame = MakeFrame("ForeverForgeMenuFrame", UIParent, FRAME_W, FRAME_H)
  frame:Hide()
  frame:SetFrameStrata("DIALOG")
  frame:SetToplevel(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:SetClampedToScreen(true)
  WithBackdrop(frame, 0.07, 0.05, 0.04, 0.96, 0.78, 0.64, 0.32, 1)
  Menu.frame = frame
  Menu.rows = {}
  Menu.configPages = {}

  if type(UISpecialFrames) == "table" then
    table.insert(UISpecialFrames, "ForeverForgeMenuFrame")
  end

  local drag = CreateFrame("Frame", nil, frame)
  drag:SetPoint("TOPLEFT", 8, -6)
  drag:SetPoint("TOPRIGHT", -36, -6)
  drag:SetHeight(50)
  drag:EnableMouse(true)
  drag:RegisterForDrag("LeftButton")
  drag:SetScript("OnDragStart", function()
    frame:StartMoving()
  end)
  drag:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()
    SavePosition(frame)
  end)

  local close
  local closeOk, created = pcall(CreateFrame, "Button", nil, frame, "UIPanelCloseButton")
  if closeOk and type(created) == "table" then
    close = created
    close:SetPoint("TOPRIGHT", 2, 2)
  else
    close = MakeTextButton(frame, "X", 24)
    close:SetPoint("TOPRIGHT", -8, -8)
    close:SetScript("OnClick", function()
      frame:Hide()
    end)
  end
  close:SetFrameLevel(drag:GetFrameLevel() + 5)

  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 18, -12)
  title:SetWidth(FRAME_W - 80)
  title:SetJustifyH("LEFT")
  title:SetWordWrap(false)
  if title.SetMaxLines then
    title:SetMaxLines(1)
  end
  title:SetTextColor(0.93, 0.8, 0.45)
  title:SetText(LIST_TITLE)
  Menu.title = title

  local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
  subtitle:SetWidth(FRAME_W - 90)
  subtitle:SetJustifyH("LEFT")
  subtitle:SetWordWrap(true)
  if subtitle.SetMaxLines then
    subtitle:SetMaxLines(2)
  end
  subtitle:SetTextColor(0.75, 0.7, 0.6)
  subtitle:SetText(LIST_SUB)
  Menu.subtitle = subtitle

  local rule = frame:CreateTexture(nil, "ARTWORK")
  rule:SetPoint("TOPLEFT", 14, -58)
  rule:SetPoint("TOPRIGHT", -14, -58)
  rule:SetHeight(1)
  if rule.SetColorTexture then
    rule:SetColorTexture(0.78, 0.64, 0.32, 0.75)
  end

  local ruleBottom = frame:CreateTexture(nil, "ARTWORK")
  ruleBottom:SetPoint("BOTTOMLEFT", 14, 32)
  ruleBottom:SetPoint("BOTTOMRIGHT", -14, 32)
  ruleBottom:SetHeight(1)
  if ruleBottom.SetColorTexture then
    ruleBottom:SetColorTexture(0.78, 0.64, 0.32, 0.4)
  end

  local body = CreateFrame("Frame", nil, frame)
  body:SetPoint("TOPLEFT", PAD, -66)
  body:SetPoint("BOTTOMRIGHT", -PAD, 40)
  body:EnableMouseWheel(true)
  body:SetScript("OnMouseWheel", function(_, delta)
    if Menu.mode == "config" and Menu.configScroll then
      local scroll = Menu.configScroll
      pcall(function()
        local range = scroll:GetVerticalScrollRange() or 0
        local cur = scroll:GetVerticalScroll() or 0
        local y = cur - (delta * 40)
        if y < 0 then
          y = 0
        end
        if y > range then
          y = range
        end
        scroll:SetVerticalScroll(y)
      end)
      return
    end
    ScrollBy(delta)
  end)

  local back = MakeTextButton(body, "Back", 70)
  back:SetPoint("TOPLEFT", 0, 0)
  back:Hide()
  back:SetScript("OnClick", function()
    Menu.ShowList()
  end)
  Menu.back = back

  local scroll
  local scrollOk, scrollFrame = pcall(CreateFrame, "ScrollFrame", "ForeverForgeMenuScroll", body, "UIPanelScrollFrameTemplate")
  if scrollOk and type(scrollFrame) == "table" then
    scroll = scrollFrame
  else
    scroll = CreateFrame("ScrollFrame", nil, body)
  end
  scroll:SetPoint("TOPLEFT", 0, 0)
  scroll:SetPoint("BOTTOMRIGHT", 0, 0)
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(_, delta)
    ScrollBy(delta)
  end)
  Menu.scroll = scroll

  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(ROW_W, 1)
  scroll:SetScrollChild(content)
  Menu.content = content

  local empty = body:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  empty:SetPoint("TOPLEFT", 24, -48)
  empty:SetPoint("TOPRIGHT", -24, -48)
  empty:SetJustifyH("CENTER")
  empty:SetJustifyV("TOP")
  empty:SetWordWrap(true)
  empty:SetTextColor(0.8, 0.75, 0.64)
  empty:SetText("No features yet.\n\nEach tool you add shows up here with its own on/off switch and settings.")
  Menu.empty = empty

  local configHost = CreateFrame("Frame", nil, body)
  configHost:SetPoint("TOPLEFT", 0, -30)
  configHost:SetPoint("BOTTOMRIGHT", 0, 0)
  configHost:Hide()
  Menu.configHost = configHost

  local configScroll
  local cfgOk, cfgCreated = pcall(CreateFrame, "ScrollFrame", "ForeverForgeConfigScroll", configHost, "UIPanelScrollFrameTemplate")
  if cfgOk and type(cfgCreated) == "table" then
    configScroll = cfgCreated
  else
    configScroll = CreateFrame("ScrollFrame", nil, configHost)
  end
  configScroll:SetAllPoints()
  configScroll:EnableMouseWheel(true)
  Menu.configScroll = configScroll

  local configChild = CreateFrame("Frame", nil, configScroll)
  configChild:SetSize(ROW_W, 400)
  configScroll:SetScrollChild(configChild)
  Menu.configChild = configChild

  local footer = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  footer:SetPoint("BOTTOM", 0, 12)
  footer:SetWidth(FRAME_W - 24)
  footer:SetJustifyH("CENTER")
  footer:SetWordWrap(false)
  footer:SetTextColor(0.62, 0.56, 0.46)
  Menu.footer = footer

  frame:SetScript("OnShow", function(self)
    self:Raise()
    FTK:InitDB()
    RestorePosition(self)
    Menu.ShowList()
  end)

  Menu.ShowList()
  return frame
end

function FTK:ToggleMenu()
  local frame = Menu.Ensure()
  if frame:IsShown() then
    frame:Hide()
    return
  end
  frame:Show()
end

function FTK:OpenMenu()
  local frame = Menu.Ensure()
  frame:Show()
end

function FTK:CloseMenu()
  if Menu.frame then
    Menu.frame:Hide()
  end
end
