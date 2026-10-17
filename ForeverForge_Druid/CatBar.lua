--[[
  Movable Cat bar. While in Cat Form it shows, top to bottom:
  bleed icons with a remaining-seconds timer, the energy bar, combo
  points, and mana.

  Target aura timers are often unreadable in combat on this client.
  NAG's CastLedger is the pattern that still works: remember when the
  player's bleed landed, and count down from that spell's duration.
  A plain aura expiration from the game wins when the client provides one.
]]

local Cat = {}
_G.ForeverForgeDruidCat = Cat

local PAGE_ID = "Druid"
local WIDTH = 214
local ICON = 28
local ICON_GAP = 3
local ENERGY_H = 12
local COMBO_H = 9
local MANA_H = 14
local PAD = 3

-- Durations are the Camelot spell facts NAG ships: Rake 9s, Rip 12s.
-- Faerie Fire is the classic 40s armor debuff.
local DOTS = {
  {
    key = "rake",
    name = "Rake",
    spell = 1822,
    duration = 9,
    icon = "Interface\\Icons\\Ability_Druid_Disembowel",
    ids = { 1822, 1823, 1824, 9904, 27003, 48573, 48574 },
  },
  {
    key = "rip",
    name = "Rip",
    spell = 1079,
    duration = 12,
    icon = "Interface\\Icons\\Ability_GhoulFrenzy",
    ids = { 1079, 9492, 9493, 9752, 9894, 9896, 27008, 49799, 49800 },
  },
  {
    key = "faerie",
    name = "Faerie Fire",
    spell = 770,
    duration = 40,
    icon = "Interface\\Icons\\Spell_Nature_FaerieFire",
    ids = { 770, 778, 9749, 9907, 26993, 16857, 17390, 17391, 17392, 27011, 48475 },
  },
}

local DOT_BY_ID = {}
local DOT_BY_NAME = {}
local index
for index = 1, #DOTS do
  local dot = DOTS[index]
  DOT_BY_NAME[dot.name:lower()] = dot
  local idIndex
  for idIndex = 1, #dot.ids do
    DOT_BY_ID[dot.ids[idIndex]] = dot
  end
end

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

function Cat.DotForSpell(spellId, spellName)
  local id = PlainNumber(spellId)
  if id and DOT_BY_ID[id] then
    return DOT_BY_ID[id]
  end
  local name = PlainString(spellName)
  if name then
    return DOT_BY_NAME[name:lower()]
  end
  return nil
end

function Cat.Remaining(now, auraSeconds, ledgerExpires)
  if type(now) ~= "number" then
    return nil
  end
  if type(auraSeconds) == "number" and auraSeconds > 0 then
    return auraSeconds
  end
  if type(ledgerExpires) == "number" then
    local left = ledgerExpires - now
    if left > 0 then
      return left
    end
  end
  return nil
end

function Cat.TimerText(seconds)
  if type(seconds) ~= "number" or seconds <= 0 then
    return ""
  end
  local whole = math.ceil(seconds - 0.001)
  if whole < 1 then
    whole = 1
  end
  return tostring(whole)
end

function Cat.VisibleDots(now, auraByKey, ledgerRow)
  local shown = {}
  local dotIndex
  for dotIndex = 1, #DOTS do
    local dot = DOTS[dotIndex]
    local aura = auraByKey and auraByKey[dot.key] or nil
    local expires = ledgerRow and ledgerRow[dot.key] or nil
    local left = Cat.Remaining(now, aura, expires)
    if left then
      shown[#shown + 1] = {
        key = dot.key,
        spell = dot.spell,
        icon = dot.icon,
        seconds = left,
        text = Cat.TimerText(left),
      }
    end
  end
  return shown
end

local function PageConfig()
  local host = _G.ForeverForge
  if not host or type(host.GetPageConfig) ~= "function" then
    return nil
  end
  return host:GetPageConfig(PAGE_ID)
end

