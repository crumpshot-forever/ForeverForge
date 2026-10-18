--[[
  Group Finder. Role and class filters on the Looking For Group window.
  A ticked role keeps listings that have that role. A ticked class keeps
  listings that include that class. Both together mean both must match.
  Delisted listings stay hidden. Starting a new search is blocked for
  addons, so the refresh button stays the game's own button.
]]

local FTK = ForeverForge
if not FTK then
  error("ForeverForge: Core.lua must load before Modules/GroupFinder.lua")
end

local MODULE_ID = "GroupFinder"
local LEVEL_SPAN = 5

local CLASS_FILTERS = {
  { "WARRIOR", "Wa" },
  { "PALADIN", "Pa" },
  { "HUNTER", "Hu" },
  { "ROGUE", "Ro" },
  { "PRIEST", "Pr" },
  { "SHAMAN", "Sh" },
  { "MAGE", "Ma" },
  { "WARLOCK", "Lo" },
  { "DRUID", "Dr" },
}

local function IsSecret(value)
  if value == nil or type(issecretvalue) ~= "function" then
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

local function SecretTable(value)
  if type(value) ~= "table" then
    return true
  end
  if IsSecret(value) then
    return true
  end
  if type(issecrettable) == "function" then
    local ok, secret = pcall(issecrettable, value)
    if ok and secret == true then
      return true
    end
  end
  return false
end

local function Config()
  local cfg = FTK:GetConfig(MODULE_ID)
  if cfg.hideDelisted == nil then
    cfg.hideDelisted = true
  end
  if cfg.nearLevel == nil then
    cfg.nearLevel = false
  end
  if type(cfg.roles) ~= "table" then
    cfg.roles = {}
  end
  if type(cfg.classes) ~= "table" then
    cfg.classes = {}
  end
  return cfg
end

local function ClassColor(className)
  local colors = _G.RAID_CLASS_COLORS
  local color = colors and colors[className]
  if type(color) == "table" then
    local red = PlainNumber(color.r)
    local green = PlainNumber(color.g)
    local blue = PlainNumber(color.b)
    if red and green and blue then
      return { red, green, blue }
    end
  end
  return { 1, 0.82, 0 }
end

local function ClassWanted(cfg)
  local classes = cfg.classes
  if type(classes) ~= "table" then
    return false
  end
  local className
  for className, on in pairs(classes) do
    if on == true then
      return true
    end
  end
  return false
end

local function RoleWanted(cfg)
  return cfg.roles.tank == true or cfg.roles.healer == true or cfg.roles.dps == true
end

local function ListingRoles(resultID, info)
  local members = PlainNumber(info.numMembers)
  if not members then
    return nil
  end
  if members <= 1 then
    local ok, member = pcall(C_LFGList.GetSearchResultPlayerInfo, resultID, 1)
    if not ok or SecretTable(member) then
      return nil
    end
    local roles = member.lfgRoles
    if SecretTable(roles) then
      return nil
    end
    return roles.tank == true, roles.healer == true, roles.dps == true
  end
  local ok, counts = pcall(C_LFGList.GetSearchResultMemberCounts, resultID)
  if not ok or SecretTable(counts) then
    return nil
  end
  local tank = PlainNumber(counts.TANK)
  local healer = PlainNumber(counts.HEALER)
  local dps = PlainNumber(counts.DAMAGER)
  if tank == nil and healer == nil and dps == nil then
    return nil
  end
  return (tank or 0) > 0, (healer or 0) > 0, (dps or 0) > 0
end

local function MemberClass(resultID, memberIndex)
  local ok, member = pcall(C_LFGList.GetSearchResultPlayerInfo, resultID, memberIndex)
  if not ok or SecretTable(member) then
    return nil
  end
  local className = member.classFilename
  if type(className) ~= "string" or className == "" or IsSecret(className) then
    return nil
  end
  return className
end

