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

local function BuildPage(page, parent)
  local bars = _G.ForeverForgeDruid
  if bars and type(bars.BuildOptions) == "function" then
    bars.BuildOptions(page, parent)
  end
  local cat = _G.ForeverForgeDruidCat
  if cat and type(cat.BuildOptions) == "function" then
    cat.BuildOptions(page, parent)
  end
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
    description = "Mana in Bear. Cat Bar in Cat.",
    builder = BuildPage,
  })
  local bars = _G.ForeverForgeDruid
  if bars and type(bars.Start) == "function" then
    bars.Start()
  end
  local cat = _G.ForeverForgeDruidCat
  if cat and type(cat.Start) == "function" then
    cat.Start()
  end
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
