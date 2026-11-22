--[[
  Exercises Clean Bags reagent slots outside the game.
  Run with: node tests/run-reagent-bag.js
]]

local failures = 0
local function check(cond, message)
  if not cond then
    failures = failures + 1
    print("FAIL: " .. tostring(message))
  end
end

local calls = {}
local function record(name, ...)
  calls[#calls + 1] = { name = name, n = select("#", ...), ... }
end

local function resetCalls()
  calls = {}
end

local function saw(name, bag, slot)
  local index
  for index = 1, #calls do
    local call = calls[index]
    if call.name == name and call[1] == bag and call[2] == slot then
      return true
    end
  end
  return false
end

local function countNamed(name)
  local total = 0
  local index
  for index = 1, #calls do
    if calls[index].name == name then
      total = total + 1
    end
  end
  return total
end

local modifiers = {}
local cursorHolding = false
local spellTarget = false
local timers = {}

local function noop()
end

local function makeRegion()
  local region = {}
  local methods = {
    SetAllPoints = noop,
    SetColorTexture = noop,
    SetPoint = noop,
    SetHeight = noop,
    SetWidth = noop,
    SetJustifyH = noop,
    SetWordWrap = noop,
    SetTextColor = noop,
    ClearAllPoints = noop,
    SetText = noop,
    GetStringWidth = function()
      return 48
    end,
    Hide = noop,
    Show = noop,
  }
  setmetatable(region, {
    __index = function(_, key)
      return methods[key] or noop
    end,
  })
  return region
end

local function removeChild(parent, child)
  if not parent or not parent._children then
    return
  end
  local index
  local nextChildren = {}
  for index = 1, #parent._children do
    if parent._children[index] ~= child then
      nextChildren[#nextChildren + 1] = parent._children[index]
    end
  end
  parent._children = nextChildren
end

local frames = {}

local function CreateFrame(_kind, name, parent, template)
  local frame = {
    _name = name,
    _parent = nil,
    _template = template,
    _scripts = {},
    _attr = {},
    _shown = false,
    _id = 0,
    _width = 37,
    _height = 37,
    _strata = "MEDIUM",
    _level = 1,
    _mouse = true,
    _children = {},
    _clicks = {},
    _pass = {},
    _propagateMotion = false,
    _raiseOnResize = false,
  }

  function frame:SetScript(script, fn)
    self._scripts[script] = fn
  end
  function frame:GetScript(script)
    return self._scripts[script]
  end
  function frame:HookScript(script, fn)
    local prev = self._scripts[script]
    self._scripts[script] = function(...)
      if prev then
        prev(...)
      end
      return fn(...)
    end
  end
  function frame:SetAttribute(key, value)
    self._attr[key] = value
  end
  function frame:GetAttribute(key)
    return self._attr[key]
  end
  function frame:SetID(id)
    self._id = id
  end
  function frame:GetID()
    return self._id
  end
  function frame:GetParent()
    return self._parent
  end
  function frame:SetParent(nextParent)
    if self._parent == nextParent then
      return
    end
    removeChild(self._parent, self)
    self._parent = nextParent
    if nextParent then
      nextParent._children[#nextParent._children + 1] = self
      if self._level <= nextParent._level then
        self._level = nextParent._level + 1
      end
    end
  end
  function frame:Show()
    self._shown = true
  end
  function frame:Hide()
    self._shown = false
    local script = self._scripts.OnHide
    if script then
      script(self)
    end
  end
  function frame:IsShown()
    if not self._shown then
      return false
    end
    if self._parent and not self._parent:IsShown() then
      return false
    end
    return true
  end
  function frame:SetWidth(width)
    self._width = width
  end
  function frame:SetHeight(height)
    self._height = height
    if self._raiseOnResize then
      self._level = self._level + 500
    end
  end
  function frame:SetSize(width, height)
    self._width = width
    self._height = height
  end
  function frame:GetWidth()
    return self._width
  end
  function frame:GetHeight()
    return self._height
  end
  function frame:SetFrameStrata(strata)
    self._strata = strata
  end
  function frame:GetFrameStrata()
    return self._strata
  end
  function frame:SetFrameLevel(level)
    self._level = level
    local index
    for index = 1, #self._children do
      local child = self._children[index]
      if child._level <= level then
        child._level = level + 1
      end
    end
  end
  function frame:GetFrameLevel()
    return self._level
  end
  function frame:EnableMouse(enabled)
    self._mouse = enabled ~= false
  end
  function frame:EnableMouseWheel()
  end
  function frame:RegisterForClicks(...)
    self._clicks = { ... }
  end
  function frame:RegisterForDrag()
  end
  function frame:SetPassThroughButtons(...)
    self._pass = { ... }
  end
  function frame:SetPropagateMouseMotion(enabled)
    self._propagateMotion = enabled == true
  end
  function frame:RegisterEvent(event)
    self._events = self._events or {}
    self._events[event] = true
    if event == "MERCHANT_SHOW" then
      merchantEvents = self
    end
  end
  function frame:UnregisterEvent()
  end
  function frame:UnregisterAllEvents()
  end
  function frame:SetPoint()
  end
  function frame:ClearAllPoints()
  end
  function frame:SetAllPoints(other)
    self._anchorAll = other or true
  end
  function frame:CreateTexture()
    return makeRegion()
  end
  function frame:CreateFontString()
    return makeRegion()
  end
  function frame:Raise()
    self._level = self._level + 100
  end
  function frame:IsCombinedBagContainer()
    return self._combined == true
  end

  if template and type(template) == "string" and template:find("ContainerFrameItemButton", 1, true) then
    frame._templateClick = function(self, mouseButton)
      local parent = self:GetParent()
      local bag = parent and parent.GetID and parent:GetID() or -1
      record("templateClick", bag, self:GetID(), mouseButton)
    end
    frame.OnClick = frame._templateClick
    frame._scripts.OnClick = frame._templateClick
    frame.GetBagID = function(self)
      local parent = self:GetParent()
      if parent and parent.GetBagID then
        return parent:GetBagID()
      end
      return parent and parent:GetID() or 0
    end
    frame.SetBagID = function(self, id)
      record("SetBagID", id)
      self._setBag = id
    end
  end

  frame:SetParent(parent)
  if name then
    _G[name] = frame
  end
  frames[#frames + 1] = frame
  return frame
end

_G.CreateFrame = CreateFrame

UIParent = CreateFrame("Frame", "UIParent")
UIParent:Show()

local loginFrame
local merchantEvents
local oldRegister = UIParent.RegisterEvent
function UIParent:RegisterEvent(event)
  if event == "PLAYER_LOGIN" then
    loginFrame = self
  end
  return oldRegister(self, event)
end

-- CreateFrame copies RegisterEvent per frame, so watch every new frame.
local baseCreate = CreateFrame
_G.CreateFrame = function(kind, name, parent, template)
  local frame = baseCreate(kind, name, parent, template)
  local register = frame.RegisterEvent
  function frame:RegisterEvent(event)
    if event == "PLAYER_LOGIN" then
      loginFrame = self
    end
    if event == "MERCHANT_SHOW" then
      merchantEvents = self
    end
    return register(self, event)
  end
  return frame
end

C_Timer = {
  After = function(_delay, fn)
    timers[#timers + 1] = fn
  end,
}

local function flushTimers()
  local guard = 0
  while #timers > 0 and guard < 20 do
    guard = guard + 1
    local pending = timers
    timers = {}
    local index
    for index = 1, #pending do
      pending[index]()
    end
  end
end

function InCombatLockdown()
  return false
end

function hooksecurefunc(owner, name, fn)
  if type(owner) == "string" then
    fn = name
    name = owner
    local previous = _G[name]
    _G[name] = function(...)
      if previous then
        previous(...)
      end
      fn(...)
    end
    return
  end
  local previous = owner[name]
  owner[name] = function(...)
    if previous then
      previous(...)
    end
    fn(...)
  end
end

function SecureHandlerWrapScript(frame, script, _header, preBody)
  frame._wrap = preBody
  frame._wrapScript = script
  record("wrap", script)
end

Enum = { BagIndex = { ReagentBag = 5 } }
ContainerFrameMixin = { UpdateItemLayout = function() end }
ContainerFrameSettingsManager = {
  IsUsingCombinedBags = function()
    return true
  end,
}

local items = {
  [0] = {
    [1] = {
      itemID = 100,
      hyperlink = "|cff0070dd|Hitem:100::::::::|h[Pack Lunch]|h|r",
      stackCount = 1,
      quality = 1,
      iconFileID = 10,
    },
  },
  [5] = {
    [1] = {
      itemID = 201,
      hyperlink = "|cff1eff00|Hitem:201::::::::|h[Silverleaf]|h|r",
      stackCount = 5,
      quality = 2,
      iconFileID = 20,
    },
    [2] = {
      itemID = 202,
      hyperlink = "|cff9d9d9d|Hitem:202::::::::|h[Broken Fang]|h|r",
      stackCount = 1,
      quality = 0,
      iconFileID = 30,
      isLocked = false,
    },
  },
}

C_Container = {
  GetContainerNumSlots = function(bag)
    if bag == 5 then
      return 3
    end
    if bag == 0 then
      return 16
    end
    return 0
  end,
  GetContainerItemInfo = function(bag, slot)
    local bagItems = items[bag]
    return bagItems and bagItems[slot] or nil
  end,
  GetContainerItemLink = function(bag, slot)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    return info and info.hyperlink or nil
  end,
  PickupContainerItem = function(bag, slot)
    record("pickup", bag, slot)
  end,
  UseContainerItem = function(bag, slot)
    record("use", bag, slot)
  end,
  SplitContainerItem = function(bag, slot, amount)
    record("split", bag, slot, amount)
  end,
}

C_Item = {
  GetItemInfoInstant = function(itemID)
    return itemID, "Trade Goods", "Herb", "", 1, 7, 0
  end,
}

function SetItemButtonTexture()
end
function SetItemButtonCount()
end
function SetItemButtonQuality()
end

MerchantFrame = {
  selectedTab = 1,
  shown = false,
  IsShown = function(self)
    return self.shown == true
  end,
}

GameTooltip = {
  owner = nil,
  bag = nil,
  slot = nil,
  SetOwner = function(self, owner)
    self.owner = owner
  end,
  SetBagItem = function(self, bag, slot)
    self.bag = bag
    self.slot = slot
    record("tooltip", bag, slot)
  end,
  Hide = function(self)
    self.owner = nil
  end,
}

function IsModifiedClick(which)
  if which == nil then
    return modifiers.any == true
  end
  return modifiers[which] == true
end

function HandleModifiedItemClick(link)
  record("link", link)
  return modifiers.link == true
end

function CursorHasItem()
  return cursorHolding
end

function SpellCanTargetItem()
  return spellTarget
end

function OpenStackSplitFrame(count, button)
  record("openSplit", count, button and button:GetID())
end

local function click(button, mouseButton)
  local script = button:GetScript("OnClick")
  check(type(script) == "function", "reagent slot has an OnClick script")
  script(button, mouseButton)
end

local function loadSource(name, source)
  local chunk, err = load(source, "@" .. name)
  if not chunk then
    error(err)
  end
  chunk()
end

loadSource("Core.lua", CORE_SRC)
loadSource("Modules/BagSections.lua", BAG_SRC)

local combined = CreateFrame("Frame", "ContainerFrameCombinedBags", UIParent)
combined._combined = true
combined._raiseOnResize = true
combined:SetFrameLevel(10)
combined:Show()
combined.Items = {}

local pack = CreateFrame("ItemButton", "ContainerFrame1Item1", combined, "ContainerFrameItemButtonTemplate")
pack:SetID(1)
pack.GetBagID = function()
  return 0
end
pack:Show()
combined.Items[1] = pack

function combined:EnumerateValidItems()
  return ipairs(self.Items)
end
function combined:GetColumns()
  return 4
end

check(loginFrame ~= nil, "login frame was created")
loginFrame:GetScript("OnEvent")(loginFrame, "PLAYER_LOGIN")
flushTimers()

local slot1 = _G.ForeverForgeReagentButton1
local slot2 = _G.ForeverForgeReagentButton2
local slot3 = _G.ForeverForgeReagentButton3
check(slot1 ~= nil and slot2 ~= nil and slot3 ~= nil, "reagent slots were built")
check(slot1:IsShown() and slot2:IsShown() and slot3:IsShown(), "reagent slots are shown")

local function sabotageParent(button)
  local parent = button:GetParent()
  parent:SetID(0)
  parent.GetBagID = function()
    return 0
  end
end

sabotageParent(slot1)
sabotageParent(slot2)
sabotageParent(slot3)

check(slot1:GetBagID() == 5, "slot 1 bag id stays 5 when the parent says 0")
check(slot1:GetID() == 1 and slot2:GetID() == 2 and slot3:GetID() == 3, "slot ids are the reagent slots")
check(slot1:GetScript("OnClick") ~= slot1._templateClick, "template click was replaced")
check(slot1.OnClick == slot1:GetScript("OnClick"), "method and script are the same handler")
check(countNamed("SetBagID") == 0, "SetBagID was not called")
check(pack:GetScript("OnClick") == pack._templateClick, "backpack button kept its own click")

local function overlayOf(button)
  return button.ftkUseOverlay
end

local function assertOverlay(button, slot, label)
  local overlay = overlayOf(button)
  check(overlay ~= nil, label .. " has a use button")
  if not overlay then
    return
  end
  check(overlay:GetParent() == button, label .. " use button is parented to the slot")
  check(overlay:IsShown(), label .. " use button is shown")
  check(overlay:GetFrameLevel() > button:GetFrameLevel(), label .. " use button is above the slot")
  check(overlay:GetAttribute("type2") == "item", label .. " right-click action is item")
  check(overlay:GetAttribute("item2") == "5 " .. slot, label .. " item attribute is bag 5 slot " .. slot)
  check(overlay:GetAttribute("bag2") == 5, label .. " bag attribute is 5")
  check(overlay:GetAttribute("slot2") == slot, label .. " slot attribute is " .. slot)
  check(overlay._pass[1] == "LeftButton", label .. " lets left clicks through")
  check(overlay._propagateMotion == true, label .. " forwards mouse motion for the tooltip")
  check(type(overlay._wrap) == "string", label .. " guards buyback")
  local parsedBag, parsedSlot = (overlay:GetAttribute("item2") or ""):match("^(%d+)%s+(%d+)$")
  check(parsedBag == "5" and tonumber(parsedSlot) == slot, label .. " parses as bag 5, not an item name")
end

assertOverlay(slot1, 1, "slot 1")
assertOverlay(slot2, 2, "slot 2")
assertOverlay(slot3, 3, "empty slot")

-- Resize raises the bag. The use button has to end above the slot.
combined:SetFrameLevel(10)
local mixinLayout = ContainerFrameMixin.UpdateItemLayout
mixinLayout(combined)
flushTimers()
assertOverlay(slot1, 1, "slot 1 after resize")
sabotageParent(slot1)

resetCalls()
click(slot1, "LeftButton")
check(saw("pickup", 5, 1), "left click picks up reagent bag slot 1")
check(not saw("pickup", 0, 1), "left click does not pick up the backpack")
check(countNamed("use") == 0, "left click does not use the item")
check(countNamed("templateClick") == 0, "template parent-id click did not run")

resetCalls()
slot2:GetScript("OnDragStart")(slot2)
check(saw("pickup", 5, 2), "drag picks up reagent bag slot 2")

resetCalls()
slot3:GetScript("OnReceiveDrag")(slot3)
check(saw("pickup", 5, 3), "drop on an empty reagent slot uses that slot")

resetCalls()
cursorHolding = true
modifiers.any = true
click(slot3, "LeftButton")
check(saw("pickup", 5, 3), "placing a held item still picks up the reagent slot")
check(countNamed("link") == 0, "a held item is not turned into a link")
cursorHolding = false
modifiers.any = false

resetCalls()
modifiers.any = true
modifiers.link = true
click(slot1, "LeftButton")
check(saw("link", items[5][1].hyperlink), "shift-click links the reagent item")
check(countNamed("pickup") == 0, "shift-click does not pick the item up")
modifiers.any = false
modifiers.link = false

resetCalls()
modifiers.any = true
modifiers.SPLITSTACK = true
click(slot1, "LeftButton")
check(saw("openSplit", 5, 1), "split modifier opens the stack frame for the reagent stack")
check(countNamed("pickup") == 0, "splitting does not pick the stack up")
slot1:SplitStack(2)
check(saw("split", 5, 1), "the stack frame splits the reagent slot")
modifiers.any = false
modifiers.SPLITSTACK = false

resetCalls()
spellTarget = true
click(slot2, "LeftButton")
check(saw("use", 5, 2), "a spell that wants an item uses the reagent slot")
check(countNamed("pickup") == 0, "spell targeting does not pick the item up")
spellTarget = false

resetCalls()
slot1:GetScript("OnEnter")(slot1)
check(saw("tooltip", 5, 1), "tooltip reads reagent bag slot 1")

-- At a vendor the slot sells even while the use button is still on top.
MerchantFrame.shown = true
MerchantFrame.selectedTab = 1
resetCalls()
click(slot2, "RightButton")
check(saw("use", 5, 2), "right-click at a vendor sells reagent slot 2")
check(not saw("use", 0, 2), "vendor sell does not use the backpack")

check(merchantEvents ~= nil, "merchant events are registered")
if merchantEvents then
  merchantEvents:GetScript("OnEvent")(merchantEvents, "MERCHANT_SHOW")
  flushTimers()
end
check(not slot2.ftkUseOverlay:IsShown(), "the vendor buy tab hides the use button")
check(slot2.ftkUseOverlay:GetAttribute("type2") == nil, "the use button does not also act at a vendor")
slot2:GetScript("OnEnter")(slot2)
check(not slot2.ftkUseOverlay:IsShown(), "pointing at a slot at a vendor leaves the use button off")
resetCalls()
click(slot2, "RightButton")
check(saw("use", 5, 2), "right-click still sells after the use button hides")

MerchantFrame.selectedTab = 2
if merchantEvents then
  merchantEvents:GetScript("OnEvent")(merchantEvents, "MERCHANT_SHOW")
  flushTimers()
end
resetCalls()
click(slot2, "RightButton")
check(countNamed("use") == 0, "buyback does not sell the reagent item")

MerchantFrame.shown = false
MerchantFrame.selectedTab = 1
if merchantEvents then
  merchantEvents:GetScript("OnEvent")(merchantEvents, "MERCHANT_CLOSED")
  flushTimers()
end
check(slot1.ftkUseOverlay:IsShown(), "closing the vendor shows the use button again")
-- The use button is on top again, so the slot must not use the item too.
resetCalls()
click(slot1, "RightButton")
check(countNamed("use") == 0, "covered right-click outside a vendor does not use the item twice")

-- The use button can be left hidden: the bag key hides it, another window
-- re-seats the chrome. A click on the bare slot must not use the item from
-- this addon's own button. The client blocks that call ("Blocked action").
slot1.ftkUseOverlay:Hide()
resetCalls()
click(slot1, "RightButton")
check(countNamed("use") == 0, "right-click on an uncovered slot makes no blocked use call")
check(slot1.ftkUseOverlay:IsShown(), "right-click on an uncovered slot puts the use button back")

-- Pointing at the slot puts the use button back before the click lands.
slot1.ftkUseOverlay:Hide()
slot1:GetScript("OnEnter")(slot1)
check(slot1.ftkUseOverlay:IsShown(), "pointing at a slot puts its use button back")

-- The use button can sit under the slot after a resize. The slot still sells.
slot1.ftkUseOverlay:Show()
slot1.ftkUseOverlay._level = slot1:GetFrameLevel()
MerchantFrame.shown = true
MerchantFrame.selectedTab = 1
resetCalls()
click(slot1, "RightButton")
check(saw("use", 5, 1), "a use button under the slot still sells that reagent item")

slot1.ftkUseOverlay:Show()
mixinLayout(combined)
flushTimers()
sabotageParent(slot1)

local function runWrap(body, mouseButton, down)
  local chunk = assert(load(
    "return function(self, button, down)\n" .. body .. "\nend",
    "reagent-use-pre"
  ))
  local fn = chunk()
  return fn(slot1.ftkUseOverlay, mouseButton, down)
end

MerchantFrame.shown = true
MerchantFrame.selectedTab = 2
check(runWrap(slot1.ftkUseOverlay._wrap, "RightButton", false) == false, "secure click cancels sell on the buyback tab")
MerchantFrame.selectedTab = 1
check(runWrap(slot1.ftkUseOverlay._wrap, "RightButton", false) == nil, "secure click still sells on the buy tab")
MerchantFrame.shown = false
check(runWrap(slot1.ftkUseOverlay._wrap, "RightButton", false) == nil, "secure click still uses the item with no merchant")

-- A second open keeps each slot on its own item.
mixinLayout(combined)
flushTimers()
check(slot1.ftkUseOverlay:GetAttribute("item2") == "5 1", "slot 1 keeps its own item")
check(slot2.ftkUseOverlay:GetAttribute("item2") == "5 2", "slot 2 keeps its own item")
check(slot1.ftkUseOverlay:GetFrameLevel() > slot1:GetFrameLevel(), "use button stays above the slot")
check(type(slot1.ftkUseOverlay._wrap) == "string" and slot1.ftkUseOverlay._wrap:find("selectedTab == 2", 1, true) ~= nil, "buyback guard was installed")

if failures > 0 then
  error(failures .. " reagent bag check(s) failed")
end
print("reagent bag checks passed")
