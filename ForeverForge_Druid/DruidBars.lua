--[[
  Druid Bars. A mana bar under the player power bar while in Cat or Bear.
  Caster form and Moonkin already show mana as the main bar, so this stays
  hidden there. Energy and Rage are not drawn. This client does not keep
  those pools readable outside their own form.
]]

local M = {}
_G.ForeverForgeDruid = M

local PAGE_ID = "Druid"
local BAR_H = 6
local BAR_GAP = -1

local FALLBACK_POWER = {
  Energy = 3,
  Rage = 1,
  Mana = 0,
}

local FORM_SPELL = {
  [768] = "cat",
  [5487] = "bear",
  [9634] = "bear",
  [24858] = "moonkin",
  [783] = "travel",
  [1066] = "travel",
  [33943] = "travel",
  [40120] = "travel",
  [33891] = "travel",
}

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

function M.PowerId(name)
  local enum = _G.Enum and _G.Enum.PowerType
  local value = enum and enum[name]
  if type(value) == "number" and not IsSecret(value) then
    return value
  end
  return FALLBACK_POWER[name]
end

function M.ShowMana(form, sample, powerType)
  local feral = form == "cat" or form == "bear"
  if not feral and form == nil then
    feral = powerType == M.PowerId("Energy") or powerType == M.PowerId("Rage")
  end
  if not feral or type(sample) ~= "table" then
    return false
  end
  if sample.curSecret or sample.maxSecret then
    return true
  end
  return type(sample.max) == "number" and sample.max > 0
end

local function SpellName(spellID)
  local id = PlainNumber(spellID)
  if not id then
    return nil
  end
  local spells = _G.C_Spell
  if spells and type(spells.GetSpellName) == "function" then
    local ok, name = pcall(spells.GetSpellName, id)
    if ok and type(name) == "string" and name ~= "" and not IsSecret(name) then
      return name:lower()
    end
  end
  if spells and type(spells.GetSpellInfo) == "function" then
    local ok, info = pcall(spells.GetSpellInfo, id)
    if ok and type(info) == "table" then
      local name = info.name
      if type(name) == "string" and name ~= "" and not IsSecret(name) then
        return name:lower()
      end
    end
  end
  return nil
end

local function FormFromSpell(spellID)
  local id = PlainNumber(spellID)
  if id and FORM_SPELL[id] then
    return FORM_SPELL[id]
  end
  local name = SpellName(spellID)
  if not name then
    return nil
  end
  if name:find("moonkin", 1, true) then
    return "moonkin"
  end
  if name:find("dire bear", 1, true) or name:find("bear form", 1, true) then
    return "bear"
  end
  if name:find("cat form", 1, true) then
    return "cat"
  end
  if name:find("travel form", 1, true) or name:find("aquatic form", 1, true) or name:find("flight form", 1, true) then
    return "travel"
  end
  return nil
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
  local index
  local sawButton = false
  for index = 1, count do
    local infoOk, _, active, _, spellID = pcall(GetShapeshiftFormInfo, index)
    if infoOk then
      if IsSecret(active) then
        return nil
      end
      sawButton = true
      if active == true then
        return FormFromSpell(spellID) or "other"
      end
    end
  end
  if sawButton then
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

local function ReadMana()
  local power = M.PowerId("Mana")
  if type(UnitPower) ~= "function" or type(UnitPowerMax) ~= "function" then
    return nil
  end
  local curOk, cur = pcall(UnitPower, "player", power)
  local maxOk, maxValue = pcall(UnitPowerMax, "player", power)
  if not curOk or not maxOk then
    return nil
  end
  local sample = {
    curSecret = IsSecret(cur),
    maxSecret = IsSecret(maxValue),
    curRaw = cur,
    maxRaw = maxValue,
  }
  if not sample.curSecret then
    sample.cur = PlainNumber(cur)
    if sample.cur == nil then
      return nil
    end
  end
  if not sample.maxSecret then
    sample.max = PlainNumber(maxValue)
    if sample.max == nil then
      return nil
    end
  end
  return sample
end

local function PageConfig()
  local host = _G.ForeverForge
  if not host or type(host.GetPageConfig) ~= "function" then
    return nil
  end
  return host:GetPageConfig(PAGE_ID)
end

function M.BarsEnabled()
  local cfg = PageConfig()
  if type(cfg) ~= "table" then
    return true
  end
  return cfg.showBars ~= false
end

local bar
local driver

local function BarVisible(frame)
  if type(frame) ~= "table" or type(frame.IsVisible) ~= "function" then
    return false
  end
  local ok, shown = pcall(frame.IsVisible, frame)
  return ok and shown == true and not IsSecret(shown)
end

local function AsStatusBar(frame)
  if type(frame) ~= "table" or type(frame.GetObjectType) ~= "function" then
    return nil
  end
  local ok, kind = pcall(frame.GetObjectType, frame)
  if ok and kind == "StatusBar" then
    return frame
  end
  return nil
end

local function FindPowerBar()
  local player = _G.PlayerFrame
  local main = player and player.PlayerFrameContent and player.PlayerFrameContent.PlayerFrameContentMain
  local candidates = {
    AsStatusBar(_G.PlayerFrameManaBar),
    main and main.ManaBarArea and AsStatusBar(main.ManaBarArea.ManaBar) or nil,
    player and AsStatusBar(player.manabar) or nil,
    player and AsStatusBar(player.ManaBar) or nil,
  }
  local index
  local first
  for index = 1, #candidates do
    local candidate = candidates[index]
    if candidate then
      if not first then
        first = candidate
      end
      if BarVisible(candidate) then
        return candidate
      end
    end
  end
  return first
