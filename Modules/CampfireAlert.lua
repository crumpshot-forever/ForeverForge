--[[
  Campfire Alert. When Campfire Nearby is confirmed on the player, post one
  local chat line and, if the sound option is on, play one sound.

  Campfire Nearby is spell 1283391 on Forever 1.60.1: a unique dummy aura
  with a 100 yard radius, no duration, applied by a server script. Wowhead's
  Forever notes describe it as the buff that appears when a camp is close,
  before anyone sits. Camp Benefits is the hour-long buff from sitting and
  is not used here. A lingering buff is not treated as proof the fire is
  still nearby.

  The aura does not include the camp's coordinates, and no supported API
  found for this client exposes that object position. There is no minimap
  marker. The player's own position is never shown as the camp.

  The same aura covers every camp in range, so adjacent fires are one
  alert. An unreadable aura bar does not count as leaving. After a
  confirmed absence of 10 seconds the alert can arm again, and a new
  entry still waits out a 60 second cooldown from the last alert.

  Nothing is sent to public chat.

  Hovering a camp item adds one line naming that item's buff type. The
  line is chosen from the item id on the tooltip. Numbers scale with
  level, so the line names the effect and the class buff it excludes.
]]

local FTK = ForeverForge
if not FTK then
  error("ForeverForge: Core.lua must load before Modules/CampfireAlert.lua")
end

local MODULE_ID = "CampfireAlert"
-- Published Forever 1.60.1 spell. Matched by this id or by the localized
-- name the client returns for it. Not Camp Benefits, Welcoming Campfire,
-- or the old Cozy Fire cooking buff.
local CAMP_SPELL_ID = 1283391
local ABSENT_REARM = 10
local REENTRY_COOLDOWN = 60
local SCAN_INTERVAL = 1

local frame = CreateFrame("Frame")
local expectedName
local latched = false
local nextAlert = 0
local absentAccrued = 0
local absentMark = nil
local scanElapsed = 0
local tipsInstalled = false
local addingTip = false

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

local function Now()
  if type(GetTime) ~= "function" then
    return 0
  end
  local ok, value = pcall(GetTime)
  if not ok then
    return 0
  end
  return PlainNumber(value) or 0
end

local function Config()
  return FTK:GetConfig(MODULE_ID)
end

local function SoundOn()
  return Config().sound ~= false
end

local function ExpectedName()
  if expectedName then
    return expectedName
  end
  local name
  if C_Spell and type(C_Spell.GetSpellName) == "function" then
    local ok, value = pcall(C_Spell.GetSpellName, CAMP_SPELL_ID)
    if ok then
      name = PlainString(value)
    end
  end
  if not name and type(GetSpellInfo) == "function" then
    local ok, value = pcall(GetSpellInfo, CAMP_SPELL_ID)
    if ok then
      name = PlainString(value)
    end
  end
  if name then
    expectedName = name
  end
  return name
end

local function PlayId(id)
  if type(id) ~= "number" or type(PlaySound) ~= "function" then
    return false
  end
  local ok, played = pcall(PlaySound, id, "Master")
  return ok and played ~= false
end

local function PlayCue()
  if SOUNDKIT and type(SOUNDKIT.READY_CHECK) == "number" and PlayId(SOUNDKIT.READY_CHECK) then
    return
  end
  if PlayId(8960) then
    return
  end
  PlayId(3175)
end

local function ConsiderAura(spellId, name)
  local id = PlainNumber(spellId)
  local label = PlainString(name)
  local expect = ExpectedName()
  if id == CAMP_SPELL_ID then
    return "present"
  end
  if label and expect and label == expect then
    return "present"
  end
  -- A readable id or a readable other name is not this buff. A secret
  -- id with no readable name cannot be ruled out.
  if id ~= nil then
    return "no"
  end
  if label and expect and label ~= expect then
    return "no"
  end
  if IsSecret(spellId) or IsSecret(name) then
    return "secret"
  end
  return "no"
end

