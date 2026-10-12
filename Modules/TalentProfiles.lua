--[[
  Talent Profiles. Save the current talent build under a name and stage it
  back later. Builds are kept per character (name-realm) and per spec index.

  Apply only stages points (C_Traits.PurchaseRank / SetSelection). It never
  commits: the player reviews and clicks the talent window's Apply Changes.
  Committed points cannot be refunded on Forever, so if the committed build
  has points the saved build does not, Apply places nothing and asks for a
  trainer reset.

  Saved builds for the spec on screen also show as tabs on the right of the
  talent window: spec icon, with the saved name drawn on it. Click a tab to
  stage that build. Click it again to clear the preview.
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

-- Which saved build the side tabs last staged, and for which spec index.
local viewedName, viewedSpec
local RefreshSideTabs

local function TouchTabs()
  if RefreshSideTabs then
    RefreshSideTabs()
  end
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
-- spec nil means the spec the character is playing right now.
local function Builds(spec)
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
  spec = PlainNumber(spec) or SpecIndex()
  local list = char[spec]
  if type(list) ~= "table" then
    list = {}
    char[spec] = list
  end
  return list
end

local function SortedNames(spec)
  local list = Builds(spec) or {}
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

local function FindName(name, spec)
  local list = Builds(spec)
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

-- configID nil uses the active spec. A talent-pane id stages into the tree on screen.
local function ResolveConfig(configID)
  configID = PlainNumber(configID)
  if not configID then
    return ActiveConfig()
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
  TouchTabs()
  return true
end

local function DeleteBuild(name)
  local found = FindName(name)
  if not found then
    Say("No build named \"" .. Trim(name) .. "\".")
    return false
  end
  Builds()[found] = nil
  if viewedName == found then
    viewedName, viewedSpec = nil, nil
  end
  Say("Deleted \"" .. found .. "\".")
  TouchTabs()
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
  if viewedName == found then
    viewedName = new
  end
  Say("Renamed \"" .. found .. "\" to \"" .. new .. "\".")
  TouchTabs()
  return true
end

-- True when committed points cannot become this saved build without a trainer reset.
local function CommittedBlocks(nodes, saved, configID)
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
        return true
      end
    end
  end
  return false
end

local function Rollback(configID)
  local fn = C_Traits and (C_Traits.RollbackConfig or C_Traits.RollBackConfig)
  if type(fn) ~= "function" then
    return false
  end
  local ok = pcall(fn, configID)
  return ok
end

-- spec and configID are optional. The menu and slash command leave them nil
-- (active spec, active config). Side tabs pass the tree on screen.
-- replaceStaged clears a previous preview before purchasing, and only after
-- the committed-points check passes.
local function ApplyBuild(name, spec, configID, replaceStaged)
  if InCombatLockdown and InCombatLockdown() then
    Say("Can't apply a build in combat.")
    return false
  end
  if not Supported() then
    Say("Not supported on this client.")
    return false
  end
  local found = FindName(name, spec)
  if not found then
    Say("No build named \"" .. Trim(name) .. "\".")
    return false
  end
  local saved = Builds(spec)[found].nodes or {}
  local treeIDs
  configID, treeIDs = ResolveConfig(configID)
  if not configID then
    Say("No active talent config found.")
    return false
  end

  local nodes = ReadNodes(configID, treeIDs)
  if CommittedBlocks(nodes, saved, configID) then
    return false
  end
  if HasStaged(configID) then
    if replaceStaged and Rollback(configID) and not HasStaged(configID) then
      nodes = ReadNodes(configID, treeIDs)
    else
      Say("You already have unapplied talent changes. Only adding points on top of them.")
    end
  end
  local i

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
  viewedName = found
  viewedSpec = PlainNumber(spec) or SpecIndex()
  Say("Placed " .. placed .. " points. Review and click Apply Changes.")
  TouchTabs()
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

local tabsEnabled = false
local profileTabs
local tabButtons = {}
local tabWatcher = CreateFrame("Frame")

local function Solid(tex, r, g, b, a)
  if tex.SetColorTexture then
    tex:SetColorTexture(r, g, b, a)
  else
    tex:SetTexture("Interface\\Buttons\\WHITE8X8")
    tex:SetVertexColor(r, g, b, a)
  end
end

local function TalentHost()
  local frame = _G.PlayerSpellsFrame or _G.ClassTalentFrame
  if type(frame) ~= "table" then
    frame = _G.PlayerTalentFrame
  end
  if type(frame) ~= "table" then
    return nil
  end
  local pane = frame.TalentsFrame or frame.TalentsTab
  if type(pane) ~= "table" and frame == _G.PlayerTalentFrame then
    pane = frame
  end
  if type(pane) ~= "table" then
    return nil
  end
  return frame, pane
end

local function NumSpecs()
  local fn = C_SpecializationInfo and C_SpecializationInfo.GetNumSpecializations or GetNumSpecializations
  local ok, n = Call(fn)
  n = ok and PlainNumber(n) or nil
  if n and n > 0 and n < 20 then
    return n
  end
  return 4
end

local function SpecInfoAt(index)
  local specID, icon
  pcall(function()
    local id, specName, specDesc, file
    if C_SpecializationInfo and type(C_SpecializationInfo.GetSpecializationInfo) == "function" then
      id, specName, specDesc, file = C_SpecializationInfo.GetSpecializationInfo(index)
    elseif GetSpecializationInfo then
      id, specName, specDesc, file = GetSpecializationInfo(index)
    end
    specID, icon = id, file
  end)
  if IsSecret(icon) then
    icon = nil
  end
  return PlainNumber(specID), icon
end

local function SpecIndexForID(specID)
  specID = PlainNumber(specID)
  if not specID then
    return nil
  end
  local i
  for i = 1, NumSpecs() do
    local id = SpecInfoAt(i)
    if id == specID then
      return i
    end
  end
  return nil
end

local function ViewingSpec(pane)
  if pane and type(pane.GetSpecID) == "function" then
    local ok, specID = Call(pane.GetSpecID, pane)
    local idx = ok and SpecIndexForID(specID)
    if idx then
      return idx
    end
  end
  return SpecIndex()
end

local function PaneConfigID(pane)
  if pane and type(pane.GetConfigID) == "function" then
    local ok, id = Call(pane.GetConfigID, pane)
    return ok and PlainNumber(id) or nil
  end
  return nil
end

local function SpecIcon(spec)
  local _, icon = SpecInfoAt(spec)
  if type(icon) == "number" or (type(icon) == "string" and icon ~= "") then
    return icon
  end
  return "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function PaintBorder(btn, selected)
  local r, g, b, a = 0.2, 0.16, 0.08, 0.95
  if selected then
    r, g, b, a = 0.95, 0.78, 0.25, 1
  end
  Solid(btn.edgeTop, r, g, b, a)
  Solid(btn.edgeBottom, r, g, b, a)
  Solid(btn.edgeLeft, r, g, b, a)
  Solid(btn.edgeRight, r, g, b, a)
end

local function ViewBuild(name)
  if InCombatLockdown and InCombatLockdown() then
    Say("Can't apply a build in combat.")
    TouchTabs()
    return
  end
  local _, pane = TalentHost()
  local spec = ViewingSpec(pane)
  local found = FindName(name, spec)
  if not found then
    Say("No build named \"" .. Trim(name) .. "\".")
    return
  end
  local configID = PaneConfigID(pane)
  if not configID and spec ~= SpecIndex() then
    Say("This talent tree isn't ready to stage yet.")
    return
  end
  if viewedName == found and viewedSpec == spec then
    local id = select(1, ResolveConfig(configID))
    if id and HasStaged(id) and (not Rollback(id) or HasStaged(id)) then
      Say("Couldn't clear the talent preview on this client.")
      TouchTabs()
      return
    end
    viewedName, viewedSpec = nil, nil
    Say("Cleared \"" .. found .. "\". Showing committed talents.")
    TouchTabs()
    return
  end
  ApplyBuild(found, spec, configID, true)
end

local function EnsureTabButton(index)
  local btn = tabButtons[index]
  if btn then
    return btn
  end
  btn = CreateFrame("Button", nil, profileTabs)
  btn:SetSize(72, 46)
  btn:RegisterForClicks("LeftButtonUp")
  btn:EnableMouse(true)
  btn.bg = btn:CreateTexture(nil, "BACKGROUND")
  btn.bg:SetAllPoints()
  Solid(btn.bg, 0.04, 0.04, 0.04, 0.92)
  btn.icon = btn:CreateTexture(nil, "ARTWORK")
  btn.icon:SetPoint("TOPLEFT", 3, -3)
  btn.icon:SetPoint("BOTTOMRIGHT", -3, 3)
  btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  btn.shade = btn:CreateTexture(nil, "OVERLAY")
  btn.shade:SetPoint("BOTTOMLEFT", 3, 3)
  btn.shade:SetPoint("BOTTOMRIGHT", -3, 3)
  btn.shade:SetHeight(15)
  Solid(btn.shade, 0, 0, 0, 0.78)
  btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  pcall(btn.label.SetDrawLayer, btn.label, "OVERLAY", 7)
  btn.label:SetPoint("BOTTOM", 0, 4)
  btn.label:SetJustifyH("CENTER")
  btn.label:SetWordWrap(false)
  local font = btn.label:GetFont()
  if font then
    btn.label:SetFont(font, 9, "OUTLINE")
  end
  local function Edge()
    local tex = btn:CreateTexture(nil, "OVERLAY")
    return tex
  end
  btn.edgeTop = Edge()
  btn.edgeTop:SetPoint("TOPLEFT")
  btn.edgeTop:SetPoint("TOPRIGHT")
  btn.edgeTop:SetHeight(2)
  btn.edgeBottom = Edge()
  btn.edgeBottom:SetPoint("BOTTOMLEFT")
  btn.edgeBottom:SetPoint("BOTTOMRIGHT")
  btn.edgeBottom:SetHeight(2)
  btn.edgeLeft = Edge()
  btn.edgeLeft:SetPoint("TOPLEFT")
  btn.edgeLeft:SetPoint("BOTTOMLEFT")
  btn.edgeLeft:SetWidth(2)
  btn.edgeRight = Edge()
  btn.edgeRight:SetPoint("TOPRIGHT")
  btn.edgeRight:SetPoint("BOTTOMRIGHT")
  btn.edgeRight:SetWidth(2)
  btn:SetScript("OnClick", function(self)
    ViewBuild(self.profileName)
  end)
  btn:SetScript("OnEnter", function(self)
    if not GameTooltip or not self.profileName then
      return
    end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(FTK.Plain(self.profileName), 1, 0.82, 0)
    local build = self.profileSpec and Builds(self.profileSpec)
    local points = build and build[self.profileName] and build[self.profileName].points
    if points then
      GameTooltip:AddLine(tostring(points) .. " points", 0.8, 0.8, 0.8)
    end
    GameTooltip:AddLine("Click to view this build in the talent window. Click again to clear the preview.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  btn:SetScript("OnLeave", function()
    if GameTooltip then
      GameTooltip:Hide()
    end
  end)
  tabButtons[index] = btn
  return btn
end

local function HookPane(frame, pane)
  if pane.HookScript and not pane.ftkTalentProfileTabs then
    pane.ftkTalentProfileTabs = true
    pane:HookScript("OnShow", function()
      TouchTabs()
    end)
    pane:HookScript("OnHide", function()
      if profileTabs then
        profileTabs:Hide()
      end
    end)
  end
  if frame ~= pane and frame.HookScript and not frame.ftkTalentProfileTabs then
    frame.ftkTalentProfileTabs = true
    frame:HookScript("OnHide", function()
      if profileTabs then
        profileTabs:Hide()
      end
    end)
  end
end

RefreshSideTabs = function()
  if not tabsEnabled then
    if profileTabs then
      profileTabs:Hide()
    end
    return
  end
  local frame, pane = TalentHost()
  if not frame then
    return
  end
  HookPane(frame, pane)
  if not pane:IsShown() then
    if profileTabs then
      profileTabs:Hide()
    end
    return
  end
  local spec = ViewingSpec(pane)
  if profileTabs and profileTabs.specSeen and profileTabs.specSeen ~= spec then
    if viewedSpec ~= spec then
      viewedName, viewedSpec = nil, nil
    end
  end
  local names = SortedNames(spec)
  if #names == 0 then
    if profileTabs then
      profileTabs:Hide()
    end
    return
  end
  if not profileTabs then
    local ok, created = pcall(CreateFrame, "Frame", "ForeverForgeTalentProfileTabs", UIParent)
    if ok and type(created) == "table" then
      profileTabs = created
    else
      profileTabs = CreateFrame("Frame", "ForeverForgeTalentProfileTabs", UIParent)
    end
    profileTabs:EnableMouse(false)
    profileTabs:SetScript("OnUpdate", function(self, elapsed)
      self.t = (self.t or 0) + elapsed
      if self.t < 0.4 then
        return
      end
      self.t = 0
      if not tabsEnabled or not self:IsShown() then
        return
      end
      local _, openPane = TalentHost()
      if not openPane or not openPane:IsShown() then
        self:Hide()
        return
      end
      local openSpec = ViewingSpec(openPane)
      if openSpec ~= self.specSeen then
        RefreshSideTabs()
      end
    end)
  end
  profileTabs.specSeen = spec
  local width = 72
  local i
  for i = 1, #names do
    local guess = 18 + #names[i] * 7
    if guess > width then
      width = guess
    end
  end
  if width > 130 then
    width = 130
  end
  local height = 46
  local icon = SpecIcon(spec)
  for i = 1, math.max(#names, #tabButtons) do
    local name = names[i]
    if name then
      local btn = EnsureTabButton(i)
      btn.profileName = name
      btn.profileSpec = spec
      btn:SetSize(width, height)
      btn.label:SetWidth(width - 8)
      btn.label:SetText(FTK.Plain(name))
      btn.icon:SetTexture(icon)
      local selected = viewedName == name and viewedSpec == spec
      btn.icon:SetAlpha(selected and 1 or 0.82)
      PaintBorder(btn, selected)
      btn:ClearAllPoints()
      btn:SetPoint("TOPLEFT", profileTabs, "TOPLEFT", 0, -((i - 1) * (height + 4)))
      btn:Show()
    elseif tabButtons[i] then
      tabButtons[i]:Hide()
    end
  end
  profileTabs:SetSize(width, #names * (height + 4) - 4)
  profileTabs:ClearAllPoints()
  profileTabs:SetPoint("TOPLEFT", frame, "TOPRIGHT", 4, -6)
  local strata = frame.GetFrameStrata and frame:GetFrameStrata() or "MEDIUM"
  profileTabs:SetFrameStrata(strata)
  local level = frame.GetFrameLevel and frame:GetFrameLevel() or 1
  profileTabs:SetFrameLevel(level + 20)
  profileTabs:Show()
end

tabWatcher:SetScript("OnEvent", function(_, event, arg1)
  if not tabsEnabled then
    return
  end
  if event == "ADDON_LOADED" and arg1 ~= "Blizzard_PlayerSpells" and arg1 ~= "Blizzard_ClassTalentUI" and arg1 ~= "Blizzard_TalentUI" then
    return
  end
  RefreshSideTabs()
end)

local function Watch(event)
  pcall(tabWatcher.RegisterEvent, tabWatcher, event)
end

local tabsWatching = false

local function LoadTalentUI()
  local load = (C_AddOns and C_AddOns.LoadAddOn) or UIParentLoadAddOn or LoadAddOn
  if type(load) ~= "function" then
    return
  end
  pcall(load, "Blizzard_PlayerSpells")
  if not _G.PlayerSpellsFrame then
    pcall(load, "Blizzard_ClassTalentUI")
  end
  if not _G.PlayerSpellsFrame and not _G.ClassTalentFrame and not _G.PlayerTalentFrame then
    pcall(load, "Blizzard_TalentUI")
  end
end

local function StartTabs()
  tabsEnabled = true
  LoadTalentUI()
  if not tabsWatching then
    tabsWatching = true
    Watch("ADDON_LOADED")
    Watch("PLAYER_ENTERING_WORLD")
    Watch("PLAYER_SPECIALIZATION_CHANGED")
    Watch("ACTIVE_TALENT_GROUP_CHANGED")
  end
  TouchTabs()
end

local function StopTabs()
  tabsEnabled = false
  viewedName, viewedSpec = nil, nil
  if profileTabs then
    profileTabs:Hide()
  end
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
  note:SetText("Builds for this character and spec. They also show as tabs on the right of the talent window. Apply places points but does not commit them: review, then click Apply Changes.")
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
  description = "Save talent builds by name per character and spec. Each saved build is a spec-icon tab on the right of the talent window. Apply stages the points; you review and click Apply Changes. Needs a trainer reset if your committed points don't match.",
  defaultEnabled = true,
  BuildOptions = BuildOptions,
  onEnable = function()
    Config()
    StartTabs()
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
  onDisable = function()
    StopTabs()
  end,
})
