--[[
  Campfire Alert. When Campfire Nearby is confirmed on the player, post one
  local chat line and, if the sound option is on, play one sound.

  Campfire Nearby is spell 1283391 on Forever 1.60.1: a unique dummy aura
  with a 100 yard radius, no duration, applied by a server script. Wowhead's
  Forever notes describe it as the buff that appears when a camp is close,
  before anyone sits. Camp Benefits is the hour-long buff from sitting and
  is not used here. A lingering buff is not treated as proof the fire is
  still nearby.

  The aura does not include the camp's coordinates, and no supported API
  found for this client exposes that object position. There is no minimap
  marker. The player's own position is never shown as the camp.

  The same aura covers every camp in range, so adjacent fires are one
  alert. An unreadable aura bar does not count as leaving. After a
  confirmed absence of 10 seconds the alert can arm again, and a new
  entry still waits out a 60 second cooldown from the last alert.

  Nothing is sent to public chat.
]]

local FTK = ForeverForge
if not FTK then
  error("ForeverForge: Core.lua must load before Modules/CampfireAlert.lua")
end

local MODULE_ID = "CampfireAlert"
-- Published Forever 1.60.1 spell. Matched by this id or by the localized
-- name the client returns for it. Not Camp Benefits, Welcoming Campfire,
-- or the old Cozy Fire cooking buff.
local CAMP_SPELL_ID = 1283391
local ABSENT_REARM = 10
local REENTRY_COOLDOWN = 60
local SCAN_INTERVAL = 1

local frame = CreateFrame("Frame")
local expectedName
local latched = false
local nextAlert = 0
local absentAccrued = 0
local absentMark = nil
local lastState = nil
local scanElapsed = 0

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

local function Now()
  if type(GetTime) ~= "function" then
    return 0
  end
  local ok, value = pcall(GetTime)
  if not ok then
    return 0
  end
  return PlainNumber(value) or 0
end

local function Config()
  return FTK:GetConfig(MODULE_ID)
end

local function SoundOn()
  return Config().sound ~= false
end

local function DebugOn()
  return Config().debug == true
end

local function ExpectedName()
  if expectedName then
    return expectedName
  end
  local name
  if C_Spell and type(C_Spell.GetSpellName) == "function" then
    local ok, value = pcall(C_Spell.GetSpellName, CAMP_SPELL_ID)
    if ok then
      name = PlainString(value)
    end
  end
  if not name and type(GetSpellInfo) == "function" then
    local ok, value = pcall(GetSpellInfo, CAMP_SPELL_ID)
    if ok then
      name = PlainString(value)
    end
  end
  if name then
    expectedName = name
  end
  return name
end

local function PlayId(id)
  if type(id) ~= "number" or type(PlaySound) ~= "function" then
    return false
  end
  local ok, played = pcall(PlaySound, id, "Master")
  return ok and played ~= false
end

local function PlayCue()
  if SOUNDKIT and type(SOUNDKIT.READY_CHECK) == "number" and PlayId(SOUNDKIT.READY_CHECK) then
    return
  end
  if PlayId(8960) then
    return
  end
  PlayId(3175)
end

local function ConsiderAura(spellId, name)
  local id = PlainNumber(spellId)
  local label = PlainString(name)
  local expect = ExpectedName()
  if id == CAMP_SPELL_ID then
    return "present"
  end
  if label and expect and label == expect then
    return "present"
  end
  -- A readable id or a readable other name is not this buff. A secret
  -- id with no readable name cannot be ruled out.
  if id ~= nil then
    return "no"
  end
  if label and expect and label ~= expect then
    return "no"
  end
  if IsSecret(spellId) or IsSecret(name) then
    return "secret"
  end
  return "no"
end

local function ReadIndex(index, filter)
  if C_UnitAuras and type(C_UnitAuras.GetAuraDataByIndex) == "function" then
    local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", index, filter)
    if not ok or IsSecret(aura) then
      return "unknown"
    end
    if aura == nil then
      return "end"
    end
    if type(aura) ~= "table" then
      return "secret"
    end
    return ConsiderAura(aura.spellId, aura.name)
  end
  if type(UnitAura) ~= "function" then
    return "unsupported"
  end
  local ok, name, _, _, _, _, _, _, _, _, spellId = pcall(UnitAura, "player", index, filter)
  if not ok then
    return "unknown"
  end
  if name == nil and spellId == nil then
    return "end"
  end
  return ConsiderAura(spellId, name)
end