function Cat.Enabled()
  local cfg = PageConfig()
  if type(cfg) ~= "table" then
    return true
  end
  return cfg.catBarOn ~= false
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

function Cat.InCat()
  local form = ReadForm()
  if form == "cat" then
    return true
  end
  if form == nil then
    return ReadPowerType() == PowerId("Energy", 3)
  end
  return false
end

function Cat.IsCoveringMana()
  return Cat.Enabled() and Cat.InCat()
end

local ledger = {}

local function Now()
  if type(GetTime) ~= "function" then
    return nil
  end
  local ok, value = pcall(GetTime)
  if not ok then
    return nil
  end
  return PlainNumber(value)
end

local function TargetGuid()
  if type(UnitGUID) ~= "function" then
    return nil
  end
  local ok, guid = pcall(UnitGUID, "target")
  if not ok then
    return nil
  end
  return PlainString(guid)
end

local function NoteBleed(guid, dot, now, duration)
  guid = PlainString(guid)
  if not guid or not dot or type(now) ~= "number" then
    return
  end
  local seconds = PlainNumber(duration)
  if not seconds or seconds <= 0 then
    seconds = dot.duration
  end
  ledger[guid] = ledger[guid] or {}
  ledger[guid][dot.key] = now + seconds
end

local function ClearBleed(guid, dot)
  guid = PlainString(guid)
  if not guid or not dot or not ledger[guid] then
    return
  end
  ledger[guid][dot.key] = nil
end

local function Field(data, key)
  if type(data) ~= "table" or IsSecret(data) then
    return nil
  end
  if type(issecrettable) == "function" then
    local secretOk, secret = pcall(issecrettable, data)
    if secretOk and secret == true then
      return nil
    end
  end
  if type(canaccesstable) == "function" then
    local accessOk, access = pcall(canaccesstable, data)
    if accessOk and access == false then
      return nil
    end
  end
  local ok, value = pcall(function()
    return data[key]
  end)
  if not ok then
    return nil
  end
  return value
end

local function AuraSeconds(dot)
  local auras = _G.C_UnitAuras
  if not auras then
    return nil
  end
  local filters = { "HARMFUL|PLAYER", "HARMFUL" }
  local filterIndex
  for filterIndex = 1, #filters do
    local data
    if type(auras.GetAuraDataBySpellName) == "function" then
      local ok, result = pcall(auras.GetAuraDataBySpellName, "target", dot.name, filters[filterIndex])
      if ok then
        data = result
      end
    end
    if type(data) ~= "table" and type(auras.GetUnitAuraBySpellID) == "function" then
      local idIndex
      for idIndex = 1, #dot.ids do
        local ok, result = pcall(auras.GetUnitAuraBySpellID, "target", dot.ids[idIndex])
        if ok and type(result) == "table" then
          data = result
          break
        end
      end
    end
    if type(data) == "table" then
      local expires = Field(data, "expirationTime")
      local duration = Field(data, "duration")
      local now = Now()
      local expiresN = PlainNumber(expires)
      if expiresN and now then
        local left = expiresN - now
        if left > 0 then
          return left, PlainNumber(duration)
        end
      end
      if IsSecret(expires) then
        return nil, PlainNumber(duration)
      end
    end
  end
  return nil, nil
end

local function AuraSnapshot()
  local snapshot = {}
  local dotIndex
  for dotIndex = 1, #DOTS do
    local dot = DOTS[dotIndex]
    local left = AuraSeconds(dot)
    if type(left) == "number" then
      snapshot[dot.key] = left
    end
  end
  return snapshot
end

