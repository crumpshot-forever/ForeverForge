--[[
  Chat Fade Off. Disables fading (or sets a very long visible time) on
  the default ChatFrame1..N windows only. One enable switch. No font
  or background restyle.
]]

local FTK = ForeverForge
if not FTK then
  error("ForeverForge: Core.lua must load before Modules/ChatFadeOff.lua")
end

local MODULE_ID = "ChatFadeOff"
local MAX_FRAMES = 10
local LONG_VISIBLE = 120

local saved = {}

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

local function EachDefaultChat(callback)
  local i
  for i = 1, MAX_FRAMES do
    local frame = _G["ChatFrame" .. i]
    if type(frame) == "table" then
      callback(frame, i)
    end
  end
end

local function Remember(frame, index)
  if saved[index] then
    return
  end
  local entry = {}
  if type(frame.GetTimeVisible) == "function" then
    local ok, value = pcall(frame.GetTimeVisible, frame)
    if ok then
      entry.timeVisible = PlainNumber(value)
    end
  end
  if type(frame.GetFading) == "function" then
    local ok, value = pcall(frame.GetFading, frame)
    if ok and not IsSecret(value) then
      entry.fading = value == true
    end
  end
  saved[index] = entry
end

local function ApplyFrame(frame, index)
  Remember(frame, index)
  if type(frame.SetFading) == "function" then
    pcall(frame.SetFading, frame, false)
  end
  if type(frame.SetTimeVisible) == "function" then
    pcall(frame.SetTimeVisible, frame, LONG_VISIBLE)
  end
end

local function RestoreFrame(frame, index)
  local entry = saved[index]
  if not entry then
    return
  end
  if entry.fading ~= nil and type(frame.SetFading) == "function" then
    pcall(frame.SetFading, frame, entry.fading)
  end
  if entry.timeVisible ~= nil and type(frame.SetTimeVisible) == "function" then
    pcall(frame.SetTimeVisible, frame, entry.timeVisible)
  end
end

local function Apply()
  EachDefaultChat(ApplyFrame)
end

local function Restore()
  EachDefaultChat(RestoreFrame)
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function()
  if FTK:IsEnabled(MODULE_ID) then
    Apply()
  end
end)

FTK:RegisterModule({
  id = MODULE_ID,
  name = "Chat Fade Off",
  description = "Turns off (or greatly extends) message fade on the default chat frames only.",
  defaultEnabled = false,
  onEnable = function()
    pcall(events.RegisterEvent, events, "PLAYER_ENTERING_WORLD")
    Apply()
  end,
  onDisable = function()
    events:UnregisterAllEvents()
    Restore()
  end,
})
