--[[
  Durability Warning. When an equipped piece drops to or below the threshold
  (default 30%), posts one local chat line for that piece. The same piece is
  not warned again until it is repaired above the threshold. Chat is silent
  in combat; pending warnings fire after combat ends. Optional sound is off
  by default. No on-screen durability overlay.
]]

local FTK = ForeverForge
if not FTK then
  error("ForeverForge: Core.lua must load before Modules/DurabilityWarning.lua")
end

local MODULE_ID = "DurabilityWarning"
local DEFAULT_THRESHOLD = 30
local SLOT_MIN = 1
local SLOT_MAX = 19

local frame = CreateFrame("Frame")
-- slot -> itemID that was already warned while at/below threshold
local warned = {}
-- true when a scan found warn-worthy gear during combat
local pending = false

local function ClearWarned()
  local slot
  for slot in pairs(warned) do
    warned[slot] = nil
  end
end

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
  if IsSecret(value) or type(value) ~= "string" or value == "" then
    return nil
  end
  return value
end

local function Config()
  local cfg = FTK:GetConfig(MODULE_ID)
  local threshold = PlainNumber(cfg.threshold)
  if not threshold or threshold < 1 or threshold > 100 then
    cfg.threshold = DEFAULT_THRESHOLD
  else
    cfg.threshold = math.floor(threshold)
  end
  if cfg.playSound == nil then
    cfg.playSound = false
  end
  return cfg
end

local function InCombat()
  if type(InCombatLockdown) == "function" then
    local ok, value = pcall(InCombatLockdown)
    if ok and not IsSecret(value) and value == true then
      return true
    end
  end
  if type(UnitAffectingCombat) == "function" then
    local ok, value = pcall(UnitAffectingCombat, "player")
    if ok and not IsSecret(value) and value == true then
      return true
    end
  end
  return false
end

local function SlotDurability(slot)
  if type(GetInventoryItemDurability) ~= "function" then
    return nil, nil
  end
  local ok, current, maximum = pcall(GetInventoryItemDurability, slot)
  if not ok then
    return nil, nil
  end
  current = PlainNumber(current)
  maximum = PlainNumber(maximum)
  if not current or not maximum or maximum <= 0 then
    return nil, nil
  end
  return current, maximum
end

local function SlotItemID(slot)
  if type(GetInventoryItemID) == "function" then
    local ok, itemID = pcall(GetInventoryItemID, "player", slot)
    itemID = ok and PlainNumber(itemID) or nil
    if itemID then
      return itemID
    end
  end
  if type(GetInventoryItemLink) == "function" then
    local ok, link = pcall(GetInventoryItemLink, "player", slot)
    link = ok and PlainString(link) or nil
    if link then
      local matchOk, id = pcall(function()
        return tonumber(link:match("item:(%d+)"))
      end)
      return matchOk and PlainNumber(id) or nil
    end
  end
  return nil
end

local function SlotName(slot)
  if type(GetInventoryItemLink) == "function" then
    local linkOk, link = pcall(GetInventoryItemLink, "player", slot)
    link = linkOk and PlainString(link) or nil
    if link then
      if type(GetItemInfo) == "function" then
        local nameOk, name = pcall(GetItemInfo, link)
        name = nameOk and PlainString(name) or nil
        if name then
          return name
        end
      end
      local ok, extracted = pcall(function()
        return link:match("%[(.-)%]")
      end)
      extracted = ok and PlainString(extracted) or nil
      if extracted then
        return extracted
      end
    end
  end
  return "slot " .. tostring(slot)
end

local function Percent(current, maximum)
  if not current or not maximum or maximum <= 0 then
    return nil
  end
  return (current / maximum) * 100
end

local function PlayCue()
  if not Config().playSound then
    return
  end
  if type(PlaySound) ~= "function" then
    return
  end
  local function PlayId(id)
    if type(id) ~= "number" then
      return false
    end
    local ok, played = pcall(PlaySound, id, "Master")
    return ok and played ~= false
  end
  if SOUNDKIT and PlayId(PlainNumber(SOUNDKIT.MAP_PING)) then
    return
  end
  if PlayId(3175) then
    return
  end
  PlayId(8960)
end

local function WarnSlot(slot, pct)
  local name = SlotName(slot)
  local whole = math.floor(pct + 0.5)
  FTK:Print("Durability Warning: " .. name .. " is at " .. tostring(whole) .. "%.")
  PlayCue()
