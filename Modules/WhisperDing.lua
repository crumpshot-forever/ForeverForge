--[[
  Whisper Ding. Plays a short sound when you receive a whisper.
  Module enable = whisper ding. Optional BN whisper via Configure
  (default OFF). No per-channel sound suite.
]]

local FTK = ForeverForge
if not FTK then
  error("ForeverForge: Core.lua must load before Modules/WhisperDing.lua")
end

local MODULE_ID = "WhisperDing"
local SOUND_GAP = 0.4
local lastSound = 0

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

local function Config()
  local cfg = FTK:GetConfig(MODULE_ID)
  if cfg.bnWhisper == nil then
    cfg.bnWhisper = false
  end
  return cfg
end

local function Now()
  if not GetTime then
    return 0
  end
  local ok, value = pcall(GetTime)
  if not ok then
    return 0
  end
  return PlainNumber(value) or 0
end

local function PlayId(id)
  if type(id) ~= "number" or not PlaySound then
    return false
  end
  local ok, played = pcall(PlaySound, id, "Master")
  return ok and played ~= false
end

local function PlayCue()
  local now = Now()
  if lastSound > 0 and now - lastSound < SOUND_GAP then
    return
  end
  lastSound = now
  if SOUNDKIT then
    if SOUNDKIT.TELL_MESSAGE and PlayId(SOUNDKIT.TELL_MESSAGE) then
      return
    end
    if SOUNDKIT.MapPing and PlayId(SOUNDKIT.MapPing) then
      return
    end
    if SOUNDKIT.MAP_PING and PlayId(SOUNDKIT.MAP_PING) then
      return
    end
  end
  -- Classic-ish fallbacks.
  if PlayId(3081) then
    return
  end
  if PlayId(5274) then
    return
  end
  PlayId(8960)
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
  note:SetText("Module on = ding for normal whispers. Battle.net whispers are optional and off by default.")
  y = y - 40
  local cfg = Config()
  y = CheckLine(parent, "Also ding for Battle.net whispers", y, function()
    return cfg.bnWhisper == true
  end, function(value)
    Config().bnWhisper = value == true
  end)
  parent:SetHeight((-y) + 12)
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
  if not FTK:IsEnabled(MODULE_ID) then
    return
  end
  if event == "CHAT_MSG_WHISPER" then
    PlayCue()
    return
  end
  if event == "CHAT_MSG_BN_WHISPER" then
    if Config().bnWhisper == true then
      PlayCue()
    end
  end
end)

FTK:RegisterModule({
  id = MODULE_ID,
  name = "Whisper Ding",
  description = "Plays a short sound when you receive a whisper. Optional Battle.net whisper ding (default off).",
  defaultEnabled = false,
  BuildOptions = BuildOptions,
  onEnable = function()
    pcall(events.RegisterEvent, events, "CHAT_MSG_WHISPER")
    pcall(events.RegisterEvent, events, "CHAT_MSG_BN_WHISPER")
  end,
  onDisable = function()
    events:UnregisterAllEvents()
  end,
})
