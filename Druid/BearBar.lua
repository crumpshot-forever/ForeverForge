--[[
  Movable Bear bar. While in Bear Form it shows, top to bottom:
  your debuffs on the target, the rage bar, and mana.

  The debuff row matches the Cat bar. It is a Blizzard Aura Container.
  The game paints the icon and the time left. The dark panel starts at
  the rage bar, so an empty debuff row stays clear.
]]

local Bear = {}
_G.ForeverForgeDruidBear = Bear

local PAGE_ID = "Druid"
local WIDTH = 214
local ICON = 28
local ICON_GAP = 3
local AURA_H = 46
local RAGE_H = 16
local MANA_H = 16
local PAD = 3
local BARS_TOP = PAD + AURA_H + 2

local function IsSecret(value)
  if value == nil or type(issecretvalue) ~= "function" then
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

local function PageConfig()
  local host = _G.ForeverForge
  if not host or type(host.GetPageConfig) ~= "function" then
    return nil
  end
  return host:GetPageConfig(PAGE_ID)
end

function Bear.Enabled()
  local cfg = PageConfig()
  if type(cfg) ~= "table" then
    return true
  end
  return cfg.bearBarOn ~= false
end

function Bear.Locked()
  local cfg = PageConfig()
  return type(cfg) == "table" and cfg.bearBarLocked == true
end

local function PowerId(name, fallback)
  local enum = _G.Enum and _G.Enum.PowerType
  local value = enum and enum[name]
  if type(value) == "number" and not IsSecret(value) then
    return value
  end
  return fallback
end

local function ReadForm()
  if type(GetNumShapeshiftForms) ~= "function" or type(GetShapeshiftFormInfo) ~= "function" then
    return nil
  end
  local countOk, count = pcall(GetNumShapeshiftForms)
  count = countOk and PlainNumber(count) or nil
  if not count or count < 1 then
    return nil
  end
  local button = false
  local formIndex
  for formIndex = 1, count do
    local infoOk, _, active, _, spellID = pcall(GetShapeshiftFormInfo, formIndex)
    if infoOk then
      if IsSecret(active) then
        return nil
      end
      button = true
      if active == true then
        local id = PlainNumber(spellID)
        if id == 768 then
          return "cat"
        end
        if id == 5487 or id == 9634 then
          return "bear"
        end
        local spells = _G.C_Spell
        local name
        if id and spells and type(spells.GetSpellName) == "function" then
          local nameOk, result = pcall(spells.GetSpellName, id)
          name = nameOk and PlainString(result) or nil
        end
        if name then
          local lower = name:lower()
          if lower:find("cat form", 1, true) then
            return "cat"
          end
          if lower:find("bear form", 1, true) then
            return "bear"
          end
        end
        return "other"
      end
    end
  end
  if button then
    return "caster"
  end
  return nil
end

local function ReadPowerType()
  if type(UnitPowerType) ~= "function" then
    return nil
  end
  local ok, power = pcall(UnitPowerType, "player")
  if not ok then
    return nil
  end
  return PlainNumber(power)
end

function Bear.InBear()
  local form = ReadForm()
  if form == "bear" then
    return true
  end
  if form == nil then
    return ReadPowerType() == PowerId("Rage", 1)
  end
  return false
end

function Bear.IsCoveringMana()
  return Bear.Enabled() and Bear.InBear()
end

local function PrepareAuraButton(button)
  button:SetSize(ICON, ICON)
  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetAllPoints(button)
  if button.SetIcon then
    button:SetIcon(icon)
  end
  local swipeOk, swipe = pcall(CreateFrame, "Cooldown", nil, button, "CooldownFrameTemplate")
  if not swipeOk then
    swipe = CreateFrame("Cooldown", nil, button)
  end
  swipe:SetAllPoints(button)
  if swipe.SetHideCountdownNumbers then
    swipe:SetHideCountdownNumbers(true)
  end
  if button.SetDurationCooldown then
    button:SetDurationCooldown(swipe)
  end
  local duration = button:CreateFontString(nil, "OVERLAY")
  duration:SetPoint("TOP", button, "BOTTOM", 0, -1)
  duration:SetJustifyH("CENTER")
  if not pcall(duration.SetFont, duration, "Fonts\\FRIZQT__.TTF", 10, "OUTLINE") then
    pcall(duration.SetFontObject, duration, "GameFontHighlightSmall")
  end
  duration:SetTextColor(1, 0.95, 0.8, 1)
  if button.SetDurationText then
    button:SetDurationText(duration)
  end
  local count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
  count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
  if button.SetApplicationCount then
    button:SetApplicationCount(count)
  end
end

