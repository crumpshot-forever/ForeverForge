--[[
  Druid page for Forever Forge.

  The game still loads this addon for every class. On login it checks the
  player class and returns immediately for anyone who is not a Druid.
  Settings, when a Druid opens the page, live in Forever Forge's saved
  variables. This addon has none of its own.
]]

local PAGE_ID = "Druid"

local function PlayerClass()
  if type(UnitClass) ~= "function" then
    return nil
  end
  local ok, _, classFile = pcall(UnitClass, "player")
  if not ok or type(classFile) ~= "string" or classFile == "" then
    return nil
  end
  if type(issecretvalue) == "function" then
    local secretOk, secret = pcall(issecretvalue, classFile)
    if secretOk and secret == true then
      return nil
    end
  end
  return classFile
end

local function PlaceholderToggle(parent, y, cfg)
  local box = CreateFrame("CheckButton", nil, parent)
  box:SetSize(24, 24)
  box:SetPoint("TOPLEFT", 0, y)
  box:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
  box:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
  box:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
  box:SetChecked(cfg.placeholder == true)
  box:SetScript("OnClick", function(self)
    cfg.placeholder = self:GetChecked() == true
  end)
  local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  text:SetPoint("LEFT", box, "RIGHT", 4, 0)
  text:SetText("Placeholder toggle")
  return y - 28
end

local function BuildPage(page, parent)
  local host = _G.ForeverForge
  if not host or type(host.GetPageConfig) ~= "function" then
    return
  end
  local cfg = host:GetPageConfig(page.id)
  if type(cfg) ~= "table" then
    return
  end
  local note = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  note:SetPoint("TOPLEFT", 0, -4)
  note:SetWidth(420)
  note:SetJustifyH("LEFT")
  note:SetWordWrap(true)
  note:SetText("Placeholder. Druid tools will be added here once they are chosen.")
  PlaceholderToggle(parent, -40, cfg)
  parent:SetHeight(80)
end

local started = false

local function Start()
  if started then
    return
  end
  started = true
  if PlayerClass() ~= "DRUID" then
    return
  end
  local host = _G.ForeverForge
  if not host or type(host.RegisterPage) ~= "function" then
    return
  end
  host:RegisterPage({
    id = PAGE_ID,
    title = "Druid",
    order = 100,
    description = "Druid tools.",
    builder = BuildPage,
  })
end

if type(CreateFrame) ~= "function" then
  return
end

local gate = CreateFrame("Frame")
gate:RegisterEvent("PLAYER_LOGIN")
gate:SetScript("OnEvent", function(self)
  self:UnregisterAllEvents()
  self:SetScript("OnEvent", nil)
  Start()
end)

if type(IsLoggedIn) == "function" then
  local ok, logged = pcall(IsLoggedIn)
  if ok and logged == true then
    Start()
  end
end
