--[[
  Minimap button. Left-click toggles the toolkit menu. Drag moves the button
  around the minimap; the angle is saved.
]]

local FTK = ForeverForge
if not FTK then
  error("ForeverForge: Core.lua must load before Minimap.lua")
end

local DEFAULT_ANGLE = 200
local ICON_PATH = "Interface\\AddOns\\ForeverForge\\Textures\\Minimap"

local function ApplyTexture(texture, path, fileId)
  local ok = texture:SetTexture(path)
  if not ok and fileId then
    ok = texture:SetTexture(fileId)
  end
  return ok
end

function FTK:PlaceMinimapButton(btn, angle)
  if not btn or not Minimap then
    return
  end
  local placed = pcall(function()
    local use = angle
    if type(use) ~= "number" then
      use = self.db and self.db.minimap and self.db.minimap.angle
    end
    if type(use) ~= "number" then
      use = DEFAULT_ANGLE
    end
    local w = Minimap:GetWidth()
    if type(w) ~= "number" or w < 40 then
      w = 140
    end
    local radius = (w / 2) - 2
    local rad = math.rad(use)
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * radius, math.sin(rad) * radius)
  end)
  if placed then
    return
  end
  btn:ClearAllPoints()
  pcall(btn.SetPoint, btn, "CENTER", Minimap, "CENTER", -78, -24)
end

local function StopDrag(btn)
  btn.dragging = false
  btn:SetScript("OnUpdate", nil)
  if btn.UnlockHighlight then
    btn:UnlockHighlight()
  end
end

function FTK:CreateMinimapButton()
  local btn = CreateFrame("Button", "ForeverForgeMinimapButton", Minimap)
  btn:SetSize(40, 40)
  btn:SetFrameStrata("MEDIUM")
  btn:SetFrameLevel(8)
  btn:SetMovable(true)
  btn:EnableMouse(true)
  btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  btn:RegisterForDrag("LeftButton")

  local icon = btn:CreateTexture(nil, "ARTWORK")
  icon:SetAllPoints()
  local iconOk = ApplyTexture(icon, ICON_PATH)
  if iconOk then
    local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    ApplyTexture(highlight, ICON_PATH)
    if highlight.SetBlendMode then
      highlight:SetBlendMode("ADD")
    end
    highlight:SetAlpha(0.28)
  else
    icon:SetSize(17, 17)
    icon:ClearAllPoints()
    icon:SetPoint("CENTER")
    iconOk = ApplyTexture(icon, "Interface\\Icons\\INV_Misc_Wrench_01")
    if not iconOk then
      iconOk = ApplyTexture(icon, "Interface\\Icons\\Trade_Engineering")
    end
    if not iconOk and icon.SetColorTexture then
      icon:SetColorTexture(0.86, 0.7, 0.28, 1)
    end
  end

  btn:SetScript("OnDragStart", function(self)
    self.dragging = true
    self.wasDrag = true
    if self.LockHighlight then
      self:LockHighlight()
    end
    if GameTooltip then
      GameTooltip:Hide()
    end
    self:SetScript("OnUpdate", function(moving)
      local ok, nextAngle = pcall(function()
        local cx, cy = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        if type(scale) ~= "number" or scale < 0.01 then
          scale = 1
        end
        local mx, my = Minimap:GetCenter()
        return math.deg(math.atan2((cy / scale) - my, (cx / scale) - mx))
      end)
      if ok and type(nextAngle) == "number" and FTK.db and FTK.db.minimap then
        FTK.db.minimap.angle = nextAngle
        FTK:PlaceMinimapButton(moving, nextAngle)
      end
    end)
  end)

  btn:SetScript("OnDragStop", function(self)
    StopDrag(self)
  end)

  btn:SetScript("OnHide", function(self)
    StopDrag(self)
  end)

  btn:SetScript("OnMouseDown", function(self, button)
    if button ~= "LeftButton" then
      return
    end
    self.wasDrag = false
    local x, y = GetCursorPosition()
    self.pressX = x
    self.pressY = y
  end)

  btn:SetScript("OnMouseUp", function(self, button)
    if button ~= "LeftButton" then
      return
    end
    local dragged = self.wasDrag
    self.wasDrag = false
    if dragged then
      return
    end
    local x, y = GetCursorPosition()
    local dx = (x or 0) - (self.pressX or 0)
    local dy = (y or 0) - (self.pressY or 0)
    if (dx * dx) + (dy * dy) > 36 then
      return
    end
    if FTK.ToggleMenu then
      FTK:ToggleMenu()
    end
  end)

  btn:SetScript("OnEnter", function(self)
    if self.dragging or not GameTooltip then
      return
    end
    pcall(function()
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      GameTooltip:ClearLines()
      GameTooltip:SetText("Forever Forge")
      GameTooltip:AddLine("Left-click to open the menu", 1, 1, 1)
      GameTooltip:AddLine("Drag to move this button", 0.75, 0.75, 0.75)
      GameTooltip:Show()
    end)
  end)

  btn:SetScript("OnLeave", function()
    if GameTooltip then
      GameTooltip:Hide()
    end
  end)

  return btn
end

function FTK:InitMinimap()
  if not Minimap then
    return
  end
  if not self.minimapButton then
    local created, button = pcall(self.CreateMinimapButton, self)
    if not created or type(button) ~= "table" then
      if not self._minimapFailed then
        self._minimapFailed = true
        self:Print("Could not create the minimap button. Use /ff to open the menu.")
      end
      return
    end
    self.minimapButton = button
  end
  if not self.minimapButton.dragging then
    self:PlaceMinimapButton(self.minimapButton)
  end
end

function FTK:ResetMinimap()
  self:InitDB()
  self.db.minimap.angle = DEFAULT_ANGLE
  self:InitMinimap()
end
