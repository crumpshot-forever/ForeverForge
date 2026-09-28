--[[
  Forever Forge
  Master addon for independent in-game tools. This file is the registry,
  saved settings, and slash commands. It does not implement features.

  Add a feature in its own file, listed after Menu.lua in ForeverForge.toc.
  Call RegisterModule at file scope (not from inside onEnable):

    ForeverForge:RegisterModule({
      id = "BagSort",
      name = "Bag Sort",
      description = "Puts bags back in order.",
      defaultEnabled = false, -- first login only; the saved toggle wins after that
      onEnable = function(self)
        -- Runs on login, /reload, and when the player turns the feature on.
        -- GetConfig is safe from here on. Mutate the returned table; do not replace it.
        local cfg = ForeverForge:GetConfig(self.id)
      end,
      onDisable = function(self)
        -- Runs when the player turns the feature off. Not called on logout.
      end,
      -- Optional settings. Use one, not both. onConfigure wins if both are set.
      -- onConfigure = function(self) end, -- open the module's own window
      BuildOptions = function(self, parent)
        -- Parent is a frame inside the toolkit menu, under a Back button.
        -- Anchor controls to parent. If the page is tall, call parent:SetHeight(n).
      end,
    })

  Features must not require each other or FlowRider.
  Before reading combat, auras, health, or power, read
  ../FlowRider/docs/Forever-API-visibility.md. Secret values must not be
  compared, used as table keys, or formatted into logic.
]]

local ADDON = "ForeverForge"

local FTK = {}
_G.ForeverForge = FTK

-- Addon version is X.Y.Z. The Interface lines in the toc are the game client.
-- X stays 0 until the first public package, then 1. Raise X only when saved
-- settings would break, or a new Forever client era is certified.
-- Y goes up by 1 for a new tool, and Z returns to 0.
-- Z goes up by 1 for a fix or small change, and Y stays.
-- Keep this string identical to ## Version in ForeverForge.toc.
-- Publish a version by committing it and tagging vX.Y.Z on GitHub.
-- Do not rename the live ForeverForge folder.
FTK.VERSION = "1.0.6"
FTK.modules = {}
FTK.moduleOrder = {}

local function Trim(s)
  return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

function FTK.Plain(s)
  return (tostring(s or ""):gsub("|", "||"))
end

function FTK:Print(msg)
  local chat = _G.DEFAULT_CHAT_FRAME
  if chat and chat.AddMessage then
    chat:AddMessage("|cffe0c36aForever Forge|r: " .. self.Plain(msg))
  end
end

function FTK:InitDB()
  if self._dbReady then
    return
  end
  local db = _G.ForeverForgeDB
  if type(db) ~= "table" then
    db = {}
  end
  if type(db.minimap) ~= "table" then
    db.minimap = {}
  end
  if type(db.minimap.angle) ~= "number" then
    db.minimap.angle = 200
  end
  if type(db.menu) ~= "table" then
    db.menu = {}
  end
  if type(db.modules) ~= "table" then
    db.modules = {}
  end
  _G.ForeverForgeDB = db
  self.db = db
  self._dbReady = true
end

