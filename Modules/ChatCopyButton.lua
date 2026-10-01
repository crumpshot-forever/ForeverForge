--[[
  Chat Copy Button. Adds a small Copy button on the default chat frame.
  Clicking it opens a selectable edit box with recent chat text so you
  can copy with Ctrl+C. Own enable switch. No skins, Prat, or channel
  manager.
]]

local FTK = ForeverForge
if not FTK then
  error("ForeverForge: Core.lua must load before Modules/ChatCopyButton.lua")
end

local MODULE_ID = "ChatCopyButton"
local MAX_LINES = 200
local COPY_WIDTH = 520
local COPY_HEIGHT = 360

local button = nil
local copyFrame = nil
local hooked = false

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

local function StripColors(text)
  if type(text) ~= "string" then
    return ""
  end
  local ok, cleaned = pcall(function()
    local s = text
    s = s:gsub("|c%x%x%x%x%x%x%x%x", "")
    s = s:gsub("|r", "")
    s = s:gsub("|H.-|h(.-)|h", "%1")
    s = s:gsub("|T.-|t", "")
    s = s:gsub("|A.-|a", "")
    s = s:gsub("||", "|")
    return s
  end)
  if ok and type(cleaned) == "string" and not IsSecret(cleaned) then
    return cleaned
  end
  return text
end

local function ActiveChatFrame()
  local frame = _G.SELECTED_CHAT_FRAME or _G.DEFAULT_CHAT_FRAME or _G.ChatFrame1
  if type(frame) == "table" then
    return frame
  end
  return nil
end

local function CollectLines(chatFrame)
  local lines = {}
  if type(chatFrame) ~= "table" then
    return lines
  end
  local num = nil
  if type(chatFrame.GetNumMessages) == "function" then
    local ok, value = pcall(chatFrame.GetNumMessages, chatFrame)
    if ok and type(value) == "number" and not IsSecret(value) then
      num = value
    end
  end
  if not num or num < 1 then
    return lines
  end
  local start = num - MAX_LINES + 1
  if start < 1 then
    start = 1
  end
  local i
  for i = start, num do
    local text = nil
    if type(chatFrame.GetMessageInfo) == "function" then
      local ok, msg = pcall(chatFrame.GetMessageInfo, chatFrame, i)
      if ok then
        text = PlainString(msg)
      end
    end
    if text then
      lines[#lines + 1] = StripColors(text)
    end
  end
  return lines
end

local function EnsureCopyFrame()
  if copyFrame then
    return copyFrame
  end
  local frame = CreateFrame("Frame", "ForeverForgeChatCopyFrame", UIParent, "BackdropTemplate")
  if not frame.SetBackdrop then
    frame = CreateFrame("Frame", "ForeverForgeChatCopyFrame", UIParent)
  end
  frame:SetSize(COPY_WIDTH, COPY_HEIGHT)
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

  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", 0, -16)
  title:SetText("Chat Copy")

  local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  hint:SetPoint("TOP", title, "BOTTOM", 0, -4)
  hint:SetText("Select text and press Ctrl+C, then Escape to close.")

  local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 20, -48)
  scroll:SetPoint("BOTTOMRIGHT", -36, 40)

  local edit = CreateFrame("EditBox", nil, scroll)
  edit:SetMultiLine(true)
  edit:SetFontObject("GameFontHighlightSmall")
  edit:SetWidth(COPY_WIDTH - 60)
  edit:SetAutoFocus(false)
  edit:EnableMouse(true)
  edit:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
    frame:Hide()
  end)
  scroll:SetScrollChild(edit)
  frame.edit = edit

  local close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  if not close.SetText then
    close = CreateFrame("Button", nil, frame)
    close:SetSize(80, 22)
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

  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

  copyFrame = frame
  return frame
end

local function ShowCopy()
  local chat = ActiveChatFrame()
  local lines = CollectLines(chat)
  local frame = EnsureCopyFrame()
  local text = table.concat(lines, "\n")
  if text == "" then
    text = "(No recent chat lines available on this frame.)"
  end
  frame.edit:SetText(text)
  frame.edit:HighlightText(0, 0)
  frame.edit:SetFocus()
  frame.edit:HighlightText()
  frame:Show()
end

local function EnsureButton()
  if button then
    return button
  end
  local parent = _G.ChatFrame1ButtonFrame or _G.ChatFrame1 or UIParent
  local btn = CreateFrame("Button", "ForeverForgeChatCopyButton", parent)
  btn:SetSize(24, 24)
  if _G.ChatFrame1Tab then
    btn:SetPoint("LEFT", _G.ChatFrame1Tab, "RIGHT", 4, 0)
  else
    btn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -2, 2)
  end
  btn:SetNormalTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up")
  btn:SetPushedTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up")
  btn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
  btn:SetScript("OnEnter", function(self)
    if GameTooltip then
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText("Copy chat")
      GameTooltip:AddLine("Opens recent chat text for Ctrl+C.", 1, 1, 1, true)
      GameTooltip:Show()
    end
  end)
  btn:SetScript("OnLeave", function()
    if GameTooltip then
      GameTooltip:Hide()
    end
  end)
  btn:SetScript("OnClick", function()
    if FTK:IsEnabled(MODULE_ID) then
      ShowCopy()
    end
  end)
  button = btn
  return btn
end

local function Apply()
  local btn = EnsureButton()
  if FTK:IsEnabled(MODULE_ID) then
    btn:Show()
  else
    btn:Hide()
    if copyFrame then
      copyFrame:Hide()
    end
  end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_ENTERING_WORLD" or event == "UPDATE_LOADED" then
    if FTK:IsEnabled(MODULE_ID) then
      Apply()
    end
  end
end)

FTK:RegisterModule({
  id = MODULE_ID,
  name = "Chat Copy Button",
  description = "Adds a Copy button near chat tabs. Opens a selectable box of recent chat text for Ctrl+C.",
  defaultEnabled = false,
  onEnable = function()
    pcall(events.RegisterEvent, events, "PLAYER_ENTERING_WORLD")
    Apply()
  end,
  onDisable = function()
    events:UnregisterAllEvents()
    if button then
      button:Hide()
    end
    if copyFrame then
      copyFrame:Hide()
    end
  end,
})
