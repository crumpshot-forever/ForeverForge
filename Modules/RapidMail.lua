--[[
  Rapid Mail. Adds Open All on the default mailbox. Takes free mail (gold
  and attachments), skips COD and GM mail, throttles takes, and stops when
  bags are full. Does not replace the Blizzard mail UI.
]]

local FTK = ForeverForge
if not FTK then
  error("ForeverForge: Core.lua must load before Modules/RapidMail.lua")
end

local MODULE_ID = "RapidMail"
local THROTTLE = 0.35

local frame = CreateFrame("Frame")
local running = false
local session = 0
local openButton

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

local function Later(delay, callback)
  if C_Timer and C_Timer.After then
    C_Timer.After(delay, callback)
    return true
  end
  return false
end

local function ApiTrue(value)
  if IsSecret(value) then
    return false
  end
  return value == true or value == 1
end

local function MailOpen()
  local mail = _G.MailFrame
  if not mail or not mail.IsShown then
    return false
  end
  local ok, shown = pcall(mail.IsShown, mail)
  return ok and ApiTrue(shown)
end

local function BagCount()
  local last = 4
  if _G.NUM_BAG_SLOTS then
    local count = PlainNumber(_G.NUM_BAG_SLOTS)
    if count and count > last then
      last = count
    end
  end
  return last
end

local function FreeBagSlots()
  local free = 0
  local bag
  for bag = 0, BagCount() do
    if C_Container and C_Container.GetContainerNumFreeSlots then
      local ok, slots = pcall(C_Container.GetContainerNumFreeSlots, bag)
      slots = ok and PlainNumber(slots) or nil
      if slots then
        free = free + slots
      end
    elseif GetContainerNumFreeSlots then
      local ok, slots = pcall(GetContainerNumFreeSlots, bag)
      slots = ok and PlainNumber(slots) or nil
      if slots then
        free = free + slots
      end
    end
  end
  return free
end

local function InboxCount()
  if type(GetInboxNumItems) ~= "function" then
    return 0
  end
  local ok, num = pcall(GetInboxNumItems)
  return ok and PlainNumber(num) or 0
end

-- packageIcon, stationeryIcon, sender, subject, money, CODAmount, daysLeft,
-- hasItem, wasRead, wasReturned, textCreated, canReply, isGM
local function Header(index)
  if type(GetInboxHeaderInfo) ~= "function" then
    return nil
  end
  local ok, packageIcon, stationeryIcon, sender, subject, money, CODAmount, daysLeft, hasItem, wasRead, wasReturned, textCreated, canReply, isGM =
    pcall(GetInboxHeaderInfo, index)
  if not ok then
    return nil
  end
  return {
    sender = PlainString(sender),
    subject = PlainString(subject),
    money = PlainNumber(money) or 0,
    -- A secret COD amount is not safe to treat as free mail.
    codUnsafe = IsSecret(CODAmount),
    CODAmount = PlainNumber(CODAmount) or 0,
    daysLeft = PlainNumber(daysLeft),
    hasItem = hasItem == true or hasItem == 1 or (PlainNumber(hasItem) or 0) > 0,
    isGM = ApiTrue(isGM),
  }
end

local function AttachmentCount(index)
  if type(GetInboxNumAttachments) == "function" then
    local ok, count = pcall(GetInboxNumAttachments, index)
    count = ok and PlainNumber(count) or nil
    if count then
      return count
    end
  end
  -- Classic often has up to ATTACHMENTS_MAX_RECEIVE (16) slots; probe links.
  local maxSlots = PlainNumber(_G.ATTACHMENTS_MAX_RECEIVE) or 16
  local n = 0
  local slot
  if type(GetInboxItemLink) == "function" then
    for slot = 1, maxSlots do
      local ok, link = pcall(GetInboxItemLink, index, slot)
      if ok and PlainString(link) then
        n = n + 1
      end
    end
  end
  return n
end

local function TakeMoney(index)
  if type(TakeInboxMoney) ~= "function" then
    return false
  end
  return pcall(TakeInboxMoney, index)
end

local function TakeAttachments(index)
  if type(AutoLootMailItem) == "function" then
    local ok = pcall(AutoLootMailItem, index)
    if ok then
      return true
    end
  end
  if type(TakeInboxItem) ~= "function" then
    return false
  end
  -- One slot per tick. Taking every slot in one frame stalls the mailbox.
  local maxSlots = PlainNumber(_G.ATTACHMENTS_MAX_RECEIVE) or 16
  local slot = 1
  if type(GetInboxItemLink) == "function" then
    local probe
    for probe = 1, maxSlots do
      local ok, link = pcall(GetInboxItemLink, index, probe)
      if ok and PlainString(link) then
        slot = probe
        break
      end
    end
  end
  return pcall(TakeInboxItem, index, slot)
