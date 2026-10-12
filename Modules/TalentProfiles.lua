--[[
  Talent Profiles. Save the current talent build under a name and stage it
  back later. Builds are kept per character (name-realm) and per spec index.

  Apply only stages points (C_Traits.PurchaseRank / SetSelection). It never
  commits: the player reviews and clicks the talent window's Apply Changes.
  Committed points cannot be refunded on Forever, so if the committed build
  has points the saved build does not, Apply places nothing and asks for a
  trainer reset.
]]

local FTK = ForeverForge
if not FTK then
  error("ForeverForge: Core.lua must load before Modules/TalentProfiles.lua")
end

local MODULE_ID = "TalentProfiles"
local MAX_PASSES = 60

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

local function Trim(s)
  return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function Say(msg)
  FTK:Print("Talent Profiles: " .. msg)
end

local function Call(fn, ...)
  if type(fn) ~= "function" then
    return false
  end
  return pcall(fn, ...)
end

local function Supported()
  return type(C_Traits) == "table"
    and type(C_ClassTalents) == "table"
    and type(C_Traits.GetConfigInfo) == "function"
    and type(C_Traits.GetTreeNodes) == "function"
    and type(C_Traits.GetNodeInfo) == "function"
    and type(C_Traits.PurchaseRank) == "function"
    and type(C_ClassTalents.GetActiveConfigID) == "function"
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
    return name .. "-" .. realm:gsub("%s+", "")
  end
  return name
end

local function SpecIndex()
  local fn = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization
  if type(fn) ~= "function" then
    fn = GetSpecialization
  end
  local ok, spec = Call(fn)
  return (ok and PlainNumber(spec)) or 1
end

local function Config()
  local cfg = FTK:GetConfig(MODULE_ID)
  if type(cfg.builds) ~= "table" then
    cfg.builds = {}
  end
  return cfg
end

-- Returns the name -> build table for this character and spec.
local function Builds()
  local key = CharKey()
  if not key then
    return nil
  end
  local cfg = Config()
  local char = cfg.builds[key]
  if type(char) ~= "table" then
    char = {}
    cfg.builds[key] = char
  end
  local spec = SpecIndex()
  local list = char[spec]
  if type(list) ~= "table" then
    list = {}
    char[spec] = list
  end
  return list
end

