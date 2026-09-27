--[[
  Click Heal. Casts heals from the normal party and raid frames.
  Modified clicks cast. Left and right click stay with the game unless the
  toolkit page turns that on.

  Each overlay is our own secure button. Blizzard's frames are only read.
  Spells are armed out of combat, so they keep working during a fight.
  This client hides friendly health from addons, so there is no separate
  health panel. Nameplate settings, the combat log, and soft targets are
  not used.
]]

local FTK = ForeverToolkit
if not FTK then
  error("ForeverToolkit: Core.lua must load before Modules/ClickHeal.lua")
end

local MODULE_ID = "ClickHeal"

local HEALERS = {
  PRIEST = true,
  DRUID = true,
  PALADIN = true,
  SHAMAN = true,
}

local DEFAULTS = {
  PRIEST = {
    left = { "Flash Heal", "Lesser Heal" },
    right = { "Renew" },
    middle = { "Power Word: Shield" },
    shiftleft = { "Greater Heal", "Heal" },
    shiftright = { "Dispel Magic" },
    ctrlleft = { "Lesser Heal", "Heal" },
    ctrlright = { "Cure Disease", "Abolish Disease" },
    altleft = { "Resurrection" },
  },
  DRUID = {
    left = { "Healing Touch" },
    right = { "Rejuvenation" },
    middle = { "Regrowth" },
    shiftleft = { "Regrowth" },
    shiftright = { "Remove Curse" },
    ctrlright = { "Abolish Poison", "Cure Poison" },
    altleft = { "Rebirth", "Revive" },
  },
  PALADIN = {
    left = { "Flash of Light" },
    right = { "Holy Light" },
    middle = { "Blessing of Protection" },
    shiftright = { "Cleanse", "Purify" },
    altleft = { "Redemption" },
  },
  SHAMAN = {
    left = { "Lesser Healing Wave", "Healing Wave" },
    right = { "Healing Wave" },
    middle = { "Chain Heal" },
    shiftright = { "Cure Poison" },
    ctrlright = { "Cure Disease" },
    altleft = { "Ancestral Spirit" },
  },
}

local BINDS = {
  { key = "left", label = "Left", button = "left", type = "type1", spell = "spell1" },
  { key = "right", label = "Right", button = "right", type = "type2", spell = "spell2" },
  { key = "middle", label = "Middle", button = "middle", type = "type3", spell = "spell3" },
  { key = "shiftleft", label = "Shift-Left", button = "left", type = "shift-type1", spell = "shift-spell1" },
  { key = "shiftright", label = "Shift-Right", button = "right", type = "shift-type2", spell = "shift-spell2" },
  { key = "ctrlleft", label = "Ctrl-Left", button = "left", type = "ctrl-type1", spell = "ctrl-spell1" },
  { key = "ctrlright", label = "Ctrl-Right", button = "right", type = "ctrl-type2", spell = "ctrl-spell2" },
  { key = "altleft", label = "Alt-Left", button = "left", type = "alt-type1", spell = "alt-spell1" },
  { key = "altright", label = "Alt-Right", button = "right", type = "alt-type2", spell = "alt-spell2" },
}

local CLICK = {
  left = "LeftButtonDown",
  right = "RightButtonDown",
  middle = "MiddleButtonDown",
}

local NAMED_FRAMES = {
  "PartyMemberFrame1",
  "PartyMemberFrame2",
  "PartyMemberFrame3",
  "PartyMemberFrame4",
  "CompactPartyFrameMember1",
  "CompactPartyFrameMember2",
  "CompactPartyFrameMember3",
  "CompactPartyFrameMember4",
  "CompactPartyFrameMember5",
}

local CONTAINERS = {
  "PartyFrame",
  "CompactPartyFrame",
  "CompactRaidFrameContainer",
}

local resolved = {}
local overlays = {}
local watched = {}
local overlayCount = 0
local pending = false
local saidClass = false
local statusText = {}

local events = CreateFrame("Frame")
local pollWait = 0

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

local function InCombat()
  if not InCombatLockdown then
    return false
  end
  local ok, value = pcall(InCombatLockdown)
  if not ok or IsSecret(value) then
    return true
  end
  return value == true
end

