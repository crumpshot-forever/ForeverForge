--[[
  Social Convenience. Four independent opt-in switches (all default OFF):
  Accept Summon, Accept Res, Decline Duels, BG Auto-Release.
  No party-invite auto-accept. Module master switch can stay on; each
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
  if C_PvP and C_PvP.IsBattleground then
    local ok, value = pcall(C_PvP.IsBattleground)
    if ok and not IsSecret(value) and value == true then
      return true
    end
  end
  if type(UnitInBattleground) == "function" then
    local ok, value = pcall(UnitInBattleground, "player")
    if ok and not IsSecret(value) and value then
      return true
    end
  end
  -- Classic: GetZonePVPInfo / IsActiveBattlefieldArena — treat instance type.
  if type(IsInInstance) == "function" then
    local ok, inInstance, instanceType = pcall(IsInInstance)
    if ok and inInstance == true and PlainString(instanceType) == "pvp" then
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
      if ok and PlainString(visible) then
        -- visible is the frame name when shown.
        local frameName = PlainString(visible)
        local popup = frameName and _G[frameName]
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
      if ok and shown == true then
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
  if type(C_SummonInfo) == "table" and C_SummonInfo.ConfirmSummon then
    local ok = pcall(C_SummonInfo.ConfirmSummon)
    if ok then
      return
    end
  end
  if type(ConfirmSummon) == "function" then
    if pcall(ConfirmSummon) then
      return
    end
  end
  ClickStaticPopup({ "CONFIRM_SUMMON", "CONFIRM_SUMMON_STARTING_AREA" }, 1)
end

local function AcceptRes()
  if not FTK:IsEnabled(MODULE_ID) or not Config().acceptRes then
    return
  end
  if type(AcceptResurrect) == "function" then
    if pcall(AcceptResurrect) then
      return
    end
  end
  ClickStaticPopup({
    "RESURRECT",
    "RESURRECT_NO_SICKNESS",
    "RESURRECT_NO_TIMER",
  }, 1)
end

local function DeclineDuel()
  if not FTK:IsEnabled(MODULE_ID) or not Config().declineDuels then
    return
  end
  if type(CancelDuel) == "function" then
    pcall(CancelDuel)
  end
end

local function BgRelease()
  if not FTK:IsEnabled(MODULE_ID) or not Config().bgAutoRelease then
    return
  end
  if not InBattleground() then
    return
  end
  local dead = false
  if type(UnitIsDeadOrGhost) == "function" then
    local ok, value = pcall(UnitIsDeadOrGhost, "player")
    if ok and not IsSecret(value) then
      dead = value == true
    end
  elseif type(UnitIsDead) == "function" then
    local ok, value = pcall(UnitIsDead, "player")
    if ok and not IsSecret(value) then
      dead = value == true
    end
  end
  if not dead then
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
  note:SetText("Each action is opt-in and off by default. Turn on only what you want. Party invites are never auto-accepted.")
  y = y - 40
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
  elseif event == "DUEL_REQUESTED" then
    Later(DeclineDuel)
  elseif event == "PLAYER_DEAD" then
    Later(BgRelease)
  elseif event == "AREA_SPIRIT_HEALER_IN_RANGE" then
    -- Optional spirit healer path; RepopMe still the BG release.
    Later(BgRelease)
  end
end)

FTK:RegisterModule({
  id = MODULE_ID,
  name = "Social Convenience",
  description = "Opt-in Accept Summon, Accept Res, Decline Duels, and BG Auto-Release. All off by default. No party-invite auto-accept.",
  -- Master switch default on so Configure checkboxes are reachable; each
  -- action still defaults OFF until the player opts in.
  defaultEnabled = true,
  BuildOptions = BuildOptions,
  onEnable = function()
    Config()
    local names = {
      "CONFIRM_SUMMON",
      "RESURRECT_REQUEST",
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