end

local function ManaColor()
  local colors = _G.PowerBarColor
  local named = colors and (colors.MANA or colors.Mana)
  if type(named) == "table" then
    local red = PlainNumber(named.r)
    local green = PlainNumber(named.g)
    local blue = PlainNumber(named.b)
    if red and green and blue then
      return red, green, blue
    end
  end
  return 0, 0.4, 1
end

local function Paint(sample)
  bar.label = "Mana"
  bar.plainCur = sample.curSecret and nil or sample.cur
  bar.plainMax = sample.maxSecret and nil or sample.max
  local red, green, blue = ManaColor()
  return pcall(function()
    bar:SetStatusBarColor(red, green, blue, 1)
    bar:SetMinMaxValues(0, sample.maxRaw)
    bar:SetValue(sample.curRaw)
  end)
end

local function Place(anchor)
  bar:ClearAllPoints()
  bar:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, BAR_GAP)
  bar:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, BAR_GAP)
  bar:SetHeight(BAR_H)
end

function M.Refresh()
  if not bar then
    return
  end
  if not M.BarsEnabled() then
    bar:Hide()
    return
  end
  local anchor = FindPowerBar()
  local sample = ReadMana()
  if not BarVisible(anchor) or not M.ShowMana(ReadForm(), sample, ReadPowerType()) or not Paint(sample) then
    bar:Hide()
    return
  end
  if bar:GetParent() ~= anchor then
    bar:SetParent(anchor)
  end
  local strataOk, strata = pcall(anchor.GetFrameStrata, anchor)
  if strataOk and type(strata) == "string" and not IsSecret(strata) then
    bar:SetFrameStrata(strata)
  end
  local levelOk, level = pcall(anchor.GetFrameLevel, anchor)
  level = levelOk and PlainNumber(level) or nil
  if level then
    bar:SetFrameLevel(level + 2)
  end
  Place(anchor)
  bar:Show()
end

local function ShowTooltip(self)
  local tip = _G.GameTooltip
  if not tip or type(tip.SetOwner) ~= "function" then
    return
  end
  tip:SetOwner(self, "ANCHOR_RIGHT")
  tip:SetText("Mana")
  if type(self.plainCur) == "number" and type(self.plainMax) == "number" and type(tip.AddLine) == "function" then
    tip:AddLine(self.plainCur .. " / " .. self.plainMax, 1, 1, 1)
  end
  tip:Show()
end

local function HideTooltip()
  local tip = _G.GameTooltip
  if tip and type(tip.Hide) == "function" then
    tip:Hide()
  end
end

function M.Start()
  if bar or type(CreateFrame) ~= "function" then
    return
  end
  bar = CreateFrame("StatusBar", "ForeverForgeDruidBar1", UIParent)
  bar:SetHeight(BAR_H)
  bar:Hide()
  bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  bar:EnableMouse(true)
  local bg = bar:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  if bg.SetColorTexture then
    bg:SetColorTexture(0, 0, 0, 0.85)
  end
  bar:SetScript("OnEnter", ShowTooltip)
  bar:SetScript("OnLeave", HideTooltip)

  driver = CreateFrame("Frame")
  local elapsed = 0
  driver:SetScript("OnUpdate", function(_, delta)
    elapsed = elapsed + (PlainNumber(delta) or 0)
    if elapsed < 0.1 then
      return
    end
    elapsed = 0
    pcall(M.Refresh)
  end)
  driver:RegisterEvent("PLAYER_ENTERING_WORLD")
  driver:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
  driver:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
  driver:RegisterEvent("UNIT_DISPLAYPOWER")
  driver:RegisterEvent("UNIT_POWER_UPDATE")
  driver:RegisterEvent("UNIT_MAXPOWER")
  if type(driver.RegisterUnitEvent) == "function" then
    driver:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
  end
  driver:SetScript("OnEvent", function(_, _, unit)
    if type(unit) == "string" and not IsSecret(unit) and unit ~= "player" then
      return
    end
    pcall(M.Refresh)
  end)
  M.Refresh()
end

function M.BuildOptions(_, parent)
  local cfg = PageConfig()
  if type(cfg) ~= "table" then
    return
  end
  local note = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  note:SetPoint("TOPLEFT", 0, -4)
  note:SetWidth(420)
  note:SetJustifyH("LEFT")
  note:SetWordWrap(true)
  note:SetText("Shows your Mana under the power bar while you are in Cat Form or Bear Form.")
  local box = CreateFrame("CheckButton", nil, parent)
  box:SetSize(24, 24)
  box:SetPoint("TOPLEFT", 0, -36)
  box:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
  box:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
  box:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
  box:SetChecked(cfg.showBars ~= false)
  box:SetScript("OnClick", function(self)
    cfg.showBars = self:GetChecked() == true
    M.Refresh()
  end)
  local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  text:SetPoint("LEFT", box, "RIGHT", 4, 0)
  text:SetText("Druid Bars")
  parent:SetHeight(80)
end