local function PlayerClass()
  if not UnitClass then
    return nil
  end
  local ok, _, classFile = pcall(UnitClass, "player")
  if not ok then
    return nil
  end
  return PlainString(classFile)
end

local function PlayerLevel()
  if not UnitLevel then
    return nil
  end
  local ok, level = pcall(UnitLevel, "player")
  if not ok then
    return nil
  end
  return PlainNumber(level)
end

local function Config()
  local cfg = FTK:GetConfig(MODULE_ID)
  if type(cfg.binds) ~= "table" then
    cfg.binds = {}
  end
  if cfg.takeLeft == nil then
    cfg.takeLeft = false
  end
  if cfg.takeRight == nil then
    cfg.takeRight = false
  end
  if cfg.coverTarget == nil then
    cfg.coverTarget = false
  end
  return cfg
end

local function SpellName(spellId)
  if C_Spell and C_Spell.GetSpellInfo then
    local ok, info = pcall(C_Spell.GetSpellInfo, spellId)
    if ok and type(info) == "table" then
      local name = PlainString(info.name)
      if name then
        return name
      end
    end
  end
  if GetSpellInfo then
    local ok, name = pcall(GetSpellInfo, spellId)
    if ok then
      return PlainString(name)
    end
  end
  return nil
end

local function SpellRank(spellId)
  local subtext = nil
  if C_Spell and C_Spell.GetSpellSubtext then
    local ok, value = pcall(C_Spell.GetSpellSubtext, spellId)
    if ok then
      subtext = PlainString(value)
    end
  end
  if not subtext and GetSpellSubtext then
    local ok, value = pcall(GetSpellSubtext, spellId)
    if ok then
      subtext = PlainString(value)
    end
  end
  if not subtext then
    return nil
  end
  local digits = subtext:match("(%d+)")
  if not digits then
    return nil
  end
  return PlainNumber(tonumber(digits))
end

local function LearnedLevel(spellId)
  if not (C_Spell and C_Spell.GetSpellLevelLearned) then
    return nil
  end
  local ok, level = pcall(C_Spell.GetSpellLevelLearned, spellId)
  if not ok then
    return nil
  end
  return PlainNumber(level)
end

local function BaseName(name)
  local stripped = name:match("^(.-)%s*%(")
  if stripped and stripped ~= "" then
    return stripped
  end
  return name
end

local function NameKnown(name)
  if C_Spell and C_Spell.GetSpellInfo then
    local ok, info = pcall(C_Spell.GetSpellInfo, name)
    if ok and type(info) == "table" and PlainString(info.name) then
      return true
    end
  end
  if GetSpellInfo then
    local ok, found = pcall(GetSpellInfo, name)
    if ok and PlainString(found) then
      return true
    end
  end
  return false
end

local function EachSpellId(visitor)
  local book = C_SpellBook
  local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
  if book and book.GetSpellBookItemInfo and book.GetNumSpellBookSkillLines and book.GetSpellBookSkillLineInfo then
    local ok, lineCount = pcall(book.GetNumSpellBookSkillLines)
    lineCount = ok and PlainNumber(lineCount) or nil
    if lineCount and lineCount >= 1 then
      local line
      for line = 1, lineCount do
        local infoOk, lineInfo = pcall(book.GetSpellBookSkillLineInfo, line)
        if infoOk and type(lineInfo) == "table" then
          local offset = PlainNumber(lineInfo.itemIndexOffset) or 0
          local count = PlainNumber(lineInfo.numSpellBookItems) or 0
          local index
          for index = 1, count do
            local itemOk, item = pcall(book.GetSpellBookItemInfo, offset + index, bank)
            if itemOk and type(item) == "table" then
              local spellId = PlainNumber(item.spellID or item.spellId)
              if spellId then
                visitor(spellId)
              end
            end
          end
        end
      end
      return
    end
  end
  if not (GetNumSpellTabs and GetSpellTabInfo and GetSpellBookItemInfo) then
    return
  end
  local tabsOk, tabs = pcall(GetNumSpellTabs)
  tabs = tabsOk and PlainNumber(tabs) or nil
  if not tabs or tabs < 1 then
    return
  end
  local bookType = _G.BOOKTYPE_SPELL or "spell"
  local tab
  for tab = 1, tabs do
    local tabOk, _, _, offset, count = pcall(GetSpellTabInfo, tab)
    offset = tabOk and PlainNumber(offset) or nil
    count = tabOk and PlainNumber(count) or nil
    if offset and count and count > 0 then
      local index
      for index = offset + 1, offset + count do
        local itemOk, spellType, spellId = pcall(GetSpellBookItemInfo, index, bookType)
        if itemOk and not IsSecret(spellType) and spellType == "SPELL" then
          spellId = PlainNumber(spellId)
          if spellId then
            visitor(spellId)
          end
        end
      end
    end
  end