local function ListingClasses(resultID, info)
  local members = PlainNumber(info.numMembers) or 1
  if members < 1 then
    members = 1
  end
  if members > 10 then
    members = 10
  end
  local found = {}
  local saw = false
  local memberIndex
  for memberIndex = 1, members do
    local className = MemberClass(resultID, memberIndex)
    if className then
      found[className] = true
      saw = true
    end
  end
  if not saw then
    return nil
  end
  return found
end

local function ListingLevel(resultID, info)
  local members = PlainNumber(info.numMembers)
  if members == 1 then
    local ok, member = pcall(C_LFGList.GetSearchResultPlayerInfo, resultID, 1)
    if ok and not SecretTable(member) then
      return PlainNumber(member.level)
    end
    return nil
  end
  local ok, leader = pcall(C_LFGList.GetSearchResultLeaderInfo, resultID)
  if ok and not SecretTable(leader) then
    return PlainNumber(leader.level)
  end
  return nil
end

local function KeepResult(resultID, cfg)
  if type(C_LFGList) ~= "table" or type(C_LFGList.GetSearchResultInfo) ~= "function" then
    return true
  end
  local ok, info = pcall(C_LFGList.GetSearchResultInfo, resultID)
  if not ok or SecretTable(info) then
    return true
  end
  if info.hasSelf == true then
    return true
  end
  if cfg.hideDelisted and info.isDelisted == true then
    return false
  end
  if cfg.nearLevel then
    local mineOk, mine = pcall(UnitLevel, "player")
    mine = mineOk and PlainNumber(mine) or nil
    local theirs = ListingLevel(resultID, info)
    if mine and theirs and (theirs < mine - LEVEL_SPAN or theirs > mine + LEVEL_SPAN) then
      return false
    end
  end
  if RoleWanted(cfg) then
    local tank, healer, dps = ListingRoles(resultID, info)
    if tank == nil then
      return true
    end
    if cfg.roles.tank and tank then
      return true
    end
    if cfg.roles.healer and healer then
      return true
    end
    if cfg.roles.dps and dps then
      return true
    end
    return false
  end
  if ClassWanted(cfg) then
    local found = ListingClasses(resultID, info)
    if found == nil then
      return true
    end
    local className, on
    for className, on in pairs(cfg.classes) do
      if on == true and found[className] then
        return true
      end
    end
    return false
  end
  return true
end

local filtering = false