local function ReadIndex(index, filter)
  if C_UnitAuras and type(C_UnitAuras.GetAuraDataByIndex) == "function" then
    local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", index, filter)
    if not ok or IsSecret(aura) then
      return "unknown"
    end
    if aura == nil then
      return "end"
    end
    if type(aura) ~= "table" then
      return "secret"
    end
    return ConsiderAura(aura.spellId, aura.name)
  end
  if type(UnitAura) ~= "function" then
    return "unsupported"
  end
  local ok, name, _, _, _, _, _, _, _, _, spellId = pcall(UnitAura, "player", index, filter)
  if not ok then
    return "unknown"
  end
  if name == nil and spellId == nil then
    return "end"
  end
  return ConsiderAura(spellId, name)
end

-- "present", "absent", or "unknown". Unknown must not count as leaving.
local function Scan()
  local sawSecret = false
  local index
  for index = 1, 40 do
    local reading = ReadIndex(index, "HELPFUL")
    if reading == "unsupported" then
      return "unknown"
    end
    if reading == "end" then
      break
    end
    if reading == "present" then
      return "present"
    end
    if reading == "secret" or reading == "unknown" then
      sawSecret = true
    end
  end
  if sawSecret then
    return "unknown"
  end
  return "absent"
end

local function ClearPresence()
  latched = false
  absentAccrued = 0
  absentMark = nil
end

local function Alert()
  FTK:Print("Active campfire nearby")
  if SoundOn() then
    PlayCue()
  end
end

local function Evaluate()
  if not FTK:IsEnabled(MODULE_ID) then
    return
  end
  local state = Scan()
  local now = Now()
  if state == "present" then
    absentAccrued = 0
    absentMark = nil
    if not latched then
      latched = true
      if now >= nextAlert then
        Alert()
        nextAlert = now + REENTRY_COOLDOWN
      end
    end
    return
  end
  if state == "unknown" or not latched then
    if absentMark then
      absentAccrued = absentAccrued + (now - absentMark)
      absentMark = nil
    end
    return
  end
  if not absentMark then
    absentMark = now
  end
  if absentAccrued + (now - absentMark) >= ABSENT_REARM then
    ClearPresence()
  end
end

local function OnUpdate(_, elapsed)
  local step = PlainNumber(elapsed) or 0
  scanElapsed = scanElapsed + step
  if scanElapsed < SCAN_INTERVAL then
    return
  end
  scanElapsed = 0
  Evaluate()
end

local function OnEvent(_, event, unit)
  if event == "UNIT_AURA" then
    if unit ~= "player" then
      return
    end
    Evaluate()
    return
  end
  ClearPresence()
  Evaluate()
end

local function Watch(event)
  pcall(frame.RegisterEvent, frame, event)
end

local function Start()
  frame:SetScript("OnEvent", OnEvent)
  frame:SetScript("OnUpdate", OnUpdate)
  Watch("UNIT_AURA")
  Watch("PLAYER_ENTERING_WORLD")
  Watch("ZONE_CHANGED_NEW_AREA")
  scanElapsed = SCAN_INTERVAL
  Evaluate()
end

local function Stop()
  frame:SetScript("OnEvent", nil)
  frame:SetScript("OnUpdate", nil)
  pcall(frame.UnregisterAllEvents, frame)
  ClearPresence()
  nextAlert = 0
  scanElapsed = 0
end

-- Item ids are the Forever 1.60.1 camp features. Higher tiers keep the
-- tier-1 buff. Fires, the reagent bots, the Anarchist's Workbench, and
-- the Iron Oven do not grant a stat buff.
local BUFF_STAMINA = "Camp buff: Stamina. Does not stack with Power Word: Fortitude."
local BUFF_INTELLECT = "Camp buff: Intellect. Does not stack with Arcane Intellect."
local BUFF_ATTACK = "Camp buff: Melee attack power. Does not stack with Blessing of Might."
local BUFF_STRENGTH = "Camp buff: Strength. Does not stack with Strength of Earth Totem."
local BUFF_MANA = "Camp buff: Mana every 5 sec. Does not stack with Blessing of Wisdom."
local BUFF_SPIRIT = "Camp buff: Spirit. Does not stack with Divine Spirit."
local BUFF_LUTE = "Camp buff: Armor, all stats, and resistances. Does not stack with Mark of the Wild."
local BUFF_STATS = "Camp buff: 8% all stats. Does not stack with Blessing of Kings."
local BUFF_CRIT = "Camp buff: 2% critical strike. Does not stack with Moonkin Aura."
local BUFF_REST = "Camp buff: Rested experience."
local BUFF_FOOD = "Camp buff: Stamina food."
local BUFF_NONE = "Camp buff: none"