local function OnCombatLog()
  if type(CombatLogGetCurrentEventInfo) ~= "function" then
    return
  end
  local ok, timestamp, subevent, _, sourceGUID, _, _, _, destGUID, _, _, _, spellId, spellName = pcall(CombatLogGetCurrentEventInfo)
  if not ok then
    return
  end
  subevent = PlainString(subevent)
  if subevent ~= "SPELL_AURA_APPLIED" and subevent ~= "SPELL_AURA_REFRESH" and subevent ~= "SPELL_AURA_REMOVED" then
    return
  end
  local playerOk, playerGUID = pcall(UnitGUID, "player")
  if not playerOk or not PlainString(sourceGUID) or PlainString(sourceGUID) ~= PlainString(playerGUID) then
    return
  end
  local dot = Cat.DotForSpell(spellId, spellName)
  if not dot then
    return
  end
  if subevent == "SPELL_AURA_REMOVED" then
    ClearBleed(destGUID, dot)
    return
  end
  local now = PlainNumber(timestamp) or Now()
  if not now then
    return
  end
  local _, duration = AuraSeconds(dot)
  NoteBleed(destGUID, dot, now, duration)
end

local frame
local iconFrames = {}
local energyBar
local comboSlots = {}
local manaBar

local function MacroCombo()
  if type(SecureCmdOptionParse) ~= "function" then
    return nil
  end
  local function yes(points)
    local ok, result = pcall(SecureCmdOptionParse, "[combopoints:" .. points .. "]yes;no")
    result = ok and PlainString(result) or nil
    if result == "yes" then
      return true
    end
    if result == "no" then
      return false
    end
    return nil
  end
  if yes(9) == true or yes(6) == true then
    return nil
  end
  local points
  for points = 5, 1, -1 do
    local hit = yes(points)
    if hit == true then
      if points == 5 or yes(points + 1) == false then
        return points
      end
      return nil
    end
    if hit == nil then
      return nil
    end
  end
  if yes(1) == false then
    return 0
  end
  return nil
end

local function WidgetShown(widget)
  if type(widget) ~= "table" or type(widget.IsShown) ~= "function" then
    return nil
  end
  local ok, shown = pcall(widget.IsShown, widget)
  if not ok or IsSecret(shown) then
    return nil
  end
  return shown == true
end

local function RegionBright(texture)
  if type(texture) ~= "table" or type(texture.GetVertexColor) ~= "function" then
    return nil
  end
  local ok, red, green, blue = pcall(texture.GetVertexColor, texture)
  if not ok then
    return nil
  end
  red = PlainNumber(red)
  if not red then
    return nil
  end
  green = PlainNumber(green) or 0
  blue = PlainNumber(blue) or 0
  local bright = red
  if green > bright then
    bright = green
  end
  if blue > bright then
    bright = blue
  end
  return bright
end

local function SlotFilled(slot)
  if WidgetShown(slot) ~= true then
    return false
  end
  local highlight = slot.Highlight or slot.highlight
  if WidgetShown(highlight) == true then
    local bright = RegionBright(highlight)
    if bright == nil or bright >= 0.75 then
      return true
    end
  end
  return false
end

local function ComboFromGems()
  local charged = 0
  local seen = 0
  local point
  for point = 1, 5 do
    local slot = _G["ComboPoint" .. point]
    if slot then
      seen = seen + 1
      if SlotFilled(slot) then
        charged = charged + 1
      end
    end
  end
  if seen < 3 then
    return nil
  end
  return charged
end

local function ComboCount()
  local fromMacro = MacroCombo()
  if fromMacro ~= nil then
    return fromMacro
  end
  local last = _G.ComboFrame and PlainNumber(_G.ComboFrame.lastPoints)
  if last and last >= 0 and last <= 5 then
    return last
  end
  local gems = ComboFromGems()
  if gems ~= nil then
    return gems
  end
  if type(GetComboPoints) == "function" then
    local ok, points = pcall(GetComboPoints, "player", "target")
    points = ok and PlainNumber(points) or nil
    if points and points > 0 then
      return points
    end
  end
  if type(UnitPower) == "function" then
    local ok, points = pcall(UnitPower, "player", PowerId("ComboPoints", 4))
    points = ok and PlainNumber(points) or nil
    if points and points > 0 then
      return points
    end
  end
  return 0
