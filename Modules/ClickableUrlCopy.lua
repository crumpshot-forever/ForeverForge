--[[
  Clickable URL Copy. Turns http(s):// links and common Discord invite
  forms in chat into clickable hyperlinks that open a copy popup.
  Never launches a browser. One enable switch.
]]

local FTK = ForeverForge
if not FTK then
  error("ForeverForge: Core.lua must load before Modules/ClickableUrlCopy.lua")
end

local MODULE_ID = "ClickableUrlCopy"
local LINK_TYPE = "ffurl"
local popup = nil
local filterInstalled = false
local itemRefHooked = false
local originalItemRef = nil

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

-- Match http(s) URLs and discord.gg / discord.com/invite forms.
local URL_PATTERN = "([Hh][Tt][Tt][Pp][Ss]?://[%w%-%._~:/%?#%[%]@!$&'()*+,;=%%]+)"
local DISCORD_PATTERN = "([Dd][Ii][Ss][Cc][Oo][Rr][Dd]%.[Gg][Gg]/[%w%-]+)"
local DISCORD_INVITE_PATTERN = "([Dd][Ii][Ss][Cc][Oo][Rr][Dd]%.[Cc][Oo][Mm]/[Ii][Nn][Vv][Ii][Tt][Ee]/[%w%-]+)"

local function MakeLink(url)
  local safe = PlainString(url)
  if not safe then
    return url
  end
  -- Escape | in URL for hyperlink payload; display stays readable.
  local payload = safe:gsub("|", "||")
  return "|cff00ccff|H" .. LINK_TYPE .. ":" .. payload .. "|h[" .. safe .. "]|h|r"
end

local function AlreadyLinked(text)
  return type(text) == "string" and text:find("|H" .. LINK_TYPE .. ":", 1, true) ~= nil
end

local function Linkify(text)
  local s = PlainString(text)
  if not s or AlreadyLinked(s) then
    return text
  end
  local ok, result = pcall(function()
    local out = s
    -- Skip spans already inside |H...|h by only rewriting plain URLs.
    out = out:gsub(URL_PATTERN, function(url)
      return MakeLink(url)
    end)
    -- Discord short forms without scheme (avoid double-link if http already wrapped).
    out = out:gsub(DISCORD_PATTERN, function(url)
      if out:find("|H" .. LINK_TYPE .. ":", 1, true) and out:find(url, 1, true) then
        -- If this exact token is already inside an ffurl link, leave it.
        local linked = "|H" .. LINK_TYPE .. ":" .. url
        if out:find(linked, 1, true) then
          return url
        end
      end
      return MakeLink(url)
    end)
    out = out:gsub(DISCORD_INVITE_PATTERN, function(url)
      local linked = "|H" .. LINK_TYPE .. ":" .. url
      if out:find(linked, 1, true) then
        return url
      end
      return MakeLink(url)
    end)
    return out
  end)
  if ok and type(result) == "string" and not IsSecret(result) then
    return result
  end
  return text
end

local function EnsurePopup()
  if popup then
    return popup
  end
  local frame = CreateFrame("Frame", "ForeverForgeUrlCopyPopup", UIParent)
  frame:SetSize(420, 120)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("DIALOG")
  frame:Hide()
  pcall(function()
    if frame.SetBackdrop then
      frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
      })
    end
  end)

  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOP", 0, -14)
  title:SetText("Copy link (Ctrl+C) — browser not opened")

  local edit = CreateFrame("EditBox", nil, frame)
  edit:SetSize(360, 24)
  edit:SetPoint("TOP", title, "BOTTOM", 0, -12)
  edit:SetFontObject("GameFontHighlight")
  edit:SetAutoFocus(false)
  edit:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
    frame:Hide()
  end)
  frame.edit = edit

  local close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  if not close.SetText then
    close = CreateFrame("Button", nil, frame)
    local label = close:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("CENTER")
    label:SetText("Close")
    close:SetFontString(label)
  end
  close:SetSize(80, 22)
  close:SetPoint("BOTTOM", 0, 14)
  if close.SetText then
    close:SetText("Close")
  end
  close:SetScript("OnClick", function()
    frame:Hide()
  end)

  popup = frame
  return frame