local BUFF_BY_ID = {
  [279968] = BUFF_STAMINA, -- First Aid Kit
  [279940] = BUFF_STAMINA, -- Toxin Study
  [279951] = BUFF_STAMINA, -- Plague Doctor's Laboratory
  [279962] = BUFF_INTELLECT, -- Incense Candle
  [279964] = BUFF_INTELLECT, -- Greenhouse
  [279947] = BUFF_INTELLECT, -- Seed Hybridizer
  [279960] = BUFF_ATTACK, -- Lodestone
  [279948] = BUFF_ATTACK, -- Rock Garden
  [279952] = BUFF_ATTACK, -- Molten Foundry
  [279944] = BUFF_STRENGTH, -- Sharpening Wheel
  [279988] = BUFF_STRENGTH, -- Anvil
  [279955] = BUFF_STRENGTH, -- Master Forge
  [279956] = BUFF_MANA, -- Mana Well
  [279970] = BUFF_MANA, -- Fermenter
  [279990] = BUFF_MANA, -- Alchemy Laboratory
  [279973] = BUFF_SPIRIT, -- Faction Banner (Alliance)
  [279972] = BUFF_SPIRIT, -- Faction Banner (Horde)
  [279943] = BUFF_SPIRIT, -- Spinning Wheel
  [279959] = BUFF_SPIRIT, -- Loom
  [279976] = BUFF_LUTE, -- Enchanted Lute
  [279985] = BUFF_LUTE, -- Arcane Salvager
  [279987] = BUFF_LUTE, -- Arcane Forge
  [279967] = BUFF_STATS, -- Fish Bowl
  [279965] = BUFF_STATS, -- Fishing Rack
  [279966] = BUFF_STATS, -- Fishing Hut
  [279979] = BUFF_CRIT, -- Camp Chair
  [279969] = BUFF_CRIT, -- Field Guide
  [279938] = BUFF_CRIT, -- Trapper's Workbench
  [279978] = BUFF_REST, -- Camp Tent
  [279941] = BUFF_REST, -- Tanning Rack
  [279945] = BUFF_REST, -- Sewing Machine
  [279957] = BUFF_FOOD, -- Cookie's Feast
  [279981] = BUFF_NONE, -- Basic Campfire Kit
  [279961] = BUFF_NONE, -- Journeyman Campfire Kit
  [279974] = BUFF_NONE, -- Expert Campfire Kit
  [279950] = BUFF_NONE, -- Reagent Bot
  [279949] = BUFF_NONE, -- Repair Bot
  [279989] = BUFF_NONE, -- Anarchist's Workbench
  [279982] = BUFF_NONE, -- Iron Oven
}

local BUFF_BY_NAME = {
  ["First Aid Kit"] = BUFF_STAMINA,
  ["Toxin Study"] = BUFF_STAMINA,
  ["Plague Doctor's Laboratory"] = BUFF_STAMINA,
  ["Incense Candle"] = BUFF_INTELLECT,
  ["Greenhouse"] = BUFF_INTELLECT,
  ["Seed Hybridizer"] = BUFF_INTELLECT,
  ["Lodestone"] = BUFF_ATTACK,
  ["Rock Garden"] = BUFF_ATTACK,
  ["Molten Foundry"] = BUFF_ATTACK,
  ["Sharpening Wheel"] = BUFF_STRENGTH,
  ["Master Forge"] = BUFF_STRENGTH,
  ["Mana Well"] = BUFF_MANA,
  ["Fermenter"] = BUFF_MANA,
  ["Alchemy Laboratory"] = BUFF_MANA,
  ["Faction Banner"] = BUFF_SPIRIT,
  ["Enchanted Lute"] = BUFF_LUTE,
  ["Arcane Salvager"] = BUFF_LUTE,
  ["Arcane Forge"] = BUFF_LUTE,
  ["Fish Bowl"] = BUFF_STATS,
  ["Fishing Bowl"] = BUFF_STATS,
  ["Fishing Rack"] = BUFF_STATS,
  ["Fishing Hut"] = BUFF_STATS,
  ["Camp Chair"] = BUFF_CRIT,
  ["Camp Tent"] = BUFF_REST,
  ["Tanning Rack"] = BUFF_REST,
  ["Sewing Machine"] = BUFF_REST,
  ["Cookie's Feast"] = BUFF_FOOD,
  ["Basic Campfire"] = BUFF_NONE,
  ["Basic Campfire Kit"] = BUFF_NONE,
  ["Journeyman Campfire"] = BUFF_NONE,
  ["Journeyman Campfire Kit"] = BUFF_NONE,
  ["Expert Campfire"] = BUFF_NONE,
  ["Expert Campfire Kit"] = BUFF_NONE,
  ["Reagent Bot"] = BUFF_NONE,
  ["Repair Bot"] = BUFF_NONE,
  ["Anarchist's Workbench"] = BUFF_NONE,
  ["Trapper's Workbench"] = BUFF_CRIT,
  ["Iron Oven"] = BUFF_NONE,
}