end

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
    local currentNumber = PlainNumber(current)
    if currentNumber == nil then
      bar.valueText:SetText("")
    else
      local whole = math.floor(currentNumber + 0.5)
      if whole < 0 then
        whole = 0
      end
      bar.valueText:SetText(tostring(whole))
    end
  end
end

local function ApplyIcon(icon, row)
  icon:Show()
  local texture = icon.texture
  if texture and texture.SetTexture then
    local spells = _G.C_Spell
    local iconId
    if spells and type(spells.GetSpellTexture) == "function" then
      local ok, result = pcall(spells.GetSpellTexture, row.spell)
      if ok and PlainNumber(result) then
        iconId = result
      end
    end
    pcall(texture.SetTexture, texture, iconId or row.icon)
  end
  if icon.timer then
    icon.timer:SetText(row.text)
  end
end

local function LayoutDots(shown)
  local count = #shown
  local rowWidth = 0
  if count > 0 then
    rowWidth = count * ICON + (count - 1) * ICON_GAP
  end
  local left = (WIDTH - rowWidth) / 2
  local iconIndex
  for iconIndex = 1, #iconFrames do
    local icon = iconFrames[iconIndex]
    local row = shown[iconIndex]
    if row then
      icon:ClearAllPoints()
      icon:SetPoint("TOPLEFT", frame, "TOPLEFT", left + (iconIndex - 1) * (ICON + ICON_GAP), -PAD)
      ApplyIcon(icon, row)
    else
      icon:Hide()
    end
  end
  return count > 0 and (PAD + ICON) or 0
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
  cfg.catBarPos = {
    point = point,
    relPoint = type(relPoint) == "string" and relPoint or point,
    x = x,
    y = y,
  }
end

local function RestorePosition()
  local cfg = PageConfig()
  local pos = cfg and cfg.catBarPos
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

function Cat.Refresh()
  if not frame then
    return
  end
  if not Cat.Enabled() or not Cat.InCat() then
    frame:Hide()
    return
  end
  local now = Now() or 0
  local guid = TargetGuid()
  local aura = AuraSnapshot()
  if guid then
    ledger[guid] = ledger[guid] or {}
    local dotIndex
    for dotIndex = 1, #DOTS do
      local left = aura[DOTS[dotIndex].key]
      if type(left) == "number" and left > 0 then
        ledger[guid][DOTS[dotIndex].key] = now + left
      end
    end
  end
  local shown = Cat.VisibleDots(now, aura, guid and ledger[guid] or nil)
  local y = PAD
  local dotsHeight = LayoutDots(shown)
  if dotsHeight > 0 then
    y = y + dotsHeight + 2
  end
  PlaceRow(energyBar, y, ENERGY_H)
  PaintPower(energyBar, "Energy", 3, { 1, 0.82, 0.15 })
  y = y + ENERGY_H + 2
  local points = ComboCount()
  if points > 5 then
    points = 5
  end
  if points < 0 then
    points = 0
  end
  local slot
  for slot = 1, 5 do
    local pip = comboSlots[slot]
    pip:ClearAllPoints()
    local gap = 2
    local pipWidth = (WIDTH - PAD * 2 - gap * 4) / 5
    pip:SetSize(pipWidth, COMBO_H)
    pip:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + (slot - 1) * (pipWidth + gap), -y)
    local filled = slot <= points
    if pip.SetColorTexture then
      if filled then
        pip:SetColorTexture(0.95, 0.45, 0.08, 1)
      else
        pip:SetColorTexture(0.12, 0.1, 0.08, 1)
      end
    end
    pip:Show()
  end
  y = y + COMBO_H + 2
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