local function CreateAuraRow(parent)
  local ok, container = pcall(CreateFrame, "AuraContainer", "ForeverForgeBearAuras", parent, "CustomAuraContainerTemplate")
  if not ok or type(container) ~= "table" then
    return nil
  end
  container:SetSize(WIDTH - PAD * 2, AURA_H)
  container:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, -PAD)
  if container.EnableMouse then
    container:EnableMouse(false)
  end
  if container.SetBackdrop then
    pcall(container.SetBackdrop, container, nil)
  end
  if container.SetUnit then
    pcall(container.SetUnit, container, "target")
  end
  local options = {
    maxFrameCount = 6,
    layout = {
      elementSpacing = ICON_GAP,
      elementWidth = ICON,
      elementHeight = ICON,
    },
    initializeFrame = PrepareAuraButton,
  }
  if _G.AuraContainerSortMethod and _G.AuraContainerSortDirection then
    options.sortMethod = _G.AuraContainerSortMethod.Expiration
    options.sortDirection = _G.AuraContainerSortDirection.Normal
  end
  if container.AddAuraGroup then
    local added = pcall(container.AddAuraGroup, container, "debuffs", "HARMFUL|PLAYER", options)
    if not added then
      pcall(container.AddAuraGroup, container, "debuffs", "HARMFUL", options)
    end
  end
  return container
end

local function RefreshAuras(container)
  if container and container.UpdateAllAuras then
    pcall(container.UpdateAllAuras, container)
  end
end

local frame
local auras
local rageBar
local manaBar
local aurasReady = false

local function PaintPower(bar, powerName, fallback, color)
  if type(UnitPower) ~= "function" or type(UnitPowerMax) ~= "function" then
    return
  end
  local power = PowerId(powerName, fallback)
  local curOk, current = pcall(UnitPower, "player", power)
  local maxOk, maximum = pcall(UnitPowerMax, "player", power)
  if not curOk or not maxOk then
    return
  end
  local maxNumber = PlainNumber(maximum)
  local paintedMax = maximum
  if maxNumber ~= nil and maxNumber <= 0 then
    paintedMax = 1
  end
  pcall(bar.SetStatusBarColor, bar, color[1], color[2], color[3], 1)
  pcall(function()
    bar:SetMinMaxValues(0, paintedMax)
    bar:SetValue(current)
  end)
  if bar.valueText then
    local text = bar.valueText
    if IsSecret(current) then
      local shown = pcall(text.SetText, text, current)
      if not shown then
        text:SetText("")
      end
    else
      local currentNumber = PlainNumber(current)
      if currentNumber == nil then
        text:SetText("")
      else
        local whole = math.floor(currentNumber + 0.5)
        if whole < 0 then
          whole = 0
        end
        text:SetText(tostring(whole))
      end
    end
  end
end

local function PlaceRow(widget, y, height)
  widget:ClearAllPoints()
  widget:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
  widget:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -y)
  widget:SetHeight(height)
end

local function SavePosition()
  local cfg = PageConfig()
  if type(cfg) ~= "table" or not frame then
    return
  end
  local ok, point, _, relPoint, x, y = pcall(frame.GetPoint, frame, 1)
  if not ok or type(point) ~= "string" or type(x) ~= "number" or type(y) ~= "number" then
    return
  end
  cfg.bearBarPos = {
    point = point,
    relPoint = type(relPoint) == "string" and relPoint or point,
    x = x,
    y = y,
  }
end

local function RestorePosition()
  local cfg = PageConfig()
  local pos = cfg and cfg.bearBarPos
  local function placeDefault()
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 220, -40)
  end
  if type(pos) ~= "table" or type(pos.point) ~= "string" or type(pos.x) ~= "number" or type(pos.y) ~= "number" then
    placeDefault()
    return
  end
  local ok = pcall(function()
    frame:ClearAllPoints()
    frame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x, pos.y)
  end)
  if not ok then
    placeDefault()
  end
end

function Bear.Refresh()
  if not frame then
    return
  end
  if not Bear.Enabled() or not Bear.InBear() then
    frame:Hide()
    aurasReady = false
    return
  end
  if not aurasReady then
    RefreshAuras(auras)
    aurasReady = true
  end
  local y = BARS_TOP
  PlaceRow(rageBar, y, RAGE_H)
  PaintPower(rageBar, "Rage", 1, { 0.9, 0.12, 0.12 })
  y = y + RAGE_H + 2
  PlaceRow(manaBar, y, MANA_H)
  PaintPower(manaBar, "Mana", 0, { 0.15, 0.45, 1 })
  y = y + MANA_H + PAD
  frame:SetHeight(y)
  frame:Show()
end

local function MakeStatus(parent, name)
  local bar = CreateFrame("StatusBar", name, parent)
  bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  local bg = bar:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  if bg.SetColorTexture then
    bg:SetColorTexture(0, 0, 0, 0.9)
  end
  bar:EnableMouse(false)
  return bar
end

local function AddCenterValue(bar)
  local holder = CreateFrame("Frame", nil, bar)
  holder:SetAllPoints(bar)
  holder:EnableMouse(false)
  local levelOk, level = pcall(bar.GetFrameLevel, bar)
  level = levelOk and PlainNumber(level) or nil
  if level then
    holder:SetFrameLevel(level + 5)
  end
  local text = holder:CreateFontString(nil, "OVERLAY")
  text:SetPoint("CENTER", holder, "CENTER", 0, 0)
  text:SetJustifyH("CENTER")
  text:SetJustifyV("MIDDLE")
  if not pcall(text.SetFont, text, "Fonts\\FRIZQT__.TTF", 12, "OUTLINE") then
    pcall(text.SetFontObject, text, "GameFontHighlightSmall")
  end
  text:SetTextColor(1, 1, 1, 1)
  bar.valueText = text