end

local function BestCast(baseName)
  baseName = PlainString(baseName)
  if not baseName then
    return nil
  end
  local level = PlayerLevel()
  local bestRank = nil
  local saw = false
  EachSpellId(function(spellId)
    local name = SpellName(spellId)
    if not name or BaseName(name) ~= baseName then
      return
    end
    local learned = LearnedLevel(spellId)
    if learned and level and learned > level then
      return
    end
    saw = true
    local rank = SpellRank(spellId) or 0
    if not bestRank or rank > bestRank then
      bestRank = rank
    end
  end)
  if NameKnown(baseName) then
    return baseName
  end
  if saw and bestRank and bestRank > 0 then
    local ranked = baseName .. "(Rank " .. bestRank .. ")"
    if NameKnown(ranked) then
      return ranked
    end
  end
  if saw then
    return baseName
  end
  return nil
end

local function BestOf(names)
  if type(names) ~= "table" then
    return nil
  end
  local index
  for index = 1, #names do
    local cast = BestCast(names[index])
    if cast then
      return cast
    end
  end
  return nil
end

local function Resolve()
  local classFile = PlayerClass()
  local defaults = DEFAULTS[classFile or ""] or {}
  local binds = Config().binds
  local key
  for key in pairs(resolved) do
    resolved[key] = nil
  end
  local index
  for index = 1, #BINDS do
    local entry = BINDS[index]
    local override = PlainString(binds[entry.key])
    if override == "none" then
      resolved[entry.key] = nil
    elseif override then
      resolved[entry.key] = BestCast(override)
    else
      resolved[entry.key] = BestOf(defaults[entry.key])
    end
    local status = statusText[entry.key]
    if status then
      status:SetText(resolved[entry.key] or "not used")
    end
  end
end

local function ButtonWanted(button)
  local index
  for index = 1, #BINDS do
    local entry = BINDS[index]
    if entry.button == button and resolved[entry.key] then
      return true
    end
  end
  return false
end

local function UsableUnit(unit)
  unit = PlainString(unit)
  if not unit then
    return nil
  end
  if unit == "target" or unit == "focus" then
    return unit
  end
  if unit:match("^party%d$") or unit:match("^raid%d+$") then
    return unit
  end
  return nil
end

local function FrameUnit(frame)
  if type(frame) ~= "table" then
    return nil
  end
  local unit = nil
  if frame.GetAttribute then
    local ok, value = pcall(frame.GetAttribute, frame, "unit")
    if ok then
      unit = UsableUnit(value)
    end
  end
  if not unit then
    unit = UsableUnit(rawget(frame, "unit"))
  end
  if not unit then
    unit = UsableUnit(rawget(frame, "displayedUnit"))
  end
  if not unit and frame.GetName then
    local nameOk, name = pcall(frame.GetName, frame)
    name = nameOk and PlainString(name) or nil
    local index = name and name:match("^PartyMemberFrame(%d+)$")
    if not index and name then
      index = name:match("^CompactPartyFrameMember(%d+)$")
    end
    if not index and name then
      index = name:match("^PartyFrameMember(%d+)$")
    end
    if index then
      unit = "party" .. index
    end
  end
  if not unit then
    return nil
  end
  if (unit == "target" or unit == "focus") and Config().coverTarget ~= true then
    return nil
  end
  return unit
end

local function FrameShown(frame)
  if type(frame) ~= "table" or not frame.IsShown then
    return false
  end
  local ok, shown = pcall(frame.IsShown, frame)
  return ok and shown == true
end