end

local function ShowCopy(url)
  local safe = PlainString(url)
  if not safe then
    return
  end
  safe = safe:gsub("||", "|")
  local frame = EnsurePopup()
  frame.edit:SetText(safe)
  frame.edit:HighlightText()
  frame.edit:SetFocus()
  frame:Show()
  -- Prefer clipboard APIs when present; still show the box for Forever gaps.
  if type(C_ContentSharing) == "table" and C_ContentSharing.ShareText then
    pcall(C_ContentSharing.ShareText, safe)
  end
  -- Never call LaunchURL / SetBrowser / OpenURL.
end

local function ChatFilter(_, _, msg, ...)
  if not FTK:IsEnabled(MODULE_ID) then
    return false
  end
  local linked = Linkify(msg)
  if linked ~= msg then
    return false, linked, ...
  end
  return false
end

local FILTER_EVENTS = {
  "CHAT_MSG_SAY",
  "CHAT_MSG_YELL",
  "CHAT_MSG_WHISPER",
  "CHAT_MSG_WHISPER_INFORM",
  "CHAT_MSG_BN_WHISPER",
  "CHAT_MSG_BN_WHISPER_INFORM",
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
  "CHAT_MSG_SYSTEM",
  "CHAT_MSG_EMOTE",
  "CHAT_MSG_TEXT_EMOTE",
}

local function InstallFilter()
  if filterInstalled or type(ChatFrame_AddMessageEventFilter) ~= "function" then
    return
  end
  local i
  for i = 1, #FILTER_EVENTS do
    pcall(ChatFrame_AddMessageEventFilter, FILTER_EVENTS[i], ChatFilter)
  end
  filterInstalled = true
end

local function RemoveFilter()
  if not filterInstalled or type(ChatFrame_RemoveMessageEventFilter) ~= "function" then
    return
  end
  local i
  for i = 1, #FILTER_EVENTS do
    pcall(ChatFrame_RemoveMessageEventFilter, FILTER_EVENTS[i], ChatFilter)
  end
  filterInstalled = false
end

local function OnItemRef(link, text, button, chatFrame)
  local plain = PlainString(link)
  if not plain then
    return
  end
  local prefix = LINK_TYPE .. ":"
  if plain:sub(1, #prefix) == prefix then
    local url = plain:sub(#prefix + 1)
    ShowCopy(url)
    return
  end
  if originalItemRef then
    return originalItemRef(link, text, button, chatFrame)
  end
end

local function HookItemRef()
  if itemRefHooked then
    return
  end
  if type(SetItemRef) == "function" then
    originalItemRef = SetItemRef
    _G.SetItemRef = function(link, text, button, chatFrame)
      local plain = PlainString(link)
      if plain and plain:sub(1, #LINK_TYPE + 1) == LINK_TYPE .. ":" then
        OnItemRef(link, text, button, chatFrame)
        return
      end
      return originalItemRef(link, text, button, chatFrame)
    end
    itemRefHooked = true
  end
end

local function UnhookItemRef()
  if itemRefHooked and originalItemRef then
    _G.SetItemRef = originalItemRef
    itemRefHooked = false
  end
  if popup then
    popup:Hide()
  end
end

FTK:RegisterModule({
  id = MODULE_ID,
  name = "Clickable URL Copy",
  description = "Makes http(s) and Discord invite links in chat clickable. Click opens a copy box; the browser is never opened.",
  defaultEnabled = false,
  onEnable = function()
    InstallFilter()
    HookItemRef()
  end,
  onDisable = function()
    RemoveFilter()
    UnhookItemRef()
  end,
})