local function SortedNames()
  local list = Builds() or {}
  local names = {}
  local name
  for name in pairs(list) do
    names[#names + 1] = name
  end
  table.sort(names, function(a, b)
    return a:lower() < b:lower()
  end)
  return names
end

local function FindName(name)
  local list = Builds()
  name = Trim(name)
  if not list or name == "" then
    return nil
  end
  if list[name] then
    return name
  end
  local lower = name:lower()
  local n
  for n in pairs(list) do
    if n:lower() == lower then
      return n
    end
  end
  return nil
end

local function ActiveConfig()
  local ok, configID = Call(C_ClassTalents.GetActiveConfigID)
  configID = ok and PlainNumber(configID) or nil
  if not configID then
    return nil
  end
  local okInfo, info = Call(C_Traits.GetConfigInfo, configID)
  if not okInfo or type(info) ~= "table" or type(info.treeIDs) ~= "table" then
    return nil
  end
  return configID, info.treeIDs
end

-- Every node the player can see, with its committed rank and chosen entry.
local function ReadNodes(configID, treeIDs)
  local nodes = {}
  local t
  for t = 1, #treeIDs do
    local treeID = PlainNumber(treeIDs[t])
    local ok, ids = Call(C_Traits.GetTreeNodes, treeID)
    if treeID and ok and type(ids) == "table" then
      local i
      for i = 1, #ids do
        local nodeID = PlainNumber(ids[i])
        local okNode, info = Call(C_Traits.GetNodeInfo, configID, nodeID)
        if nodeID and okNode and type(info) == "table" and PlainNumber(info.ID) then
          local rank = PlainNumber(info.activeRank) or PlainNumber(info.currentRank) or 0
          local entryID = nil
          if type(info.activeEntry) == "table" then
            entryID = PlainNumber(info.activeEntry.entryID)
          end
          local isChoice = type(info.entryIDs) == "table" and #info.entryIDs > 1
          nodes[#nodes + 1] = {
            nodeID = nodeID,
            rank = rank,
            current = PlainNumber(info.currentRank) or rank,
            entryID = entryID,
            isChoice = isChoice,
            posX = PlainNumber(info.posX) or 0,
            posY = PlainNumber(info.posY) or 0,
            maxRanks = PlainNumber(info.maxRanks) or 1,
          }
        end
      end
    end
  end
  return nodes
end

local function HasStaged(configID)
  local ok, staged = Call(C_Traits.ConfigHasStagedChanges, configID)
  return ok and staged == true
end

local function NodeName(configID, nodeID, entryID)
  local name
  pcall(function()
    if not entryID then
      local info = C_Traits.GetNodeInfo(configID, nodeID)
      if info and info.activeEntry then
        entryID = info.activeEntry.entryID
      elseif info and type(info.entryIDs) == "table" then
        entryID = info.entryIDs[1]
      end
    end
    local entry = entryID and C_Traits.GetEntryInfo and C_Traits.GetEntryInfo(configID, entryID)
    local def = entry and entry.definitionID and C_Traits.GetDefinitionInfo
      and C_Traits.GetDefinitionInfo(entry.definitionID)
    if def then
      name = PlainString(def.overrideName)
      if not name and def.spellID and C_Spell and C_Spell.GetSpellName then
        name = PlainString(C_Spell.GetSpellName(def.spellID))
      end
      if not name and def.spellID and GetSpellInfo then
        name = PlainString((GetSpellInfo(def.spellID)))
      end
    end
  end)
  return name or ("node " .. tostring(nodeID))
end

local function SaveBuild(name)
  name = Trim(name)
  if name == "" then
    Say("Give the build a name.")
    return false
  end
  if not Supported() then
    Say("Not supported on this client.")
    return false
  end
  local configID, treeIDs = ActiveConfig()
  local list = Builds()
  if not configID or not list then
    Say("No active talent config found.")
    return false
  end
  if HasStaged(configID) then
    Say("You have unapplied talent changes. Saving the committed build only.")
  end
  local ranks = {}
  local count = 0
  local nodes = ReadNodes(configID, treeIDs)
  local i
  for i = 1, #nodes do
    local n = nodes[i]
    if n.rank > 0 then
      ranks[n.nodeID] = { rank = n.rank, entryID = n.isChoice and n.entryID or nil }
      count = count + n.rank
    end
  end
  local existing = FindName(name)
  if existing and existing ~= name then
    list[existing] = nil
  end
  list[name] = { nodes = ranks, points = count, savedAt = time and time() or 0 }
  Say("Saved \"" .. name .. "\" (" .. count .. " points).")
  return true
end

local function DeleteBuild(name)
  local found = FindName(name)
  if not found then
    Say("No build named \"" .. Trim(name) .. "\".")
    return false
  end
  Builds()[found] = nil
  Say("Deleted \"" .. found .. "\".")
  return true
end

local function RenameBuild(old, new)
  local found = FindName(old)
  new = Trim(new)
  if not found then
    Say("No build named \"" .. Trim(old) .. "\".")
    return false
  end
  if new == "" then
    Say("Give the build a new name.")
    return false
  end
  local other = FindName(new)
  if other and other ~= found then
    Say("A build named \"" .. other .. "\" already exists.")
    return false
  end
  local list = Builds()
  local build = list[found]
  list[found] = nil
  list[new] = build
  Say("Renamed \"" .. found .. "\" to \"" .. new .. "\".")
  return true
end

local function ApplyBuild(name)
  if InCombatLockdown and InCombatLockdown() then
    Say("Can't apply a build in combat.")
    return false
  end
  if not Supported() then
    Say("Not supported on this client.")
    return false
  end
  local found = FindName(name)
  if not found then
    Say("No build named \"" .. Trim(name) .. "\".")
    return false
  end
  local saved = Builds()[found].nodes or {}
  local configID, treeIDs = ActiveConfig()
  if not configID then
    Say("No active talent config found.")
    return false
  end
  if HasStaged(configID) then
    Say("You already have unapplied talent changes. Only adding points on top of them.")
  end

  -- Pass 1: anything committed that the saved build doesn't have blocks Apply.
  local nodes = ReadNodes(configID, treeIDs)
  local i
  for i = 1, #nodes do
    local n = nodes[i]
    local want = saved[n.nodeID]
    local wantRank = want and PlainNumber(want.rank) or 0
    local committed = n.rank -- activeRank: committed, not staged
    if committed > 0 then
      local entryMismatch = want and want.entryID and n.isChoice and n.entryID and n.entryID ~= want.entryID
      if committed > wantRank or entryMismatch then
        Say("Reset at trainer first. Your talents have points this build doesn't (" .. NodeName(configID, n.nodeID) .. ").")
        return false
      end
    end
  end

  -- Pass 2: stage missing ranks, top rows first, until nothing moves.
  table.sort(nodes, function(a, b)
    if a.posY ~= b.posY then
      return a.posY < b.posY
    end
    return a.posX < b.posX
  end)
  local placed = 0
  local pass
  local firstFail
  for pass = 1, MAX_PASSES do
    local progressed = false
    firstFail = nil
    for i = 1, #nodes do
      local n = nodes[i]
      local want = saved[n.nodeID]
      if want then
        local okInfo, info = Call(C_Traits.GetNodeInfo, configID, n.nodeID)
        local have = (okInfo and type(info) == "table" and PlainNumber(info.currentRank)) or n.current
        local wantRank = PlainNumber(want.rank) or 0
        while have < wantRank do
          local ok, result
          if want.entryID and n.isChoice and have == 0 and type(C_Traits.SetSelection) == "function" then
            ok, result = pcall(C_Traits.SetSelection, configID, n.nodeID, want.entryID)
          else
            ok, result = pcall(C_Traits.PurchaseRank, configID, n.nodeID)
          end
          if not ok or result == false then
            if not firstFail then
              firstFail = n
            end
            break
          end
          have = have + 1
          placed = placed + 1
          progressed = true
        end
      end
    end
    if not progressed then
      break
    end
  end
  if firstFail then
    Say("Stopped at " .. NodeName(configID, firstFail.nodeID, saved[firstFail.nodeID].entryID) .. ". It may need more points or a prerequisite.")
  end
  Say("Placed " .. placed .. " points. Review and click Apply Changes.")
  return true
end

-- Slash: /ff talents [save|apply|delete|rename] <name>
local function OnSlash(rest)
  rest = Trim(rest)
  local cmd, arg = rest:match("^(%S+)%s*(.*)$")
  cmd = cmd and cmd:lower() or ""
  if cmd == "save" then
    SaveBuild(arg)
    return
  end
  if cmd == "apply" then
    ApplyBuild(arg)
    return
  end
  if cmd == "delete" then
    DeleteBuild(arg)
    return
  end
  if cmd == "rename" then
    local old, new = arg:match("^(.-)%s*=%s*(.+)$")
    if old then
      RenameBuild(old, new)
    else
      Say("Usage: /ff talents rename <old> = <new>")
    end
    return
  end
  local names = SortedNames()
  if #names == 0 then
    Say("No saved builds for this character and spec.")
  else
    Say("Saved builds: " .. table.concat(names, ", "))
  end
  Say("/ff talents save <name>, apply <name>, delete <name>, rename <old> = <new>")
end

local function MakeButton(parent, text, width)
  local btn
  local ok, created = pcall(CreateFrame, "Button", nil, parent, "UIPanelButtonTemplate")
  if ok and type(created) == "table" then
    btn = created
  else
    btn = CreateFrame("Button", nil, parent)
    btn:SetNormalFontObject("GameFontNormalSmall")
  end
  btn:SetSize(width or 64, 20)
  btn:SetText(text)
  return btn
end

local function MakeEditBox(parent, width)
  local box
  local ok, created = pcall(CreateFrame, "EditBox", nil, parent, "InputBoxTemplate")
  if ok and type(created) == "table" then
    box = created
  else
    box = CreateFrame("EditBox", nil, parent)
    box:SetFontObject("GameFontHighlightSmall")
    box:SetTextInsets(6, 6, 2, 2)
  end
  box:SetSize(width or 160, 20)
  box:SetAutoFocus(false)
  return box
end

local function BuildOptions(_, parent)
  local y = -4
  local note = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  note:SetPoint("TOPLEFT", 0, y)
  note:SetWidth(420)
  note:SetJustifyH("LEFT")
  note:SetWordWrap(true)
  if not Supported() then
    note:SetText("Talent Profiles is not supported on this client.")
    parent:SetHeight(40)
    return
  end
  note:SetText("Builds for this character and spec. Apply places points but does not commit them: review, then click Apply Changes in the talent window.")
  y = y - 40

  local box = MakeEditBox(parent, 200)
  box:SetPoint("TOPLEFT", 6, y)
  local saveBtn = MakeButton(parent, "Save current", 100)
  saveBtn:SetPoint("LEFT", box, "RIGHT", 10, 0)
  y = y - 30

  local rows = {}
  local listTop = y
  local Refresh

  local function RowFor(index)
    local row = rows[index]
    if row then
      return row
    end
    row = CreateFrame("Frame", nil, parent)
    row:SetSize(420, 24)
    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.label:SetPoint("LEFT", 0, 0)
    row.label:SetWidth(170)
    row.label:SetJustifyH("LEFT")
    row.apply = MakeButton(row, "Apply", 60)
    row.apply:SetPoint("LEFT", 175, 0)
    row.rename = MakeButton(row, "Rename", 66)
    row.rename:SetPoint("LEFT", row.apply, "RIGHT", 4, 0)
    row.delete = MakeButton(row, "Delete", 60)
    row.delete:SetPoint("LEFT", row.rename, "RIGHT", 4, 0)
    row.apply:SetScript("OnClick", function()
      ApplyBuild(row.name)
    end)
    row.rename:SetScript("OnClick", function()
      local new = PlainString(box:GetText())
      if not new then
        Say("Type the new name in the box, then click Rename.")
        return
      end
      if RenameBuild(row.name, new) then
        box:SetText("")
        Refresh()
      end
    end)
    row.delete:SetScript("OnClick", function()
      if DeleteBuild(row.name) then
        Refresh()
      end
    end)
    rows[index] = row
    return row
  end

  local empty = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  empty:SetPoint("TOPLEFT", 6, listTop)
  empty:SetText("No saved builds yet.")

  Refresh = function()
    local names = SortedNames()
    local i
    for i = 1, math.max(#names, #rows) do
      local name = names[i]
      if name then
        local row = RowFor(i)
        local build = Builds()[name]
        row.name = name
        row.label:SetText(FTK.Plain(name) .. " |cff999999(" .. tostring(build.points or 0) .. ")|r")
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 6, listTop - (i - 1) * 26)
        row:Show()
      elseif rows[i] then
        rows[i]:Hide()
      end
    end
    empty:SetShown(#names == 0)
    parent:SetHeight((-listTop) + math.max(#names, 1) * 26 + 12)
  end

  local function DoSave()
    if SaveBuild(box:GetText()) then
      box:SetText("")
      box:ClearFocus()
      Refresh()
    end
  end
  saveBtn:SetScript("OnClick", DoSave)
  box:SetScript("OnEnterPressed", DoSave)
  box:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
  end)
  Refresh()
end

FTK:RegisterModule({
  id = MODULE_ID,
  name = "Talent Profiles",
  description = "Save talent builds by name per character and spec. Apply stages the points; you review and click Apply Changes. Needs a trainer reset if your committed points don't match.",
  defaultEnabled = true,
  BuildOptions = BuildOptions,
  onEnable = function()
    Config()
    if FTK.RegisterSlash then
      FTK:RegisterSlash("talents", function(rest)
        if not FTK:IsEnabled(MODULE_ID) then
          Say("Turn Talent Profiles on in the Forever Forge menu first.")
          return
        end
        OnSlash(rest)
      end)
    end
  end,
  onDisable = function() end,
})