-- These names also exist on ordinary world objects. Only treat them as
-- camp items when the tooltip itself mentions a campfire.
local GENERIC_CAMP_NAME = {
  ["Anvil"] = BUFF_STRENGTH,
  ["Loom"] = BUFF_SPIRIT,
  ["Spinning Wheel"] = BUFF_SPIRIT,
  ["Field Guide"] = BUFF_CRIT,
}

local function ItemIdFromLink(link)
  if type(link) ~= "string" or IsSecret(link) then
    return nil
  end
  local ok, digits = pcall(string.match, link, "item:(%d+)")
  if not ok or type(digits) ~= "string" then
    return nil
  end
  return PlainNumber(tonumber(digits))
end

local function ItemIdFromTooltip(tooltip)
  if not tooltip or not tooltip.GetItem then
    return nil
  end
  local ok, _, link = pcall(tooltip.GetItem, tooltip)
  if not ok then
    return nil
  end
  return ItemIdFromLink(link)
end

local function ItemIdFromData(data)
  if type(data) ~= "table" then
    return nil
  end
  if TooltipUtil and TooltipUtil.SurfaceArgs then
    pcall(TooltipUtil.SurfaceArgs, data)
  end
  return PlainNumber(data.id)
end

local function TooltipTitle(tooltip)
  if not tooltip or not tooltip.GetName then
    return nil
  end
  local name = tooltip:GetName()
  if type(name) ~= "string" or name == "" or IsSecret(name) then
    return nil
  end
  local line = _G[name .. "TextLeft1"]
  if not line or not line.GetText then
    return nil
  end
  local ok, text = pcall(line.GetText, line)
  if not ok then
    return nil
  end
  return PlainString(text)
end

local function TitleFromData(data)
  if type(data) ~= "table" then
    return nil
  end
  if TooltipUtil and TooltipUtil.SurfaceArgs then
    pcall(TooltipUtil.SurfaceArgs, data)
  end
  local lines = data.lines
  if type(lines) ~= "table" or IsSecret(lines) then
    return nil
  end
  local first = lines[1]
  if type(first) ~= "table" or IsSecret(first) then
    return nil
  end
  if TooltipUtil and TooltipUtil.SurfaceArgs then
    pcall(TooltipUtil.SurfaceArgs, first)
  end
  return PlainString(first.leftText)
end

local function MentionsCamp(tooltip)
  if not tooltip or not tooltip.GetName or not tooltip.NumLines then
    return false
  end
  local name = tooltip:GetName()
  if type(name) ~= "string" or name == "" or IsSecret(name) then
    return false
  end
  local count = tooltip:NumLines()
  if type(count) ~= "number" or IsSecret(count) or count < 1 then
    return false
  end
  if count > 40 then
    count = 40
  end
  local i
  for i = 1, count do
    local line = _G[name .. "TextLeft" .. i]
    if line and line.GetText then
      local ok, text = pcall(line.GetText, line)
      local plain = ok and PlainString(text) or nil
      if plain then
        local folded = string.lower(plain)
        if string.find(folded, "campfire", 1, true) or string.find(folded, "camping", 1, true) then
          return true
        end
      end
    end
  end
  return false
end

local function LineAlreadyShown(tooltip, text)
  if not tooltip.GetName or not tooltip.NumLines then
    return false
  end
  local name = tooltip:GetName()
  if type(name) ~= "string" or name == "" or IsSecret(name) then
    return false
  end
  local count = tooltip:NumLines()
  if type(count) ~= "number" or IsSecret(count) or count < 1 then
    return false
  end
  if count > 40 then
    count = 40
  end
  local i
  for i = 1, count do
    local line = _G[name .. "TextLeft" .. i]
    if line and line.GetText then
      local ok, existing = pcall(line.GetText, line)
      local plain = ok and PlainString(existing) or nil
      if plain and plain == text then
        return true
      end
    end
  end
  return false