end

local function AlreadyWarned(slot, itemID)
  local prior = warned[slot]
  if prior == nil then
    return false
  end
  -- Same slot, different item: treat as a new piece.
  if itemID and prior ~= itemID and prior ~= true then
    return false
  end
  return true
end

local function Scan()
  if not FTK:IsEnabled(MODULE_ID) then
    return
  end
  local cfg = Config()
  local threshold = PlainNumber(cfg.threshold) or DEFAULT_THRESHOLD
  local combat = InCombat()
  local slot
  for slot = SLOT_MIN, SLOT_MAX do
    local current, maximum = SlotDurability(slot)
    if not current then
      warned[slot] = nil
    else
      local pct = Percent(current, maximum)
      local itemID = SlotItemID(slot)
      if pct == nil then
        warned[slot] = nil
      elseif pct > threshold then
        -- Repaired (or never low): allow a future warn for this piece.
        warned[slot] = nil
      elseif not AlreadyWarned(slot, itemID) then
        if combat then
          pending = true
        else
          warned[slot] = itemID or true
          WarnSlot(slot, pct)
        end
      end
    end
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
  note:SetText("Chat once per equipped piece when durability is at or below the threshold. Silent in combat; warns after combat ends. Optional sound is off by default. No on-screen overlay.")
  y = y - 48

  local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  label:SetPoint("TOPLEFT", 0, y)
  label:SetText("Warn at or below (%)")
  local box
  local boxOk, created = pcall(CreateFrame, "EditBox", nil, parent, "InputBoxTemplate")
  if boxOk and type(created) == "table" then
    box = created
  else
    box = CreateFrame("EditBox", nil, parent)
    box:SetFontObject("GameFontHighlightSmall")
    box:SetTextInsets(6, 6, 2, 2)
  end
  box:SetSize(48, 20)
  box:SetPoint("LEFT", label, "RIGHT", 12, 0)
  box:SetAutoFocus(false)
  pcall(function()
    box:SetNumeric(true)
  end)
  box:SetText(tostring(Config().threshold or DEFAULT_THRESHOLD))
  local function SaveBox(self)
    local text = PlainString(self:GetText())
    local n = text and PlainNumber(tonumber(text)) or nil
    if n and n >= 1 and n <= 100 then
      Config().threshold = math.floor(n)
      ClearWarned()
      if FTK:IsEnabled(MODULE_ID) then
        Scan()
      end
    else
      Config().threshold = DEFAULT_THRESHOLD
      self:SetText(tostring(DEFAULT_THRESHOLD))
    end
  end
  box:SetScript("OnEnterPressed", function(self)
    SaveBox(self)
    self:ClearFocus()
  end)
  box:SetScript("OnEditFocusLost", SaveBox)
  y = y - 32

  y = CheckLine(parent, "Play a short sound with the warning", y, function()
    return Config().playSound == true
  end, function(value)
    Config().playSound = value == true
  end)

  parent:SetHeight((-y) + 12)
end

frame:SetScript("OnEvent", function(_, event)
  if not FTK:IsEnabled(MODULE_ID) then
    return
  end
  if event == "PLAYER_REGEN_ENABLED" then
    if pending then
      pending = false
      Scan()
    end
    return
  end
  if event == "PLAYER_REGEN_DISABLED" then
    return
  end
  -- PLAYER_ENTERING_WORLD / UPDATE_INVENTORY_DURABILITY / PLAYER_EQUIPMENT_CHANGED
  Scan()
end)

FTK:RegisterModule({
  id = MODULE_ID,
  name = "Durability Warning",
  description = "Chat once per equipped piece when durability is at or below a threshold (default 30%). Silent in combat. Optional sound off by default. No overlay.",
  defaultEnabled = true,
  BuildOptions = BuildOptions,
  onEnable = function()
    Config()
    ClearWarned()
    pending = false
    local names = {
      "PLAYER_ENTERING_WORLD",
      "UPDATE_INVENTORY_DURABILITY",
      "PLAYER_EQUIPMENT_CHANGED",
      "PLAYER_REGEN_ENABLED",
      "PLAYER_REGEN_DISABLED",
    }
    local i
    for i = 1, #names do
      pcall(frame.RegisterEvent, frame, names[i])
    end
    Scan()
  end,
  onDisable = function()
    frame:UnregisterAllEvents()
    ClearWarned()
    pending = false
  end,
})
