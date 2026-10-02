--[[
  Quick Accept. Five independent opt-in switches (all default OFF):
  Accept Summon, Accept Res, auto-accept party invites, Decline Duels,
  and BG Auto-Release. The module master switch can stay on; each
  action is gated by its own Configure checkbox.
]]

local FTK = ForeverForge
if not FTK then
  error("ForeverForge: Core.lua must load before Modules/SocialConvenience.lua")
end

local MODULE_ID = "SocialConvenience"

local frame = CreateFrame("Frame")

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

-- Older clients return 1 for yes. Modern clients return true.
local function ApiTrue(value)
  return (not IsSecret(value)) and (value == true or value == 1)
end

local function Config()
  local cfg = FTK:GetConfig(MODULE_ID)
  if cfg.acceptSummon == nil then
    cfg.acceptSummon = false
  end
  if cfg.acceptRes == nil then
    cfg.acceptRes = false
  end
  if cfg.declineDuels == nil then
    cfg.declineDuels = false
  end
  if cfg.bgAutoRelease == nil then
    cfg.bgAutoRelease = false
  end
  if cfg.acceptParty == nil then
    cfg.acceptParty = false
  end
  return cfg
end

local function Later(callback)
  if C_Timer and C_Timer.After then
    C_Timer.After(0.1, callback)
    return
  end
  callback()
end

local function InBattleground()
  -- "pvp" is a battleground. Any other known instance type is not, including
  -- the open world. UnitInBattleground may return 0, and 0 is truthy in Lua.
  if type(IsInInstance) == "function" then
    local ok, inInstance, instanceType = pcall(IsInInstance)
    if ok then
      local kind = PlainString(instanceType)
      if kind == "pvp" and ApiTrue(inInstance) then
        return true
      end
      if kind then
        return false
      end
    end
  end
  if C_PvP and type(C_PvP.IsBattleground) == "function" then
    local ok, value = pcall(C_PvP.IsBattleground)
    if ok and ApiTrue(value) then
      return true
    end
  end
  if type(InActiveBattlefield) == "function" then
    local ok, value = pcall(InActiveBattlefield)
    if ok and ApiTrue(value) then
      return true
    end
  end
  if type(UnitInBattleground) == "function" then
    local ok, value = pcall(UnitInBattleground, "player")
    -- nil means outside a battleground. A number, including 0, means inside one.
    if ok and PlainNumber(value) ~= nil then
      return true
    end
  end
  return false
end

local function ClickStaticPopup(whichList, buttonIndex)
  buttonIndex = buttonIndex or 1
  if type(StaticPopup_Visible) == "function" and type(StaticPopup_OnClick) == "function" then
    local i
    for i = 1, #(whichList or {}) do
      local which = whichList[i]
      local ok, visible = pcall(StaticPopup_Visible, which)
      if ok and visible and not IsSecret(visible) then
        -- Classic returns the frame name. Newer builds return the frame.
        local popup = nil
        local frameName = PlainString(visible)
        if frameName then
          popup = _G[frameName]
        elseif type(visible) == "table" then
          popup = visible
        end
        if popup then
          pcall(StaticPopup_OnClick, popup, buttonIndex)
          return true
        end
      end
    end
  end
  -- Fallback: walk StaticPopup1-4.
  local i
  for i = 1, 4 do
    local popup = _G["StaticPopup" .. i]
    if popup and popup.IsShown then
      local ok, shown = pcall(popup.IsShown, popup)
      if ok and ApiTrue(shown) then
        local which = PlainString(popup.which)
        local j
        for j = 1, #(whichList or {}) do
          if which == whichList[j] then
            local btn = popup["button" .. buttonIndex] or _G["StaticPopup" .. i .. "Button" .. buttonIndex]
            if btn and btn.Click then
              pcall(btn.Click, btn)
              return true
            end
            if type(StaticPopup_OnClick) == "function" then
              pcall(StaticPopup_OnClick, popup, buttonIndex)
              return true
            end
          end
        end
      end
    end
  end
  return false
end

local function AcceptSummon()
  if not FTK:IsEnabled(MODULE_ID) or not Config().acceptSummon then
    return
  end
  if type(C_SummonInfo) == "table" and type(C_SummonInfo.ConfirmSummon) == "function" then
    pcall(C_SummonInfo.ConfirmSummon)
  end
  if type(ConfirmSummon) == "function" then
    pcall(ConfirmSummon)
  end
  -- A successful pcall only means the call did not throw.
  ClickStaticPopup({ "CONFIRM_SUMMON" }, 1)
end

local function AcceptRes()
  if not FTK:IsEnabled(MODULE_ID) or not Config().acceptRes then
    return
  end
  if type(AcceptResurrect) == "function" then
    pcall(AcceptResurrect)
  end
  ClickStaticPopup({
    "RESURRECT",
    "RESURRECT_NO_SICKNESS",
    "RESURRECT_NO_TIMER",
  }, 1)