function Cat.Start()
  if frame or type(CreateFrame) ~= "function" then
    return
  end
  frame = CreateFrame("Frame", "ForeverForgeCatBar", UIParent)
  frame:SetSize(WIDTH, 80)
  frame:SetFrameStrata("MEDIUM")
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self)
    local locked = false
    if type(InCombatLockdown) == "function" then
      local ok, value = pcall(InCombatLockdown)
      locked = ok and value == true
    end
    if locked then
      return
    end
    self:StartMoving()
  end)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    SavePosition()
  end)
  local bg = frame:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  if bg.SetColorTexture then
    bg:SetColorTexture(0.04, 0.03, 0.02, 0.88)
  end

  local iconIndex
  for iconIndex = 1, #DOTS do
    local icon = CreateFrame("Frame", nil, frame)
    icon:SetSize(ICON, ICON)
    icon:EnableMouse(false)
    local texture = icon:CreateTexture(nil, "ARTWORK")
    texture:SetAllPoints()
    icon.texture = texture
    local timer = icon:CreateFontString(nil, "OVERLAY")
    timer:SetPoint("BOTTOM", icon, "BOTTOM", 0, 1)
    timer:SetJustifyH("CENTER")
    if not pcall(timer.SetFont, timer, "Fonts\\FRIZQT__.TTF", 11, "OUTLINE") then
      pcall(timer.SetFontObject, timer, "GameFontHighlightSmall")
    end
    timer:SetTextColor(1, 0.95, 0.8, 1)
    icon.timer = timer
    icon:Hide()
    iconFrames[iconIndex] = icon
  end

  energyBar = MakeStatus(frame, "ForeverForgeCatEnergy")
  manaBar = MakeStatus(frame, "ForeverForgeCatMana")
  local manaText = manaBar:CreateFontString(nil, "OVERLAY")
  manaText:SetPoint("CENTER", manaBar, "CENTER", 0, 0)
  if not pcall(manaText.SetFont, manaText, "Fonts\\FRIZQT__.TTF", 10, "OUTLINE") then
    pcall(manaText.SetFontObject, manaText, "GameFontHighlightSmall")
  end
  manaText:SetTextColor(1, 1, 1, 1)
  manaBar.valueText = manaText

  local slot
  for slot = 1, 5 do
    local pip = frame:CreateTexture(nil, "ARTWORK")
    comboSlots[slot] = pip
  end

  RestorePosition()

  local driver = CreateFrame("Frame")
  local elapsed = 0
  driver:SetScript("OnUpdate", function(_, delta)
    elapsed = elapsed + (PlainNumber(delta) or 0)
    if elapsed < 0.1 then
      return
    end
    elapsed = 0
    pcall(Cat.Refresh)
  end)
  driver:RegisterEvent("PLAYER_ENTERING_WORLD")
  driver:RegisterEvent("PLAYER_TARGET_CHANGED")
  driver:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
  driver:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
  driver:RegisterEvent("UNIT_POWER_UPDATE")
  driver:RegisterEvent("UNIT_POWER_FREQUENT")
  driver:RegisterEvent("UNIT_MAXPOWER")
  driver:RegisterEvent("UNIT_AURA")
  driver:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
  driver:SetScript("OnEvent", function(_, event, unit)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
      OnCombatLog()
      pcall(Cat.Refresh)
      return
    end
    if type(unit) == "string" and not IsSecret(unit) and unit ~= "player" and unit ~= "target" then
      return
    end
    pcall(Cat.Refresh)
  end)
  Cat.Refresh()
end

function Cat.BuildOptions(_, parent)
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
  note:SetText("Cat Bar is a movable panel for Cat Form. It shows Rake, Rip, and Faerie Fire with a timer, then energy, combo points, and mana. Drag the panel to move it.")
  local box = CreateFrame("CheckButton", nil, parent)
  box:SetSize(24, 24)
  box:SetPoint("TOPLEFT", 0, y - 48)
  box:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
  box:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
  box:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
  box:SetChecked(cfg.catBarOn ~= false)
  box:SetScript("OnClick", function(self)
    cfg.catBarOn = self:GetChecked() == true
    Cat.Refresh()
    local bars = _G.ForeverForgeDruid
    if bars and type(bars.Refresh) == "function" then
      bars.Refresh()
    end
  end)
  local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  text:SetPoint("LEFT", box, "RIGHT", 4, 0)
  text:SetText("Cat Bar")
  parent:SetHeight(-y + 80)
end
