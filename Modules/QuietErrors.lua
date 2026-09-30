--[[
  Quiet Errors. Hides a curated set of combat spam on the floating error
  frame: out of range, not ready / cooldown, resource shortfalls, and
  similar attack spam. Matched against locale-safe _G.ERR_* (and a few
  SPELL_FAILED_*) globals. Other errors still show. One /ff switch.
]]

local FTK = ForeverForge
if not FTK then
  error("ForeverForge: Core.lua must load before Modules/QuietErrors.lua")
end

local MODULE_ID = "QuietErrors"

-- Curated combat spam keys only. Do not add blanket filters.
local SUPPRESS_KEYS = {
  "ERR_OUT_OF_RANGE",
  "ERR_SPELL_OUT_OF_RANGE",
  "ERR_USE_TOO_FAR",
  "ERR_BADATTACKFACING",
  "ERR_BADATTACKPOS",
  "ERR_INVALID_ATTACK_TARGET",
  "ERR_NO_ATTACK_TARGET",
  "ERR_GENERIC_NO_TARGET",
  "ERR_ATTACK_DEAD",
  "ERR_ATTACK_CHARMED",
  "ERR_ATTACK_STUNNED",
  "ERR_ATTACK_PACIFIED",
  "ERR_ATTACK_FLEEING",
  "ERR_ATTACK_CONFUSED",
  "ERR_SPELL_COOLDOWN",
  "ERR_ABILITY_COOLDOWN",
  "ERR_ITEM_COOLDOWN",
  "ERR_SPELL_FAILED_ANOTHER_IN_PROGRESS",
  "ERR_SPELL_FAILED_TOO_CLOSE",
  "ERR_CLIENT_LOCKED_OUT",
  "ERR_OUT_OF_MANA",
  "ERR_OUT_OF_RAGE",
  "ERR_OUT_OF_FOCUS",
  "ERR_OUT_OF_ENERGY",
  "ERR_OUT_OF_RUNIC_POWER",
  "ERR_OUT_OF_HEALTH",
  "ERR_OUT_OF_POWER_DISPLAY",
  "ERR_OUT_OF_CHI",
  "ERR_OUT_OF_HOLY_POWER",
  "ERR_OUT_OF_SOUL_SHARDS",
  "ERR_OUT_OF_COMBO_POINTS",
  "ERR_OUT_OF_RUNES",
  "ERR_OUT_OF_ARCANE_CHARGES",
  "ERR_OUT_OF_FURY",
  "ERR_OUT_OF_PAIN",
  "ERR_OUT_OF_INSANITY",
  "ERR_OUT_OF_MAELSTROM",
  "SPELL_FAILED_SPELL_IN_PROGRESS",
  "SPELL_FAILED_NOT_READY",
  "SPELL_FAILED_MOVING",
  "SPELL_FAILED_NO_COMBO_POINTS",
  "SPELL_FAILED_TOO_CLOSE",
  "SPELL_FAILED_OUT_OF_RANGE",
  "SPELL_FAILED_UNIT_NOT_INFRONT",
  "SPELL_FAILED_NOPATH",
  "SPELL_FAILED_TARGETS_DEAD",
}

local suppress = {}
local originalAddMessage
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

local function StripCodes(text)
  text = PlainString(text)
  if not text then
    return nil
  end
  local ok, cleaned = pcall(function()
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", ""))
  end)
  if not ok then
    return text
  end
  cleaned = PlainString(cleaned)
  if cleaned then
    cleaned = (cleaned:gsub("^%s+", ""):gsub("%s+$", ""))
  end
  return cleaned ~= "" and cleaned or nil
end

local function ClearTable(t)
  local k
  for k in pairs(t) do
    t[k] = nil
  end
end

local function RebuildSuppress()
  ClearTable(suppress)
  local i
  for i = 1, #SUPPRESS_KEYS do
    local key = SUPPRESS_KEYS[i]
    local value = PlainString(_G[key])
    if value then
      -- Exact match only. Skip format strings that need a substitution.
      if not value:find("%%", 1, true) then
        suppress[value] = true
      end
    end
  end
end

local function ShouldSuppress(msg)
  local text = StripCodes(msg)
  if not text then
    return false
  end
  return suppress[text] == true
end

local function InstallHook()
  local frame = _G.UIErrorsFrame
  if not frame or hooked then
    return
  end
  if type(frame.AddMessage) ~= "function" then
    return
  end
  originalAddMessage = frame.AddMessage
  hooked = true
  function frame.AddMessage(self, msg, ...)
    if FTK:IsEnabled(MODULE_ID) and ShouldSuppress(msg) then
      return
    end
    return originalAddMessage(self, msg, ...)
  end
end

FTK:RegisterModule({
  id = MODULE_ID,
  name = "Quiet Errors",
  description = "Hides common combat spam on the floating error frame (out of range, not ready, resource). Other errors still show.",
  defaultEnabled = true,
  onEnable = function()
    RebuildSuppress()
    InstallHook()
  end,
  onDisable = function()
    -- Hook stays installed but passes every message through while disabled.
  end,
})
