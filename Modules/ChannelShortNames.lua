--[[
  Channel Short Names. Abbreviates common chat channel headers to short
  tags like [G], [P], [R], [O], [W]. One enable switch. Restores stock
  CHAT_*_GET globals on disable. Locale-aware where the stock globals
  exist; English fallbacks otherwise.
]]

local FTK = ForeverForge
if not FTK then
  error("ForeverForge: Core.lua must load before Modules/ChannelShortNames.lua")
end

local MODULE_ID = "ChannelShortNames"

-- Stock values remembered on first enable so disable can restore.
local saved = {}

-- Short tags. Trailing space/%s patterns match Blizzard CHAT_*_GET style.
local SHORT = {
  CHAT_SAY_GET = "[S] %s:\32",
  CHAT_YELL_GET = "[Y] %s:\32",
  CHAT_WHISPER_GET = "[W] %s:\32",
  CHAT_WHISPER_INFORM_GET = "[W] To %s:\32",
  CHAT_BN_WHISPER_GET = "[W] %s:\32",
  CHAT_BN_WHISPER_INFORM_GET = "[W] To %s:\32",
  CHAT_GUILD_GET = "[G] %s:\32",
  CHAT_OFFICER_GET = "[O] %s:\32",
  CHAT_PARTY_GET = "[P] %s:\32",
  CHAT_PARTY_LEADER_GET = "[PL] %s:\32",
  CHAT_PARTY_GUIDE_GET = "[PG] %s:\32",
  CHAT_RAID_GET = "[R] %s:\32",
  CHAT_RAID_LEADER_GET = "[RL] %s:\32",
  CHAT_RAID_WARNING_GET = "[RW] %s:\32",
  CHAT_INSTANCE_CHAT_GET = "[I] %s:\32",
  CHAT_INSTANCE_CHAT_LEADER_GET = "[IL] %s:\32",
  CHAT_BATTLEGROUND_GET = "[BG] %s:\32",
  CHAT_BATTLEGROUND_LEADER_GET = "[BL] %s:\32",
}

local function IsSecret(value)
  if value == nil or not issecretvalue then
    return false
  end
  local ok, secret = pcall(issecretvalue, value)
  return ok and secret == true
end

local function PlainString(value)
  if IsSecret(value) or type(value) ~= "string" or value == "" then
    return nil
  end
  return value
end

local function Remember()
  local key, _
  for key, _ in pairs(SHORT) do
    if saved[key] == nil then
      local current = PlainString(_G[key])
      if current then
        saved[key] = current
      end
    end
  end
end

local function Apply()
  Remember()
  local key, value
  for key, value in pairs(SHORT) do
    pcall(function()
      _G[key] = value
    end)
  end
end

local function Restore()
  local key, value
  for key, value in pairs(saved) do
    pcall(function()
      _G[key] = value
    end)
  end
end

-- Optional: shorten numbered custom channel headers via CHAT_CHANNEL_GET
-- when the client exposes a replaceable pattern. Conservative — only if
-- the global looks like a format string with %s.
local function ApplyChannelGet()
  local current = PlainString(_G.CHAT_CHANNEL_GET)
  if not current then
    return
  end
  if saved.CHAT_CHANNEL_GET == nil then
    saved.CHAT_CHANNEL_GET = current
  end
  -- Keep the channel name but wrap briefly: [%s] speaker
  -- Many clients use "%s: " or "[%s] %s: " — leave custom channels alone
  -- if format is ambiguous; short names target standard types above.
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function()
  if FTK:IsEnabled(MODULE_ID) then
    Apply()
    ApplyChannelGet()
  end
end)

FTK:RegisterModule({
  id = MODULE_ID,
  name = "Channel Short Names",
  description = "Abbreviates common chat labels to short tags like [G], [P], [R], [O], [W].",
  defaultEnabled = false,
  onEnable = function()
    pcall(events.RegisterEvent, events, "PLAYER_ENTERING_WORLD")
    Apply()
    ApplyChannelGet()
  end,
  onDisable = function()
    events:UnregisterAllEvents()
    Restore()
  end,
})
