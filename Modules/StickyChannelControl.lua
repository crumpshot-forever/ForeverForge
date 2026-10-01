--[[
  Sticky Channel Control. Two Configure switches:
  - Sticky whispers (default OFF)
  - Sticky custom channels (default OFF)
  Uses ChatTypeInfo[].sticky when present. No full channel manager UI.
]]

local FTK = ForeverForge
if not FTK then
  error("ForeverForge: Core.lua must load before Modules/StickyChannelControl.lua")
end

local MODULE_ID = "StickyChannelControl"

local saved = {
  whisper = nil,
  bnWhisper = nil,
  channel = nil,
}

local function Config()
  local cfg = FTK:GetConfig(MODULE_ID)
  if cfg.stickyWhisper == nil then
    cfg.stickyWhisper = false
  end
  if cfg.stickyCustom == nil then
    cfg.stickyCustom = false
  end
  return cfg
end

local function SetSticky(chatType, value)
  local info = _G.ChatTypeInfo and _G.ChatTypeInfo[chatType]
  if type(info) ~= "table" then
    return false
  end
  local ok = pcall(function()
    info.sticky = value and 1 or 0
  end)
  return ok
end

local function GetSticky(chatType)
  local info = _G.ChatTypeInfo and _G.ChatTypeInfo[chatType]
  if type(info) ~= "table" then
    return nil
  end
  local ok, value = pcall(function()
    return info.sticky
  end)
  if not ok then
    return nil
  end
  return value
end

local function RememberDefaults()
  if saved.whisper == nil then
    saved.whisper = GetSticky("WHISPER")
  end
  if saved.bnWhisper == nil then
    saved.bnWhisper = GetSticky("BN_WHISPER")
  end
  if saved.channel == nil then
    saved.channel = GetSticky("CHANNEL")
  end
end

local function Apply()
  if not FTK:IsEnabled(MODULE_ID) then
    return
  end
  RememberDefaults()
  local cfg = Config()
  SetSticky("WHISPER", cfg.stickyWhisper == true)
  SetSticky("BN_WHISPER", cfg.stickyWhisper == true)
  SetSticky("CHANNEL", cfg.stickyCustom == true)
end

local function Restore()
  if saved.whisper ~= nil then
    local info = _G.ChatTypeInfo and _G.ChatTypeInfo.WHISPER
    if type(info) == "table" then
      pcall(function()
        info.sticky = saved.whisper
      end)
    end
  end
  if saved.bnWhisper ~= nil then
    local info = _G.ChatTypeInfo and _G.ChatTypeInfo.BN_WHISPER
    if type(info) == "table" then
      pcall(function()
        info.sticky = saved.bnWhisper
      end)
    end
  end
  if saved.channel ~= nil then
    local info = _G.ChatTypeInfo and _G.ChatTypeInfo.CHANNEL
    if type(info) == "table" then
      pcall(function()
        info.sticky = saved.channel
      end)
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
    if FTK:IsEnabled(MODULE_ID) then
      Apply()
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
  note:SetText("Sticky means the chat edit box stays on that chat type after you send. Both options default off (conservative).")
  y = y - 40
  local cfg = Config()
  y = CheckLine(parent, "Sticky whispers (and BN whispers)", y, function()
    return cfg.stickyWhisper == true
  end, function(value)
    Config().stickyWhisper = value == true
  end)
  y = CheckLine(parent, "Sticky custom channels", y, function()
    return cfg.stickyCustom == true
  end, function(value)
    Config().stickyCustom = value == true
  end)
  parent:SetHeight((-y) + 12)
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function()
  if FTK:IsEnabled(MODULE_ID) then
    Apply()
  end
end)

FTK:RegisterModule({
  id = MODULE_ID,
  name = "Sticky Channel Control",
  description = "Optional sticky whispers and sticky custom channels. Both default off. No full channel manager.",
  defaultEnabled = false,
  BuildOptions = BuildOptions,
  onEnable = function()
    pcall(events.RegisterEvent, events, "PLAYER_ENTERING_WORLD")
    Apply()
  end,
  onDisable = function()
    events:UnregisterAllEvents()
    Restore()
  end,
})
