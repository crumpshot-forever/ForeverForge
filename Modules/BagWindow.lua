--[[
  Scrolling and resizing for Clean Bags and Clean Bank.

  A view adds a size grip and a scroll bar to a host frame that lies over
  a bag window, and scrolls on the mouse wheel over the window's item
  area. The grip sits in the corner opposite the window's anchor, so the
  window grows away from the point the game keeps fixed. Layout code asks
  the view where a row of the content shows; a row outside the visible
  area gets nil, and the layout hides what is there.

  The saved size is the largest size the player wants: the window still
  shrinks to its content and to the screen. It lives in the module's
  config as window = { width, height }, in the window's own units.

  Hidden item buttons can be protected Blizzard buttons. Combat lockdown
  starts after PLAYER_REGEN_DISABLED, so the owner calls Reveal from that
  event and every item is back in view before lockdown begins.
]]

local FTK = ForeverForge
if not FTK then
  error("ForeverForge: Core.lua must load before Modules/BagWindow.lua")
end

local GRIP_SIZE = 16
local GRIP_INSET = 2
local BAR_WIDTH = 8
local BAR_INSET = 3
local THUMB_MIN = 24
local SCREEN_MARGIN = 20
local GRIP_TEXTURES = {
  normal = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up",
  highlight = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight",
  pushed = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down",
}

local Window = {}

local View = {}
View.__index = View

-- Saved size table of the view's module.
local function SavedTable(self)
  local config = FTK:GetConfig(self.options.moduleID)
  if type(config.window) ~= "table" then
    config.window = {}
  end
  return config.window
end

-- Scrolls to `value`, kept inside the scroll range.
local function SetOffset(self, value)
  if value > self.maxOffset then
    value = self.maxOffset
  end
  if value < 0 then
    value = 0
  end
  value = math.floor(value + 0.5)
  if value == self.offset then
    return
  end
  self.offset = value
  self.options.onChange()
end

local function StopDrag(self)
  self.drag = nil
  if self.grip then
    self.grip:SetScript("OnUpdate", nil)
  end
end

-- Follows the cursor while the grip is held and saves the new size.
local function DragTo(self)
  local drag = self.drag
  if not drag or InCombatLockdown() then
    StopDrag(self)
    return
  end
  local x, y = GetCursorPosition()
  local dx = (x - drag.x) / drag.scale
  local dy = (y - drag.y) / drag.scale
  local width, height
  if self.options.corner == "TOPLEFT" then
    width, height = drag.width - dx, drag.height + dy
  else
    width, height = drag.width + dx, drag.height - dy
  end
  width = math.max(math.floor(width + 0.5), self.options.minWidth)
  height = math.max(math.floor(height + 0.5), self.options.minHeight)
  local saved = SavedTable(self)
  if saved.width ~= width or saved.height ~= height then
    saved.width = width
    saved.height = height
    self.options.onChange()
  end
end

local function StartDrag(self, mouseButton)
  if mouseButton ~= "LeftButton" or not self.frame or InCombatLockdown() then
    return
  end
  local x, y = GetCursorPosition()
  self.drag = {
    x = x,
    y = y,
    scale = self.frame:GetEffectiveScale(),
    width = self.frame:GetWidth(),
    height = self.frame:GetHeight(),
  }
  self.grip:SetScript("OnUpdate", function()
    DragTo(self)
  end)
end

-- Creates the grip and the scroll bar on the host frame once.
local function EnsureWidgets(self, host)
  if self.grip then
    return
  end
  local grip = CreateFrame("Button", nil, host)
  grip:SetSize(GRIP_SIZE, GRIP_SIZE)
  grip:SetNormalTexture(GRIP_TEXTURES.normal)
  grip:SetHighlightTexture(GRIP_TEXTURES.highlight)
  grip:SetPushedTexture(GRIP_TEXTURES.pushed)
  if self.options.corner == "TOPLEFT" then
    -- The game's grip art points to the bottom right; mirror it.
    local textures = { grip:GetNormalTexture(), grip:GetHighlightTexture(), grip:GetPushedTexture() }
    for index = 1, #textures do
      textures[index]:SetTexCoord(1, 0, 1, 0)
    end
  end
  grip:SetScript("OnMouseDown", function(_, mouseButton)
    StartDrag(self, mouseButton)
  end)
  grip:SetScript("OnMouseUp", function()
    StopDrag(self)
  end)
  grip:SetScript("OnHide", function()
    StopDrag(self)
  end)
  grip:Hide()
  self.grip = grip

  local bar = CreateFrame("Slider", nil, host)
  bar:SetOrientation("VERTICAL")
  bar:SetWidth(BAR_WIDTH)
  local track = bar:CreateTexture(nil, "BACKGROUND")
  track:SetAllPoints()
  track:SetColorTexture(0, 0, 0, 0.35)
  local thumb = bar:CreateTexture(nil, "ARTWORK")
  thumb:SetColorTexture(0.78, 0.64, 0.32, 0.9)
  thumb:SetSize(BAR_WIDTH, THUMB_MIN)
  bar:SetThumbTexture(thumb)
  bar.thumb = thumb
  bar:SetValueStep(1)
  if bar.SetObeyStepOnDrag then
    bar:SetObeyStepOnDrag(true)
  end
  bar:SetScript("OnValueChanged", function(_, value)
    if not self.syncing then
      SetOffset(self, value)
    end
  end)
  bar:Hide()
  self.bar = bar