end

function Bear.Start()
  if frame or type(CreateFrame) ~= "function" then
    return
  end
  frame = CreateFrame("Frame", "ForeverForgeBearBar", UIParent)
  frame:SetSize(WIDTH, 70)
  frame:SetFrameStrata("MEDIUM")
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self)
    if Bear.Locked() then
      return
    end
    local inCombat = false
    if type(InCombatLockdown) == "function" then
      local ok, value = pcall(InCombatLockdown)
      inCombat = ok and value == true
    end
    if inCombat then
      return
    end
    self:StartMoving()
  end)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    SavePosition()
  end)
  local bg = frame:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -BARS_TOP)
  bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
  if bg.SetColorTexture then
    bg:SetColorTexture(0.04, 0.03, 0.02, 0.88)
  end

  auras = CreateAuraRow(frame)
  rageBar = MakeStatus(frame, "ForeverForgeBearRage")
  manaBar = MakeStatus(frame, "ForeverForgeBearMana")
  AddCenterValue(rageBar)
  AddCenterValue(manaBar)
  RestorePosition()
  Bear.ApplyLock()

  local driver = CreateFrame("Frame")
  local elapsed = 0
  driver:SetScript("OnUpdate", function(_, delta)
    elapsed = elapsed + (PlainNumber(delta) or 0)
    if elapsed < 0.1 then
      return
    end
    elapsed = 0
    pcall(Bear.Refresh)
  end)
  driver:RegisterEvent("PLAYER_ENTERING_WORLD")
  driver:RegisterEvent("PLAYER_TARGET_CHANGED")
  driver:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
  driver:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
  driver:RegisterEvent("UNIT_POWER_UPDATE")
  driver:RegisterEvent("UNIT_POWER_FREQUENT")
  driver:RegisterEvent("UNIT_MAXPOWER")
  driver:RegisterEvent("UNIT_AURA")
  driver:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_TARGET_CHANGED" or event == "UNIT_AURA" or event == "UPDATE_SHAPESHIFT_FORM" or event == "UPDATE_SHAPESHIFT_FORMS" then
      aurasReady = false
      RefreshAuras(auras)
    end
    if type(unit) == "string" and not IsSecret(unit) and unit ~= "player" and unit ~= "target" then
      return
    end
    pcall(Bear.Refresh)
  end)
  Bear.Refresh()
end

function Bear.BuildOptions(_, parent)
  local cfg = PageConfig()
  if type(cfg) ~= "table" then
    return
  end
  local y = -8
  if parent.GetHeight then
    local ok, height = pcall(parent.GetHeight, parent)
    height = ok and PlainNumber(height) or nil
    if height and height > 20 then
      y = -(height + 12)
    end
  end
  local note = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  note:SetPoint("TOPLEFT", 0, y)
  note:SetWidth(420)
  note:SetJustifyH("LEFT")
  note:SetWordWrap(true)
  note:SetText("Bear Bar is a panel for Bear Form. Debuffs you cast sit on top, with the time left drawn by the game, then rage and mana. Drag it to move it, then lock it so it stays put.")
  local box = CreateFrame("CheckButton", nil, parent)
  box:SetSize(24, 24)
  box:SetPoint("TOPLEFT", 0, y - 48)
  box:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
  box:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
  box:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
  box:SetChecked(cfg.bearBarOn ~= false)
  box:SetScript("OnClick", function(self)
    cfg.bearBarOn = self:GetChecked() == true
    Bear.Refresh()
    local bars = _G.ForeverForgeDruid
    if bars and type(bars.Refresh) == "function" then
      bars.Refresh()
    end
  end)
  local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  text:SetPoint("LEFT", box, "RIGHT", 4, 0)
  text:SetText("Bear Bar")
  local lock = CreateFrame("CheckButton", nil, parent)
  lock:SetSize(24, 24)
  lock:SetPoint("TOPLEFT", 0, y - 76)
  lock:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
  lock:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
  lock:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
  lock:SetChecked(cfg.bearBarLocked == true)
  lock:SetScript("OnClick", function(self)
    cfg.bearBarLocked = self:GetChecked() == true
    if frame and cfg.bearBarLocked then
      pcall(frame.StopMovingOrSizing, frame)
    end
    Bear.ApplyLock()
  end)
  local lockText = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  lockText:SetPoint("LEFT", lock, "RIGHT", 4, 0)
  lockText:SetText("Lock position")
  parent:SetHeight(-y + 108)
end

function Bear.ApplyLock()
  if not frame then
    return
  end
  local locked = Bear.Locked()
  frame:SetMovable(not locked)
  frame:EnableMouse(not locked)
end