end

local function AppendBuff(tooltip, text)
  if addingTip or not tooltip or not tooltip.AddLine then
    return
  end
  if LineAlreadyShown(tooltip, text) then
    return
  end
  addingTip = true
  pcall(tooltip.AddLine, tooltip, text, 1, 0.82, 0.45, true)
  addingTip = false
end

local function BuffForTooltip(tooltip, data, trustDataId)
  local itemId = ItemIdFromTooltip(tooltip)
  if not itemId and trustDataId then
    itemId = ItemIdFromData(data)
  end
  if itemId and BUFF_BY_ID[itemId] then
    return BUFF_BY_ID[itemId]
  end
  local title = TooltipTitle(tooltip) or TitleFromData(data)
  if not title then
    return nil
  end
  local straight = title
  local ok, folded = pcall(string.gsub, title, "’", "'")
  if ok and type(folded) == "string" then
    straight = folded
  end
  if BUFF_BY_NAME[straight] then
    return BUFF_BY_NAME[straight]
  end
  local generic = GENERIC_CAMP_NAME[straight]
  if generic and MentionsCamp(tooltip) then
    return generic
  end
  return nil
end

local function OnCampItemTooltip(tooltip, data)
  if not FTK:IsEnabled(MODULE_ID) then
    return
  end
  local text = BuffForTooltip(tooltip, data, true)
  if text then
    AppendBuff(tooltip, text)
  end
end

local function OnCampObjectTooltip(tooltip, data)
  if not FTK:IsEnabled(MODULE_ID) then
    return
  end
  local text = BuffForTooltip(tooltip, data, false)
  if text then
    AppendBuff(tooltip, text)
  end
end

local function InstallTips()
  if tipsInstalled then
    return
  end
  tipsInstalled = true
  local processor = TooltipDataProcessor
  local types = Enum and Enum.TooltipDataType
  if processor and processor.AddTooltipPostCall and types then
    -- Item is enum value 0, which is false in Lua, so test nil.
    if types.Item ~= nil then
      pcall(processor.AddTooltipPostCall, types.Item, OnCampItemTooltip)
    end
    if types.Object ~= nil then
      pcall(processor.AddTooltipPostCall, types.Object, OnCampObjectTooltip)
    end
  end
  if GameTooltip and GameTooltip.HookScript then
    pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetItem", OnCampItemTooltip)
  end
  if ItemRefTooltip and ItemRefTooltip.HookScript then
    pcall(ItemRefTooltip.HookScript, ItemRefTooltip, "OnTooltipSetItem", OnCampItemTooltip)
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
    local checked = self:GetChecked()
    setter(checked == true or checked == 1)
  end)
  local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  text:SetPoint("LEFT", box, "RIGHT", 4, 0)
  text:SetText(label)
  return y - 28
end

local function BuildOptions(_, parent)
  local note = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  note:SetPoint("TOPLEFT", 0, -4)
  note:SetWidth(420)
  note:SetJustifyH("LEFT")
  note:SetWordWrap(true)
  note:SetText("Off until you enable Campfire Alert in the list. A confirmed Campfire Nearby buff posts one local line. Hovering a camp item adds its buff type. There is no map marker: that buff does not include where the fire is. The same alert covers every camp in range. Turning the module off stops the scan and the tooltip line.")
  local y = -92
  y = CheckLine(parent, "Play a sound", y, function()
    return SoundOn()
  end, function(value)
    Config().sound = value == true
  end)
  parent:SetHeight(20 - y)
end

FTK:RegisterModule({
  id = MODULE_ID,
  name = "Campfire Alert",
  description = "Opt-in. When Campfire Nearby is confirmed on you, posts one local line and can play a sound. Hovering a camp item adds its buff type. It does not mark the map: that buff does not carry the camp's location.",
  defaultEnabled = false,
  onEnable = function()
    InstallTips()
    Start()
  end,
  onDisable = function()
    Stop()
  end,
  BuildOptions = BuildOptions,
})

InstallTips()