-- "present", "absent", or "unknown". Unknown must not count as leaving.
local function Scan()
  local sawSecret = false
  local index
  for index = 1, 40 do
    local reading = ReadIndex(index, "HELPFUL")
    if reading == "unsupported" then
      return "unknown"
    end
    if reading == "end" then
      break
    end
    if reading == "present" then
      return "present"
    end
    if reading == "secret" or reading == "unknown" then
      sawSecret = true
    end
  end
  if sawSecret then
    return "unknown"
  end
  return "absent"
end

local function DebugState(state)
  if not DebugOn() or state == lastState then
    return
  end
  lastState = state
  if state == "present" then
    local name = ExpectedName()
    if name then
      FTK:Print("Campfire Alert debug: Campfire Nearby is on you (" .. name .. ").")
    else
      FTK:Print("Campfire Alert debug: Campfire Nearby is on you.")
    end
  elseif state == "absent" then
    FTK:Print("Campfire Alert debug: Campfire Nearby is not on you.")
  else
    FTK:Print("Campfire Alert debug: aura bar unreadable. Holding the current alert state.")
  end
end

local function ClearPresence()
  latched = false
  absentAccrued = 0
  absentMark = nil
end

local function Alert()
  FTK:Print("Active campfire nearby")
  if SoundOn() then
    PlayCue()
  end
end

local function Evaluate()
  if not FTK:IsEnabled(MODULE_ID) then
    return
  end
  local state = Scan()
  DebugState(state)
  local now = Now()
  if state == "present" then
    absentAccrued = 0
    absentMark = nil
    if not latched then
      latched = true
      if now >= nextAlert then
        Alert()
        nextAlert = now + REENTRY_COOLDOWN
      end
    end
    return
  end
  if state == "unknown" or not latched then
    if absentMark then
      absentAccrued = absentAccrued + (now - absentMark)
      absentMark = nil
    end
    return
  end
  if not absentMark then
    absentMark = now
  end
  if absentAccrued + (now - absentMark) >= ABSENT_REARM then
    ClearPresence()
  end
end

local function OnUpdate(_, elapsed)
  local step = PlainNumber(elapsed) or 0
  scanElapsed = scanElapsed + step
  if scanElapsed < SCAN_INTERVAL then
    return
  end
  scanElapsed = 0
  Evaluate()
end

local function OnEvent(_, event, unit)
  if event == "UNIT_AURA" then
    if unit ~= "player" then
      return
    end
    Evaluate()
    return
  end
  ClearPresence()
  Evaluate()
end

local function Watch(event)
  pcall(frame.RegisterEvent, frame, event)
end

local function Start()
  frame:SetScript("OnEvent", OnEvent)
  frame:SetScript("OnUpdate", OnUpdate)
  Watch("UNIT_AURA")
  Watch("PLAYER_ENTERING_WORLD")
  Watch("ZONE_CHANGED_NEW_AREA")
  scanElapsed = SCAN_INTERVAL
  Evaluate()
end

local function Stop()
  frame:SetScript("OnEvent", nil)
  frame:SetScript("OnUpdate", nil)
  pcall(frame.UnregisterAllEvents, frame)
  ClearPresence()
  nextAlert = 0
  lastState = nil
  scanElapsed = 0
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
    local checked = self:GetChecked()
    setter(checked == true or checked == 1)
  end)
  local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  text:SetPoint("LEFT", box, "RIGHT", 4, 0)
  text:SetText(label)
  return y - 28
end

local function BuildOptions(_, parent)
  local note = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  note:SetPoint("TOPLEFT", 0, -4)
  note:SetWidth(420)
  note:SetJustifyH("LEFT")
  note:SetWordWrap(true)
  note:SetText("Off until you enable Campfire Alert in the list. A confirmed Campfire Nearby buff posts one local line. There is no map marker: that buff does not include where the fire is. The same alert covers every camp in range. Turning the module off stops the scan.")
  local y = -78
  y = CheckLine(parent, "Play a sound", y, function()
    return SoundOn()
  end, function(value)
    Config().sound = value == true
  end)
  y = CheckLine(parent, "Debug aura scan", y, function()
    return DebugOn()
  end, function(value)
    Config().debug = value == true
    lastState = nil
  end)
  parent:SetHeight(20 - y)
end

FTK:RegisterModule({
  id = MODULE_ID,
  name = "Campfire Alert",
  description = "Opt-in. When Campfire Nearby is confirmed on you, posts one local line and can play a sound. It does not mark the map: that buff does not carry the camp's location.",
  defaultEnabled = false,
  onEnable = function()
    Start()
  end,
  onDisable = function()
    Stop()
  end,
  BuildOptions = BuildOptions,
})
