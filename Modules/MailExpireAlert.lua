--[[
  Mail Expire Alert. On login, posts a local chat line when any recorded
  alt has mailbox mail that will expire in fewer than N days (default 3).
  Snapshots earliest expiry per character when the mailbox closes.
  Multi-alt aware via name-realm keys in module SavedVariables config.
]]

local FTK = ForeverForge
if not FTK then
  error("ForeverForge: Core.lua must load before Modules/MailExpireAlert.lua")
end

local MODULE_ID = "MailExpireAlert"
local DEFAULT_WARN_DAYS = 3

local frame = CreateFrame("Frame")
local warnedThisLogin = false

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
  if type(cfg.warnDays) ~= "number" or cfg.warnDays < 1 then
    cfg.warnDays = DEFAULT_WARN_DAYS
  end
  if type(cfg.mailByChar) ~= "table" then
    cfg.mailByChar = {}
  end
  return cfg
end

local function Now()
  if type(time) ~= "function" then
    return 0
  end
  local ok, value = pcall(time)
  return ok and PlainNumber(value) or 0
end

local function CharKey()
  local name, realm
  if UnitName then
    local ok, n = pcall(UnitName, "player")
    if ok then
      name = PlainString(n)
    end
  end
  if GetNormalizedRealmName then
    local ok, r = pcall(GetNormalizedRealmName)
    if ok then
      realm = PlainString(r)
    end
  end
  if not realm and GetRealmName then
    local ok, r = pcall(GetRealmName)
    if ok then
      realm = PlainString(r)
    end
  end
  if not name then
    return nil
  end
  if realm then
    realm = realm:gsub("%s+", "")
    return name .. "-" .. realm
  end
  return name
end

local function InboxCount()
  if type(GetInboxNumItems) ~= "function" then
    return 0
  end
  local ok, num = pcall(GetInboxNumItems)
  return ok and PlainNumber(num) or 0
end

local function SnapshotInbox(fromClose)
  if not FTK:IsEnabled(MODULE_ID) then
    return
  end
  local key = CharKey()
  if not key then
    return
  end
  local cfg = Config()
  local num = InboxCount()
  if num <= 0 then
    -- MAIL_CLOSED often clears the inbox API before the handler runs.
    -- A real empty inbox already cleared the snapshot on MAIL_INBOX_UPDATE.
    if not fromClose then
      cfg.mailByChar[key] = nil
    end
    return
  end
  if type(GetInboxHeaderInfo) ~= "function" then
    return
  end
  local soonestDays = nil
  local count = 0
  local index
  for index = 1, num do
    local ok, _, _, _, _, _, _, daysLeft = pcall(GetInboxHeaderInfo, index)
    if ok then
      daysLeft = PlainNumber(daysLeft)
      if daysLeft then
        count = count + 1
        if not soonestDays or daysLeft < soonestDays then
          soonestDays = daysLeft
        end
      end
    end
  end
  if not soonestDays or count <= 0 then
    cfg.mailByChar[key] = nil
    return
  end
  local now = Now()
  cfg.mailByChar[key] = {
    earliestExpiry = now + (soonestDays * 86400),
    count = count,
    snappedAt = now,
  }
end

local function DaysUntil(expiry)
  local now = Now()
  expiry = PlainNumber(expiry)
  if not expiry or now <= 0 then
    return nil
  end
  return (expiry - now) / 86400
end

local function FormatDays(days)
  days = PlainNumber(days)
  if not days then
    return "?"
  end
  if days < 0 then
    return "expired"
  end
  if days < 1 then
    local hours = math.floor(days * 24)
    if hours <= 0 then
      return "under 1 hour"
    end
    return hours .. "h"
  end
  local whole = math.floor(days * 10 + 0.5) / 10
  if whole == math.floor(whole) then
    return tostring(math.floor(whole)) .. "d"
  end
  return string.format("%.1fd", whole)
end

local function WarnIfNeeded()
  if warnedThisLogin or not FTK:IsEnabled(MODULE_ID) then
    return
  end
  warnedThisLogin = true
  local cfg = Config()
  local warnDays = PlainNumber(cfg.warnDays) or DEFAULT_WARN_DAYS
  local key, info
  local lines = {}
  for key, info in pairs(cfg.mailByChar) do
    if type(key) == "string" and type(info) == "table" then
      local remain = DaysUntil(info.earliestExpiry)
      if remain ~= nil and remain < warnDays then
        local count = PlainNumber(info.count) or 0
        local label = count == 1 and "1 letter" or (tostring(count) .. " letters")
        lines[#lines + 1] = key .. ": " .. label .. ", soonest " .. FormatDays(remain)
      end
    end
  end
  if #lines == 0 then
    return
  end
  table.sort(lines)
  FTK:Print("Mail Expire Alert: mail expires in under " .. tostring(warnDays) .. " day(s) —")
  local i
  for i = 1, #lines do
    FTK:Print("  " .. lines[i])
  end
end

local function BuildOptions(_, parent)
  local y = -4
  local note = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  note:SetPoint("TOPLEFT", 0, y)
  note:SetWidth(420)
  note:SetJustifyH("LEFT")
  note:SetWordWrap(true)
  note:SetText("On login, chat when any recorded character has mailbox mail expiring sooner than this many days. Snapshots update when you close that character's mailbox.")
  y = y - 48
  local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  label:SetPoint("TOPLEFT", 0, y)
  label:SetText("Warn within days")
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
  pcall(function() box:SetNumeric(true) end)
  box:SetText(tostring(Config().warnDays or DEFAULT_WARN_DAYS))
  local function SaveBox(self)
    local text = PlainString(self:GetText())
    local n = text and PlainNumber(tonumber(text)) or nil
    if n and n >= 1 and n <= 30 then
      Config().warnDays = math.floor(n)
    else
      Config().warnDays = DEFAULT_WARN_DAYS
      self:SetText(tostring(DEFAULT_WARN_DAYS))
    end
  end
  box:SetScript("OnEnterPressed", function(self)
    SaveBox(self)
    self:ClearFocus()
  end)
  box:SetScript("OnEditFocusLost", SaveBox)
  y = y - 32
  parent:SetHeight((-y) + 12)
end

frame:SetScript("OnEvent", function(_, event)
  if event == "MAIL_CLOSED" then
    SnapshotInbox(true)
    return
  end
  if event == "MAIL_INBOX_UPDATE" then
    -- Keep snapshot fresh while the mailbox is open.
    SnapshotInbox(false)
    return
  end
  if event == "PLAYER_ENTERING_WORLD" then
    if C_Timer and C_Timer.After then
      C_Timer.After(2, WarnIfNeeded)
    else
      WarnIfNeeded()
    end
  end
end)

FTK:RegisterModule({
  id = MODULE_ID,
  name = "Mail Expire Alert",
  description = "On login, chat if recorded alt mail expires within N days. Snapshots when you close the mailbox.",
  defaultEnabled = true,
  BuildOptions = BuildOptions,
  onEnable = function()
    Config()
    warnedThisLogin = false
    frame:RegisterEvent("MAIL_CLOSED")
    frame:RegisterEvent("MAIL_INBOX_UPDATE")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    if C_Timer and C_Timer.After then
      C_Timer.After(2, WarnIfNeeded)
    else
      WarnIfNeeded()
    end
  end,
  onDisable = function()
    frame:UnregisterAllEvents()
  end,
})