end

-- Scrolls with the mouse wheel over the item area. Hooked once per frame;
-- the game's own wheel handler, if any, still runs.
local function HookWheel(self, area)
  if self.wheelHooked[area] or not area.HookScript then
    return
  end
  self.wheelHooked[area] = true
  if area.EnableMouseWheel then
    area:EnableMouseWheel(true)
  end
  area:HookScript("OnMouseWheel", function(_, delta)
    if self.area == area and self.maxOffset > 0 then
      SetOffset(self, self.offset - (delta * self.step))
    end
  end)
end

-- Creates a view. options:
--   moduleID             module whose config keeps the saved size
--   corner               "TOPLEFT" for a window anchored at its bottom right
--                        (it grows up and left), "BOTTOMRIGHT" for a window
--                        anchored at its top left (it grows down and right)
--   minWidth, minHeight  smallest size the grip allows
--   onChange             called when the scroll offset or the saved size changes
function Window.NewView(options)
  return setmetatable({
    options = options,
    offset = 0,
    maxOffset = 0,
    viewTop = 0,
    viewHeight = 0,
    step = 40,
    tracked = {},
    hiddenCount = 0,
    wheelHooked = setmetatable({}, { __mode = "k" }),
  }, View)
end

-- Saved width and height; nil for a size the player never set.
function View:SavedSize()
  local saved = SavedTable(self)
  local width = type(saved.width) == "number" and saved.width or nil
  local height = type(saved.height) == "number" and saved.height or nil
  return width, height
end

-- Height the window can grow to on screen, in its own units, or nil while
-- it has no position yet.
function View:AvailableHeight(frame)
  local scale = frame:GetEffectiveScale()
  if not scale or scale <= 0 then
    return nil
  end
  if self.options.corner == "TOPLEFT" then
    local bottom = frame:GetBottom()
    local screenTop = UIParent:GetTop()
    if not bottom or not screenTop then
      return nil
    end
    return (screenTop * UIParent:GetEffectiveScale() / scale) - bottom - SCREEN_MARGIN
  end
  local top = frame:GetTop()
  if not top then
    return nil
  end
  return top - SCREEN_MARGIN
end

-- Starts a layout pass. host carries the widgets, frame is the window
-- (grip corner, scale), area the frame whose top the item rows hang from.
-- viewTop and viewHeight mark the visible item area inside area,
-- contentHeight is the height of all rows, step the wheel scroll distance.
function View:Begin(host, frame, area, viewTop, viewHeight, contentHeight, step)
  EnsureWidgets(self, host)
  HookWheel(self, area)
  self.frame = frame
  self.area = area
  self.viewTop = viewTop
  self.viewHeight = viewHeight
  self.step = step
  self.maxOffset = math.max(0, math.floor(contentHeight - viewHeight + 0.5))
  if self.offset > self.maxOffset then
    self.offset = self.maxOffset
  end
  self.tracked = {}
  self.hiddenCount = 0

  local corner = self.options.corner
  local insetX = corner == "TOPLEFT" and GRIP_INSET or -GRIP_INSET
  local insetY = corner == "TOPLEFT" and -GRIP_INSET or GRIP_INSET
  self.grip:ClearAllPoints()
  self.grip:SetPoint(corner, frame, corner, insetX, insetY)
  self.grip:Show()

  local bar = self.bar
  if self.maxOffset <= 0 then
    bar:Hide()
    return
  end
  bar:ClearAllPoints()
  bar:SetPoint("TOPRIGHT", area, "TOPRIGHT", -BAR_INSET, -viewTop)
  bar:SetHeight(viewHeight)
  bar.thumb:SetHeight(math.max(THUMB_MIN, viewHeight * viewHeight / contentHeight))
  self.syncing = true
  bar:SetMinMaxValues(0, self.maxOffset)
  bar:SetValue(self.offset)
  self.syncing = false
  bar:Show()
end

-- Room the scroll bar takes at the right edge while it shows.
function View:BarRoom()
  if self.maxOffset > 0 then
    return BAR_WIDTH + BAR_INSET + 2
  end
  return 0
end

-- Distance from the top of area for a content row at contentY (from the
-- top of the content) that is `height` tall, or nil when the row is not
-- fully inside the visible area.
function View:Locate(contentY, height)
  local top = contentY - self.offset
  if top < -0.5 or top + height > self.viewHeight + 0.5 then
    return nil
  end
  return self.viewTop + top
end

-- Like Locate, and remembers the item button for Reveal.
function View:Track(button, x, contentY, height)
  local top = self:Locate(contentY, height)
  self.tracked[#self.tracked + 1] = { button = button, x = x, top = self.viewTop + contentY }
  if not top then
    self.hiddenCount = self.hiddenCount + 1
  end
  return top
end

-- Puts every tracked item back at its unscrolled place through
-- place(button, x, top). Does nothing when no item is hidden.
-- Returns true when items were moved.
function View:Reveal(place)
  if self.hiddenCount == 0 then
    return false
  end
  for index = 1, #self.tracked do
    local entry = self.tracked[index]
    place(entry.button, entry.x, entry.top)
  end
  self.hiddenCount = 0
  return true
end

-- Hides the grip and the scroll bar.
function View:HideWidgets()
  StopDrag(self)
  if self.grip then
    self.grip:Hide()
  end
  if self.bar then
    self.bar:Hide()
  end
  self.maxOffset = 0
end

FTK.BagWindow = Window