end

local function AcceptParty()
  if not FTK:IsEnabled(MODULE_ID) or not Config().acceptParty then
    return
  end
  if type(AcceptGroup) == "function" then
    pcall(AcceptGroup)
  end
  -- Button 1 is Accept. AcceptGroup does not always close the dialog.
  ClickStaticPopup({ "PARTY_INVITE" }, 1)
  if type(StaticPopup_Hide) == "function" then
    pcall(StaticPopup_Hide, "PARTY_INVITE")
  end
end

local function DeclineDuel()
  if not FTK:IsEnabled(MODULE_ID) or not Config().declineDuels then
    return
  end
  if type(CancelDuel) == "function" then
    pcall(CancelDuel)
  end
  -- Button 1 accepts the duel. Button 2 is Decline.
  ClickStaticPopup({ "DUEL_REQUESTED" }, 2)
end

local function PlayerIsDead()
  if type(UnitIsDeadOrGhost) == "function" then
    local ok, value = pcall(UnitIsDeadOrGhost, "player")
    if ok and ApiTrue(value) then
      return true
    end
    if ok and not IsSecret(value) and not ApiTrue(value) then
      return false
    end
  end
  if type(UnitIsDead) == "function" then
    local ok, value = pcall(UnitIsDead, "player")
    if ok and ApiTrue(value) then
      return true
    end
  end
  if type(UnitIsGhost) == "function" then
    local ok, value = pcall(UnitIsGhost, "player")
    if ok and ApiTrue(value) then
      return true
    end
  end
  return false
end

local function BgRelease(fromDeath)
  if not FTK:IsEnabled(MODULE_ID) or not Config().bgAutoRelease then
    return
  end
  if not InBattleground() then
    return
  end
  -- PLAYER_DEAD is the death. The unit flag can still read as alive for a moment.
  if not fromDeath and not PlayerIsDead() then
    return
  end
  if type(RepopMe) == "function" then
    pcall(RepopMe)
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
    setter(ApiTrue(self:GetChecked()))
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
  note:SetText("Each action is opt-in and off by default. Turn on only what you want.")
  y = y - 32
  local cfg = Config()
  y = CheckLine(parent, "Accept Summon", y, function()
    return cfg.acceptSummon == true
  end, function(value)
    Config().acceptSummon = value == true
  end)
  y = CheckLine(parent, "Accept Res", y, function()
    return cfg.acceptRes == true
  end, function(value)
    Config().acceptRes = value == true
  end)
  y = CheckLine(parent, "Auto accept party invites", y, function()
    return cfg.acceptParty == true
  end, function(value)
    Config().acceptParty = value == true
  end)
  y = CheckLine(parent, "Decline Duels", y, function()
    return cfg.declineDuels == true
  end, function(value)
    Config().declineDuels = value == true
  end)
  y = CheckLine(parent, "BG Auto-Release", y, function()
    return cfg.bgAutoRelease == true
  end, function(value)
    Config().bgAutoRelease = value == true
  end)
  parent:SetHeight((-y) + 12)
end

frame:SetScript("OnEvent", function(_, event, ...)
  if not FTK:IsEnabled(MODULE_ID) then
    return
  end
  if event == "CONFIRM_SUMMON" then
    Later(AcceptSummon)
  elseif event == "RESURRECT_REQUEST" then
    Later(AcceptRes)
  elseif event == "PARTY_INVITE_REQUEST" then
    Later(AcceptParty)
  elseif event == "DUEL_REQUESTED" then
    Later(DeclineDuel)
  elseif event == "PLAYER_DEAD" then
    Later(function()
      BgRelease(true)
    end)
  elseif event == "AREA_SPIRIT_HEALER_IN_RANGE" then
    Later(function()
      BgRelease(false)
    end)
  end
end)

FTK:RegisterModule({
  id = MODULE_ID,
  name = "Quick Accept",
  description = "Opt-in Accept Summon, Accept Res, party invites, Decline Duels, and BG Auto-Release. All off by default.",
  -- Master switch default on so Configure checkboxes are reachable; each
  -- action still defaults OFF until the player opts in.
  defaultEnabled = true,
  BuildOptions = BuildOptions,
  onEnable = function()
    Config()
    local names = {
      "CONFIRM_SUMMON",
      "RESURRECT_REQUEST",
      "PARTY_INVITE_REQUEST",
      "DUEL_REQUESTED",
      "PLAYER_DEAD",
      "AREA_SPIRIT_HEALER_IN_RANGE",
    }
    local i
    for i = 1, #names do
      pcall(frame.RegisterEvent, frame, names[i])
    end
  end,
  onDisable = function()
    frame:UnregisterAllEvents()
  end,
})