end

local function DeleteEmpty(index)
  local info = Header(index)
  if not info then
    return false
  end
  if info.money > 0 or info.hasItem or info.CODAmount > 0 or info.isGM then
    return false
  end
  if type(DeleteInboxItem) ~= "function" then
    return false
  end
  return pcall(DeleteInboxItem, index)
end

local function Stop(reason)
  running = false
  session = session + 1
  if reason then
    FTK:Print("Rapid Mail: " .. reason)
  end
end

local ProcessNext

ProcessNext = function(token)
  if token ~= session or not FTK:IsEnabled(MODULE_ID) then
    running = false
    return
  end
  if not MailOpen() then
    Stop(nil)
    return
  end

  local num = InboxCount()
  if num <= 0 then
    Stop("inbox empty.")
    return
  end

  -- Walk high to low so taking/deleting does not shift unprocessed indices.
  local index
  for index = num, 1, -1 do
    local info = Header(index)
    if info then
      if info.isGM then
        -- Leave GM mail alone.
      elseif info.codUnsafe or info.CODAmount > 0 then
        -- Leave COD alone.
      else
        if info.money > 0 then
          TakeMoney(index)
          if not Later(THROTTLE, function()
            ProcessNext(token)
          end) then
            ProcessNext(token)
          end
          return
        end
        if info.hasItem or AttachmentCount(index) > 0 then
          local free = FreeBagSlots()
          if free < 1 then
            Stop("bags full — stopped.")
            return
          end
          TakeAttachments(index)
          if not Later(THROTTLE, function()
            ProcessNext(token)
          end) then
            ProcessNext(token)
          end
          return
        end
        -- Empty readable mail: delete to clear the inbox.
        if DeleteEmpty(index) then
          if not Later(THROTTLE, function()
            ProcessNext(token)
          end) then
            ProcessNext(token)
          end
          return
        end
      end
    end
  end

  Stop("done (COD/GM mail left untouched).")
end

local function StartOpenAll()
  if not FTK:IsEnabled(MODULE_ID) then
    return
  end
  if not MailOpen() then
    FTK:Print("Rapid Mail: open the mailbox first.")
    return
  end
  if running then
    return
  end
  if InboxCount() <= 0 then
    FTK:Print("Rapid Mail: inbox empty.")
    return
  end
  running = true
  session = session + 1
  local token = session
  FTK:Print("Rapid Mail: opening mail…")
  if not Later(0.1, function()
    ProcessNext(token)
  end) then
    ProcessNext(token)
  end
end

local function EnsureButton()
  if openButton or not CreateFrame then
    return
  end
  local parent = _G.InboxFrame or _G.MailFrame
  if not parent then
    return
  end
  local btn = CreateFrame("Button", "ForeverForgeRapidMailOpenAll", parent, "UIPanelButtonTemplate")
  if not btn then
    btn = CreateFrame("Button", "ForeverForgeRapidMailOpenAll", parent)
    btn:SetSize(80, 22)
  end
  btn:SetSize(90, 22)
  btn:SetText("Open All")
  -- Sit near the default inbox title / close area without covering tabs.
  if _G.InboxTitleText then
    btn:SetPoint("LEFT", _G.InboxTitleText, "RIGHT", 12, 0)
  else
    btn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -40, -32)
  end
  btn:SetScript("OnClick", function()
    StartOpenAll()
  end)
  openButton = btn
  if FTK:IsEnabled(MODULE_ID) and MailOpen() then
    btn:Show()
  else
    btn:Hide()
  end
end

local function UpdateButton()
  EnsureButton()
  if not openButton then
    return
  end
  if FTK:IsEnabled(MODULE_ID) and MailOpen() then
    openButton:Show()
  else
    openButton:Hide()
  end
end

frame:SetScript("OnEvent", function(_, event)
  if event == "MAIL_CLOSED" then
    Stop(nil)
    UpdateButton()
    return
  end
  if event == "MAIL_SHOW" or event == "MAIL_INBOX_UPDATE" then
    UpdateButton()
  end
end)

FTK:RegisterModule({
  id = MODULE_ID,
  name = "Rapid Mail",
  description = "Open All on the default mailbox. Skips COD and GM mail. Stops when bags are full.",
  defaultEnabled = true,
  onEnable = function()
    frame:RegisterEvent("MAIL_SHOW")
    frame:RegisterEvent("MAIL_CLOSED")
    frame:RegisterEvent("MAIL_INBOX_UPDATE")
    UpdateButton()
  end,
  onDisable = function()
    frame:UnregisterAllEvents()
    Stop(nil)
    if openButton then
      openButton:Hide()
    end
  end,
})
