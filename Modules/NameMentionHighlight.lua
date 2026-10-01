--[[
  Name Mention Highlight. Highlights your own character name in public
  chat messages (case-insensitive word boundary). Optional sound on
  mention via Configure (default OFF). One module enable switch.
  No custom keyword lists.
]]

local FTK = ForeverForge
if not FTK then
  error("ForeverForge: Core.lua must load before Modules/NameMentionHighlight.lua")
end

local MODULE_ID = "NameMentionHighlight"
local HIGHLIGHT = "|cffffd100"
local HIGHLIGHT_END = "|r"
local SOUND_GAP = 1.0
local lastSound = 0
local filterInstalled = false
local cachedName = nil
local cachedLower = nil
local cachedPattern = nil

local PUBLIC_EVENTS = {
  "CHAT_MSG_SAY",
  "CHAT_MSG_YELL",
  "CHAT_MSG_GUILD",
  "CHAT_MSG_OFFICER",
  "CHAT_MSG_PARTY",
  "CHAT_MSG_PARTY_LEADER",
  "CHAT_MSG_RAID",
  "CHAT_MSG_RAID_LEADER",
  "CHAT_MSG_RAID_WARNING",
  "CHAT_MSG_INSTANCE_CHAT",
  "CHAT_MSG_INSTANCE_CHAT_LEADER",
  "CHAT_MSG_CHANNEL",
  "CHAT_MSG_EMOTE",
  "CHAT_MSG_TEXT_EMOTE",
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
  if cfg.playSound == nil then
    cfg.playSound = false
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
  if SOUNDKIT and SOUNDKIT.MAP_PING and PlayId(SOUNDKIT.MAP_PING) then
    return
  end
  if PlayId(3175) then
    return
  end
  PlayId(8960)
end

local function EscapePattern(text)
  return (text:gsub("(%W)", "%%%1"))
end

local function PlayerName()
  if not UnitName then
    return nil
  end
  local ok, name = pcall(UnitName, "player")
  if not ok then
    return nil
  end
  return PlainString(name)
end

local function RefreshNameCache()
  local name = PlayerName()
  if not name then
    cachedName = nil
    cachedLower = nil
    cachedPattern = nil
    return
  end
  if name == cachedName then
    return
  end
  cachedName = name
  local okLower, lower = pcall(string.lower, name)
  if okLower and type(lower) == "string" and not IsSecret(lower) then
    cachedLower = lower
  else
    cachedLower = name
  end
  -- Word-boundary style: non-alphanumeric or start/end.
  cachedPattern = "(%f[%w])(" .. EscapePattern(name) .. ")(%f[%W])"
end

local function HighlightText(msg)
  RefreshNameCache()
  if not cachedName or not cachedPattern then
    return msg, false
  end
  local s = PlainString(msg)
  if not s then
    return msg, false
  end
  -- Skip if name only appears inside hyperlinks (rough: between |H and |h).
  local hit = false
  local ok, result = pcall(function()
    -- Case-insensitive replace via lower scan, preserve original casing.
    local lowerOk, lowerMsg = pcall(string.lower, s)
    if not lowerOk or type(lowerMsg) ~= "string" or IsSecret(lowerMsg) then
      return s
    end
    local nameLower = cachedLower
    local nameLen = #cachedName
    local out = {}
    local i = 1
    local len = #s
    while i <= len do
      local found = lowerMsg:find(nameLower, i, true)
      if not found then
        out[#out + 1] = s:sub(i)
        break
      end
      -- Word boundary check on original indices.
      local before = found == 1 and "" or s:sub(found - 1, found - 1)
      local afterIdx = found + nameLen
      local after = afterIdx > len and "" or s:sub(afterIdx, afterIdx)
      local beforeOk = before == "" or not before:match("[%w]")
      local afterOk = after == "" or not after:match("[%w]")
      -- Avoid rewriting inside |c / |H sequences: if a '|' sits nearby uncanceled, skip.
      local sliceStart = s:sub(1, found - 1)
      local openH = select(2, sliceStart:gsub("|H", ""))
      local closeH = select(2, sliceStart:gsub("|h", ""))
      local inLink = openH > closeH
      if beforeOk and afterOk and not inLink then
        out[#out + 1] = s:sub(i, found - 1)
        out[#out + 1] = HIGHLIGHT .. s:sub(found, found + nameLen - 1) .. HIGHLIGHT_END
        hit = true
        i = found + nameLen
      else
        out[#out + 1] = s:sub(i, found)
        i = found + 1
      end
    end
    return table.concat(out)
  end)
  if ok and type(result) == "string" and not IsSecret(result) then
    return result, hit
  end
  return msg, false
end

local function ChatFilter(_, event, msg, author, ...)
  if not FTK:IsEnabled(MODULE_ID) then
    return false
  end
  -- Do not highlight our own outbound lines when author matches.
  local selfName = cachedName or PlayerName()
  local who = PlainString(author)
  if selfName and who then
    local ok1, a = pcall(string.lower, who)
    local ok2, b = pcall(string.lower, selfName)
    if ok1 and ok2 and a == b then
      return false
    end
  end
  local linked, hit = HighlightText(msg)
  if hit and Config().playSound == true then
    PlayCue()
  end
  if linked ~= msg then
    return false, linked, author, ...
  end
  return false
end

local function InstallFilter()
  if filterInstalled or type(ChatFrame_AddMessageEventFilter) ~= "function" then
    return
  end
  local i
  for i = 1, #PUBLIC_EVENTS do
    pcall(ChatFrame_AddMessageEventFilter, PUBLIC_EVENTS[i], ChatFilter)
  end
  filterInstalled = true
end

local function RemoveFilter()
  if not filterInstalled or type(ChatFrame_RemoveMessageEventFilter) ~= "function" then
    return
  end
  local i
  for i = 1, #PUBLIC_EVENTS do
    pcall(ChatFrame_RemoveMessageEventFilter, PUBLIC_EVENTS[i], ChatFilter)
  end
  filterInstalled = false
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
  note:SetText("Highlights your character name in public chat. Optional sound is off by default. No custom keyword list.")
  y = y - 40
  local cfg = Config()
  y = CheckLine(parent, "Play sound when mentioned", y, function()
    return cfg.playSound == true
  end, function(value)
    Config().playSound = value == true
  end)
  parent:SetHeight((-y) + 12)
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function()
  RefreshNameCache()
end)

FTK:RegisterModule({
  id = MODULE_ID,
  name = "Name Mention Highlight",
  description = "Highlights your character name in public chat. Optional sound on mention (default off).",
  defaultEnabled = false,
  BuildOptions = BuildOptions,
  onEnable = function()
    RefreshNameCache()
    InstallFilter()
    pcall(events.RegisterEvent, events, "PLAYER_ENTERING_WORLD")
    pcall(events.RegisterEvent, events, "PLAYER_LOGIN")
  end,
  onDisable = function()
    events:UnregisterAllEvents()
    RemoveFilter()
  end,
})