local function AncestorHasUnit(frame, unit)
  if type(frame) ~= "table" or not frame.GetParent then
    return false
  end
  local parent = frame:GetParent()
  local guard = 0
  while type(parent) == "table" and guard < 8 do
    if FrameUnit(parent) == unit then
      return true
    end
    if not parent.GetParent then
      return false
    end
    parent = parent:GetParent()
    guard = guard + 1
  end
  return false
end

local function AddFrame(list, seen, frame)
  if type(frame) ~= "table" or seen[frame] then
    return
  end
  local unit = FrameUnit(frame)
  if not unit or AncestorHasUnit(frame, unit) then
    return
  end
  seen[frame] = true
  list[#list + 1] = frame
end

local function AddChildren(list, seen, parent, depth)
  if type(parent) ~= "table" or depth > 4 or not parent.GetChildren then
    return
  end
  local ok, children = pcall(function()
    return { parent:GetChildren() }
  end)
  if not ok or type(children) ~= "table" then
    return
  end
  local index
  for index = 1, #children do
    local child = children[index]
    AddFrame(list, seen, child)
    AddChildren(list, seen, child, depth + 1)
  end
end

local function GroupFrames()
  local list = {}
  local seen = {}
  local index
  for index = 1, #NAMED_FRAMES do
    AddFrame(list, seen, _G[NAMED_FRAMES[index]])
  end
  local raid
  for raid = 1, 40 do
    AddFrame(list, seen, _G["CompactRaidFrame" .. raid])
  end
  if Config().coverTarget == true then
    AddFrame(list, seen, _G.TargetFrame)
    AddFrame(list, seen, _G.FocusFrame)
  end
  for index = 1, #CONTAINERS do
    AddChildren(list, seen, _G[CONTAINERS[index]], 0)
  end
  if EnumerateFrames then
    local frame = EnumerateFrames()
    local guard = 0
    while frame and guard < 8000 do
      local nameOk, name = false, nil
      if frame.GetName then
        nameOk, name = pcall(frame.GetName, frame)
      end
      name = nameOk and PlainString(name) or nil
      local interesting = name and (
        name:find("Party", 1, true)
        or name:find("Raid", 1, true)
        or name:find("Compact", 1, true)
      )
      if interesting then
        AddFrame(list, seen, frame)
        AddChildren(list, seen, frame, 0)
      end
      frame = EnumerateFrames(frame)
      guard = guard + 1
    end
  end
  return list
end

local function Watch(frame)
  if type(frame) ~= "table" or watched[frame] or not frame.HookScript then
    return
  end
  watched[frame] = true
  pcall(frame.HookScript, frame, "OnShow", function()
    if FTK:IsEnabled(MODULE_ID) then
      pending = true
    end
  end)
  pcall(frame.HookScript, frame, "OnHide", function()
    local overlay = overlays[frame]
    if overlay and not InCombat() then
      overlay:Hide()
    else
      pending = true
    end
  end)
end

local function ApplyClicks(overlay)
  local clicks = {}
  if ButtonWanted("left") then
    clicks[#clicks + 1] = CLICK.left
  end
  if ButtonWanted("right") then
    clicks[#clicks + 1] = CLICK.right
  end
  if ButtonWanted("middle") then
    clicks[#clicks + 1] = CLICK.middle
  end
  if #clicks == 0 then
    overlay:Hide()
    return false
  end
  overlay:RegisterForClicks(unpack(clicks))
  return true
end

local function SetBind(overlay, entry)
  local spell = resolved[entry.key]
  local cfg = Config()
  if spell and not (entry.key == "left" and cfg.takeLeft ~= true) and not (entry.key == "right" and cfg.takeRight ~= true) then
    overlay:SetAttribute(entry.type, "spell")
    overlay:SetAttribute(entry.spell, spell)
    return
  end
  if entry.key == "left" and ButtonWanted("left") then
    overlay:SetAttribute(entry.type, "target")
    overlay:SetAttribute(entry.spell, nil)
    return
  end
  if entry.key == "right" and ButtonWanted("right") then
    overlay:SetAttribute(entry.type, "togglemenu")
    overlay:SetAttribute(entry.spell, nil)
    return
  end
  overlay:SetAttribute(entry.type, nil)
  overlay:SetAttribute(entry.spell, nil)
end

local function ShowBindings(tooltip)
  local index
  for index = 1, #BINDS do
    local entry = BINDS[index]
    local spell = resolved[entry.key]
    local cfg = Config()
    local used = spell and not (entry.key == "left" and cfg.takeLeft ~= true) and not (entry.key == "right" and cfg.takeRight ~= true)
    if used then
      tooltip:AddLine(entry.label .. ": " .. spell, 0.6, 1, 0.6)
    end
  end
end

local function EnsureOverlay(frame)
  local overlay = overlays[frame]
  if overlay then
    return overlay
  end
  overlayCount = overlayCount + 1
  local ok, created = pcall(CreateFrame, "Button", "ForeverToolkitClickHeal" .. overlayCount, UIParent, "SecureActionButtonTemplate")
  if not ok or type(created) ~= "table" then
    return nil
  end
  overlay = created
  overlay:Hide()
  overlay:SetScript("OnEnter", function(self)
    local unit = PlainString(self.ftkUnit)
    if not unit or not GameTooltip then
      return
    end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local shown = pcall(GameTooltip.SetUnit, GameTooltip, unit)
    if not shown then
      GameTooltip:SetText(unit)
    end
    ShowBindings(GameTooltip)
    GameTooltip:Show()
  end)
  overlay:SetScript("OnLeave", function()
    if GameTooltip then
      GameTooltip:Hide()
    end
  end)
  overlays[frame] = overlay
  return overlay
end

local function PlaceOverlay(frame)
  local unit = FrameUnit(frame)
  local overlay = overlays[frame]
  if not unit or not FrameShown(frame) then
    if overlay and not InCombat() then
      overlay:Hide()
    end
    return
  end
  if InCombat() then
    pending = true
    return
  end
  overlay = EnsureOverlay(frame)
  if not overlay then
    pending = true
    return
  end
  Watch(frame)
  if not ApplyClicks(overlay) then
    return
  end
  overlay.ftkUnit = unit
  overlay:SetAttribute("unit", unit)
  local index
  for index = 1, #BINDS do
    SetBind(overlay, BINDS[index])
  end
  local strata = "MEDIUM"
  if frame.GetFrameStrata then
    local strataOk, value = pcall(frame.GetFrameStrata, frame)
    if strataOk and PlainString(value) then
      strata = value
    end
  end
  overlay:SetFrameStrata(strata)
  local level = 40
  if frame.GetFrameLevel then
    local levelOk, value = pcall(frame.GetFrameLevel, frame)
    value = levelOk and PlainNumber(value) or nil
    if value then
      level = value + 30
    end
  end
  overlay:SetFrameLevel(level)
  overlay:ClearAllPoints()
  overlay:SetAllPoints(frame)
  overlay:Show()
end

local applying = false
local nextApply = 0

local function Apply()
  if applying or not FTK:IsEnabled(MODULE_ID) then
    return
  end
  applying = true
  local classFile = PlayerClass()
  if not classFile or not HEALERS[classFile] then
    if not saidClass then
      saidClass = true
      FTK:Print("Click Heal is for a Priest, Druid, Paladin, or Shaman.")
    end
    applying = false
    return
  end
  if InCombat() then
    pending = true
    applying = false
    return
  end
  pending = false
  Resolve()
  local frames = GroupFrames()
  local keep = {}
  local index
  for index = 1, #frames do
    keep[frames[index]] = true
    PlaceOverlay(frames[index])
  end
  local frame, overlay
  for frame, overlay in pairs(overlays) do
    if not keep[frame] then
      overlay:Hide()
    end
  end
  applying = false
end

local function Disarm()
  if InCombat() then
    pending = true
    return
  end
  pending = false
  local frame, overlay
  for frame, overlay in pairs(overlays) do
    overlay.ftkUnit = nil
    overlay:Hide()
    local index
    for index = 1, #BINDS do
      local entry = BINDS[index]
      overlay:SetAttribute(entry.type, nil)
      overlay:SetAttribute(entry.spell, nil)
    end
    overlay:SetAttribute("unit", nil)
  end
end

events:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_REGEN_ENABLED" then
    if not FTK:IsEnabled(MODULE_ID) then
      Disarm()
      return
    end
    if pending then
      Apply()
    end
    return
  end
  if not FTK:IsEnabled(MODULE_ID) then
    return
  end
  if event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_TAB" then
    Resolve()
  end
  pending = true
  if not InCombat() then
    Apply()
  end
end)

events:SetScript("OnUpdate", function()
  if not pending or applying or not FTK:IsEnabled(MODULE_ID) or InCombat() then
    return
  end
  local now = 0
  if GetTime then
    local ok, value = pcall(GetTime)
    now = ok and PlainNumber(value) or 0
  end
  if now < nextApply then
    return
  end
  nextApply = now + 3
  Apply()
end)

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
    if FTK:IsEnabled(MODULE_ID) then
      pending = true
      if not InCombat() then
        Apply()
      else
        FTK:Print("Click Heal will use that after combat.")
      end
    end
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
  note:SetText("The spell name on the right of each row is what that click casts now. To change it, type the spell you want into the box on that row and press Enter. Leave the box empty to keep the spell shown on the right. Type none and press Enter to turn that click off. Left and right click stay on the normal frames unless you turn that on.")
  y = y - 78
  y = CheckLine(parent, "Heal with left click", y, function()
    return Config().takeLeft == true
  end, function(value)
    Config().takeLeft = value
  end)
  y = CheckLine(parent, "Heal with right click", y, function()
    return Config().takeRight == true
  end, function(value)
    Config().takeRight = value
  end)
  y = CheckLine(parent, "Also cover target and focus", y, function()
    return Config().coverTarget == true
  end, function(value)
    Config().coverTarget = value
  end)
  local index
  for index = 1, #BINDS do
    local entry = BINDS[index]
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", 0, y)
    label:SetWidth(110)
    label:SetJustifyH("LEFT")
    label:SetText(entry.label)
    local box
    local boxOk, created = pcall(CreateFrame, "EditBox", nil, parent, "InputBoxTemplate")
    if boxOk and type(created) == "table" then
      box = created
    else
      box = CreateFrame("EditBox", nil, parent)
      box:SetFontObject("GameFontHighlightSmall")
      box:SetTextInsets(6, 6, 2, 2)
    end
    box:SetSize(160, 20)
    box:SetPoint("TOPLEFT", 116, y + 2)
    box:SetAutoFocus(false)
    local stored = PlainString(Config().binds[entry.key])
    box:SetText(stored or "")
    local function SaveBox(self)
      local text = PlainString(self:GetText())
      if text then
        Config().binds[entry.key] = text
      else
        Config().binds[entry.key] = nil
      end
      Resolve()
      if FTK:IsEnabled(MODULE_ID) then
        pending = true
        if not InCombat() then
          Apply()
        end
      end
    end
    box:SetScript("OnEnterPressed", function(self)
      SaveBox(self)
      self:ClearFocus()
    end)
    box:SetScript("OnEditFocusLost", SaveBox)
    local status = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("LEFT", box, "RIGHT", 8, 0)
    status:SetWidth(140)
    status:SetJustifyH("LEFT")
    statusText[entry.key] = status
    y = y - 28
  end
  Resolve()
  parent:SetHeight((-y) + 12)
end

FTK:RegisterModule({
  id = MODULE_ID,
  name = "Click Heal",
  description = "Casts your heals from party and raid frames. Your own character frame is left alone. Modified clicks cast. Left and right click stay with the game unless you turn that on.",
  defaultEnabled = true,
  BuildOptions = BuildOptions,
  onEnable = function()
    local names = {
      "PLAYER_REGEN_ENABLED",
      "GROUP_ROSTER_UPDATE",
      "PLAYER_ENTERING_WORLD",
      "SPELLS_CHANGED",
    }
    local index
    for index = 1, #names do
      pcall(events.RegisterEvent, events, names[index])
    end
    pending = true
    if InCombat() then
      FTK:Print("Click Heal will arm when combat ends.")
      return
    end
    Apply()
  end,
  onDisable = function()
    events:UnregisterAllEvents()
    if InCombat() then
      pending = true
      events:RegisterEvent("PLAYER_REGEN_ENABLED")
      return
    end
    Disarm()
  end,
})