local function ApplyFilter(browse)
  if filtering or not FTK:IsEnabled(MODULE_ID) then
    return
  end
  local results = browse.results
  if SecretTable(results) then
    return
  end
  local cfg = Config()
  local kept = {}
  local index
  for index = 1, #results do
    local resultID = results[index]
    if KeepResult(resultID, cfg) then
      kept[#kept + 1] = resultID
    end
  end
  if #kept == #results then
    return
  end
  filtering = true
  browse.results = kept
  browse.totalResults = #kept
  if type(browse.UpdateResults) == "function" then
    pcall(browse.UpdateResults, browse)
  end
  filtering = false
end

local hooked = false

local function TryHook()
  if hooked then
    return true
  end
  local browse = _G.LFGBrowseFrame
  if type(browse) ~= "table" or type(browse.UpdateResultList) ~= "function" or type(hooksecurefunc) ~= "function" then
    return false
  end
  hooksecurefunc(browse, "UpdateResultList", function(self)
    ApplyFilter(self)
  end)
  hooked = true
  return true
end

local bar
local classBar
local boxes = {}
local classBoxes = {}

local function PaintBox(box, on)
  local label = box.label
  if not label then
    return
  end
  if on and box.onColor then
    label:SetTextColor(box.onColor[1], box.onColor[2], box.onColor[3])
  elseif on then
    label:SetTextColor(1, 0.82, 0)
  else
    label:SetTextColor(0.55, 0.55, 0.55)
  end
end

local function MakeCheck(parent, text, getter, setter, onColor)
  local box = CreateFrame("CheckButton", nil, parent)
  box:SetSize(18, 18)
  box:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
  box:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
  box:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
  local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  label:SetPoint("LEFT", box, "RIGHT", 1, 0)
  label:SetText(text)
  box.label = label
  box.onColor = onColor
  box:SetChecked(getter())
  PaintBox(box, getter())
  box:SetScript("OnClick", function(self)
    local on = self:GetChecked() == true
    setter(on)
    PaintBox(self, on)
    TryHook()
    local browse = _G.LFGBrowseFrame
    if browse and type(browse.UpdateResultList) == "function" then
      pcall(browse.UpdateResultList, browse)
    end
  end)
  return box, label
end

local function LayoutChecks(parent, list)
  local previous
  local index
  for index = 1, #list do
    local box = list[index]
    box:ClearAllPoints()
    if previous then
      local gap = 40
    if previous.label and type(previous.label.GetStringWidth) == "function" then
      local widthOk, width = pcall(previous.label.GetStringWidth, previous.label)
      width = widthOk and PlainNumber(width) or nil
      if width and width > 8 then
        gap = width + 10
      end
    end
    box:SetPoint("LEFT", previous, "RIGHT", gap, 0)
    else
      box:SetPoint("LEFT", parent, "LEFT", 0, 0)
    end
    previous = box
  end
end

local function EnsureBar()
  local browse = _G.LFGBrowseFrame
  local refresh = browse and browse.RefreshButton
  if not browse or not refresh or bar then
    return
  end
  bar = CreateFrame("Frame", nil, browse)
  bar:SetSize(280, 20)
  bar:SetPoint("TOPRIGHT", refresh, "BOTTOMRIGHT", 0, -4)
  classBar = CreateFrame("Frame", nil, browse)
  classBar:SetSize(430, 20)
  classBar:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -2)
  local cfg = Config()
  local specs = {
    { "Tank", function() return cfg.roles.tank == true end, function(on) cfg.roles.tank = on end },
    { "Heal", function() return cfg.roles.healer == true end, function(on) cfg.roles.healer = on end },
    { "DPS", function() return cfg.roles.dps == true end, function(on) cfg.roles.dps = on end },
    { "±5 lvl", function() return cfg.nearLevel == true end, function(on) cfg.nearLevel = on end },
  }
  local index
  for index = 1, #specs do
    boxes[index] = MakeCheck(bar, specs[index][1], specs[index][2], specs[index][3])
  end
  for index = 1, #CLASS_FILTERS do
    local className = CLASS_FILTERS[index][1]
    local label = CLASS_FILTERS[index][2]
    classBoxes[index] = MakeCheck(classBar, label, function()
      return cfg.classes[className] == true
    end, function(on)
      cfg.classes[className] = on
    end, ClassColor(className))
  end
  LayoutChecks(bar, boxes)
  LayoutChecks(classBar, classBoxes)
  if not FTK:IsEnabled(MODULE_ID) then
    bar:Hide()
    classBar:Hide()
  end
end

local function Tick()
  if not FTK:IsEnabled(MODULE_ID) then
    return
  end
  TryHook()
  EnsureBar()
end

local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", function()
  Tick()
end)

local function Start()
  TryHook()
  EnsureBar()
  if bar then
    bar:Show()
  end
  if classBar then
    classBar:Show()
  end
end

local function Stop()
  if bar then
    bar:Hide()
  end
  if classBar then
    classBar:Hide()
  end
  local browse = _G.LFGBrowseFrame
  if browse and type(browse.UpdateResultList) == "function" then
    pcall(browse.UpdateResultList, browse)
  end
end

FTK:RegisterModule({
  id = MODULE_ID,
  name = "Group Finder",
  description = "Role and class filters on the Looking For Group window. Tank, Heal, and DPS show listings with that role. The class row keeps listings that include that class. Both together must both match. Delisted listings stay hidden. ±5 lvl keeps people near your level.",
  defaultEnabled = true,
  onEnable = function()
    Start()
  end,
  onDisable = function()
    Stop()
  end,
})