function FTK:RegisterModule(def)
  if type(def) ~= "table" then
    self:Print("RegisterModule needs a module table")
    return nil
  end
  local id = Trim(def.id)
  if id == "" then
    self:Print("RegisterModule needs an id")
    return nil
  end
  if not id:find("^[%a_][%w_]*$") then
    self:Print("Module id must use letters, numbers, and underscores: " .. id)
    return nil
  end
  if self.modules[id] then
    self:Print("Duplicate module id: " .. id)
    return nil
  end
  def.id = id
  if type(def.name) ~= "string" or def.name == "" then
    def.name = id
  end
  if type(def.description) ~= "string" then
    def.description = ""
  end
  def.defaultEnabled = def.defaultEnabled == true
  self.modules[id] = def
  self.moduleOrder[#self.moduleOrder + 1] = id
  return def
end

function FTK:GetModule(id)
  return self.modules[id]
end

function FTK:GetModuleRecord(id)
  self:InitDB()
  local rec = self.db.modules[id]
  if type(rec) ~= "table" then
    rec = {}
    self.db.modules[id] = rec
  end
  if rec.enabled == nil then
    local def = self.modules[id]
    rec.enabled = def ~= nil and def.defaultEnabled == true
  end
  if type(rec.config) ~= "table" then
    rec.config = {}
  end
  return rec
end

function FTK:GetConfig(id)
  return self:GetModuleRecord(id).config
end

function FTK:IsEnabled(id)
  local module = self.modules[id]
  if module and module._active then
    return true
  end
  if not self._dbReady then
    return module ~= nil and module.defaultEnabled == true
  end
  return self:GetModuleRecord(id).enabled == true
end

function FTK:SetEnabled(id, enabled)
  local module = self.modules[id]
  if not module then
    return false
  end
  enabled = enabled == true
  local rec = self:GetModuleRecord(id)
  if enabled then
    if module._active then
      rec.enabled = true
      return true
    end
    -- Mark active before onEnable so a module that calls SetEnabled again
    -- cannot re-enter onEnable. Roll back if startup throws.
    module._active = true
    module._error = nil
    rec.enabled = true
    if type(module.onEnable) == "function" then
      local ok, err = pcall(module.onEnable, module)
      if not ok then
        module._active = false
        module._error = tostring(err)
        rec.enabled = false
        self:Print(module.name .. " failed to enable: " .. tostring(err))
        return false
      end
    end
    return true
  end
  if module._active and type(module.onDisable) == "function" then
    local ok, err = pcall(module.onDisable, module)
    if not ok then
      self:Print(module.name .. " failed to disable: " .. tostring(err))
    end
  end
  module._active = false
  module._error = nil
  rec.enabled = false
  return true
end

function FTK:ApplyModuleStates()
  if self._applied then
    return
  end
  self._applied = true
  self:InitDB()
  local i
  for i = 1, #self.moduleOrder do
    local id = self.moduleOrder[i]
    local rec = self:GetModuleRecord(id)
    if rec.enabled then
      self:SetEnabled(id, true)
    end
  end
end

function FTK:AddonVersion()
  local getter
  if _G.C_AddOns and _G.C_AddOns.GetAddOnMetadata then
    getter = _G.C_AddOns.GetAddOnMetadata
  elseif _G.GetAddOnMetadata then
    getter = _G.GetAddOnMetadata
  end
  if getter then
    local ok, version = pcall(getter, ADDON, "Version")
    if ok and type(version) == "string" and version ~= "" then
      return version
    end
  end
  return self.VERSION
end

function FTK:PrintHelp()
  self:Print("/ff, /forge, or /foreverforge - open or close the menu")
  self:Print("/ff reset - move the minimap button back")
  self:Print("/ff modules - list features")
end

function FTK:OnSlash(msg)
  msg = Trim(msg):lower()
  if msg == "" or msg == "toggle" or msg == "menu" then
    if self.ToggleMenu then
      self:ToggleMenu()
    end
    return
  end
  if msg == "open" or msg == "show" then
    if self.OpenMenu then
      self:OpenMenu()
    end
    return
  end
  if msg == "close" or msg == "hide" then
    if self.CloseMenu then
      self:CloseMenu()
    end
    return
  end
  if msg == "help" or msg == "?" then
    self:PrintHelp()
    return
  end
  if msg == "reset" or msg == "resetminimap" then
    if self.ResetMinimap then
      self:ResetMinimap()
      self:Print("Minimap button reset.")
    end
    return
  end
  if msg == "modules" or msg == "list" then
    if #self.moduleOrder == 0 then
      self:Print("No features registered.")
      return
    end
    local i
    for i = 1, #self.moduleOrder do
      local id = self.moduleOrder[i]
      local module = self.modules[id]
      local state = self:IsEnabled(id) and "on" or "off"
      self:Print(module.name .. " [" .. id .. "] " .. state)
    end
    return
  end
  self:Print("Unknown command.")
  self:PrintHelp()
end

local blockWatch = CreateFrame("Frame")
blockWatch:RegisterEvent("ADDON_ACTION_FORBIDDEN")
blockWatch:RegisterEvent("ADDON_ACTION_BLOCKED")
blockWatch:SetScript("OnEvent", function(_, _, ...)
  local parts = {}
  local count = select("#", ...)
  local index
  for index = 1, count do
    local value = select(index, ...)
    local secret = false
    if issecretvalue then
      local ok, isSecret = pcall(issecretvalue, value)
      secret = ok and isSecret == true
    end
    if type(value) == "string" and value ~= "" and not secret then
      parts[#parts + 1] = value
    end
  end
  if #parts > 0 then
    FTK:Print("Blocked action: " .. table.concat(parts, ", "))
  end
end)

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 ~= ADDON then
      return
    end
    FTK:InitDB()
    if FTK.InitMinimap then
      FTK:InitMinimap()
    end
    return
  end
  FTK:InitDB()
  if FTK.InitMinimap then
    FTK:InitMinimap()
  end
  FTK:ApplyModuleStates()
end)

_G.SLASH_FOREVERFORGE1 = "/ff"
_G.SLASH_FOREVERFORGE2 = "/forge"
_G.SLASH_FOREVERFORGE3 = "/foreverforge"
_G.SlashCmdList = _G.SlashCmdList or {}
_G.SlashCmdList.FOREVERFORGE = function(msg)
  FTK:OnSlash(msg)
end
