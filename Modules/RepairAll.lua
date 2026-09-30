--[[
  Repairs all damaged gear when a repair merchant opens.
  Prefer guild bank funds when the option is on and the game allows it.
  Non-repair merchants are skipped. Does not touch bag or merchant UI.
]]

local FTK = ForeverForge
if not FTK then
  error("ForeverForge: Core.lua must load before Modules/RepairAll.lua")
end

local MODULE_ID = "RepairAll"

local frame = CreateFrame("Frame")
local session = 0

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

local function Config()
  local cfg = FTK:GetConfig(MODULE_ID)
  if cfg.useGuildFunds == nil then
    cfg.useGuildFunds = false
  end
  return cfg
end

local function MerchantOpen()
  if not MerchantFrame or not MerchantFrame.IsShown then
    return false
  end
  local ok, shown = pcall(MerchantFrame.IsShown, MerchantFrame)
  return ok and shown == true
end

local function CanRepairHere()
  if type(CanMerchantRepair) ~= "function" then
    return false
  end
  local ok, can = pcall(CanMerchantRepair)
  if not ok or IsSecret(can) then
    return false
  end
  return can == true
end

local function RepairCost()
  if type(GetRepairAllCost) ~= "function" then
    return nil, false
  end
  local ok, cost, canRepair = pcall(GetRepairAllCost)
  if not ok then
    return nil, false
  end
  cost = PlainNumber(cost)
  if IsSecret(canRepair) then
    return cost, false
  end
  return cost, canRepair == true
end

local function PlayerMoney()
  if type(GetMoney) ~= "function" then
    return nil
  end
  local ok, money = pcall(GetMoney)
  if not ok then
    return nil
  end
  return PlainNumber(money)
end

local function GuildCanRepair(cost)
  if type(CanGuildBankRepair) ~= "function" then
    return false
  end
  local ok, can = pcall(CanGuildBankRepair)
  if not ok or IsSecret(can) or can ~= true then
    return false
  end
  -- Some clients expose GetGuildBankWithdrawMoney; treat missing as allowed.
  if type(GetGuildBankWithdrawMoney) == "function" and cost then
    local withdrawOk, limit = pcall(GetGuildBankWithdrawMoney)
    limit = withdrawOk and PlainNumber(limit) or nil
    -- -1 often means unlimited. A finite limit below cost means skip guild.
    if limit ~= nil and limit >= 0 and limit < cost then
      return false
    end
  end
  return true
end

local function CoinText(copper)
  copper = PlainNumber(copper)
  if not copper or copper < 0 then
    return "0c"
  end
  if type(GetCoinTextureString) == "function" then
    local ok, text = pcall(GetCoinTextureString, copper)
    if ok and type(text) == "string" and text ~= "" and not IsSecret(text) then
      return text
    end
  end
  local g = math.floor(copper / 10000)
  local s = math.floor((copper % 10000) / 100)
  local c = copper % 100
  local parts = {}
  if g > 0 then
    parts[#parts + 1] = g .. "g"
  end
  if s > 0 or g > 0 then
    parts[#parts + 1] = s .. "s"
  end
  parts[#parts + 1] = c .. "c"
  return table.concat(parts, " ")
end

-- Coin texture strings use |T ... |t. FTK:Print escapes |, so print those
-- with the Forever Forge prefix without running Plain on the coin segment.
local function PrintRepair(message, copper)
  local coin = CoinText(copper)
  local body = message .. coin
  local chat = _G.DEFAULT_CHAT_FRAME
  if chat and chat.AddMessage and type(coin) == "string" and coin:find("|T", 1, true) then
    chat:AddMessage("|cffe0c36aForever Forge|r: " .. FTK.Plain(message) .. coin)
    return
  end
  FTK:Print(body)
end

local function TryRepair()
  if not FTK:IsEnabled(MODULE_ID) then
    return
  end
  if not MerchantOpen() then
    return
  end
  if not CanRepairHere() then
    return
  end
  local cost, canRepair = RepairCost()
  if not canRepair or not cost or cost <= 0 then
    return
  end

  local cfg = Config()
  local useGuild = cfg.useGuildFunds == true and GuildCanRepair(cost)
  if useGuild then
    if type(RepairAllItems) == "function" then
      local ok = pcall(RepairAllItems, true)
      if ok then
        PrintRepair("Repair All: guild funds paid ", cost)
        return
      end
    end
    -- Fall through to player gold if guild repair failed.
    useGuild = false
  end

  local money = PlayerMoney()
  if money == nil or money < cost then
    local coin = CoinText(cost)
    local chat = _G.DEFAULT_CHAT_FRAME
    if chat and chat.AddMessage and type(coin) == "string" and coin:find("|T", 1, true) then
      chat:AddMessage("|cffe0c36aForever Forge|r: Repair All: not enough gold (need " .. coin .. ").")
    else
      FTK:Print("Repair All: not enough gold (need " .. coin .. ").")
    end
    return
  end

  if type(RepairAllItems) ~= "function" then
    FTK:Print("Repair All: RepairAllItems is not available on this client.")
    return
  end
  local ok = pcall(RepairAllItems, false)
  if ok then
    PrintRepair("Repair All: repaired for ", cost)
  else
    FTK:Print("Repair All: repair failed.")
  end
end

local function StartRepair(attempt)
  attempt = attempt or 0
  if attempt == 0 then
    session = session + 1
  end
  local token = session
  if not FTK:IsEnabled(MODULE_ID) then
    return
  end
  if not MerchantOpen() then
    if attempt < 10 then
      if C_Timer and C_Timer.After then
        C_Timer.After(0.1, function()
          if session == token then
            StartRepair(attempt + 1)
          end
        end)
      end
    end
    return
  end
  -- Brief delay so Auto-sell and merchant state settle without fighting hooks.
  if attempt == 0 and C_Timer and C_Timer.After then
    C_Timer.After(0.05, function()
      if session == token then
        TryRepair()
      end
    end)
    return
  end
  TryRepair()
end

local function HookMerchantFrame()
  local merchant = _G.MerchantFrame
  if not merchant or merchant.ftkRepairAllHook or not merchant.HookScript then
    return
  end
  merchant.ftkRepairAllHook = true
  merchant:HookScript("OnShow", function()
    StartRepair(0)
  end)
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
    setter(self:GetChecked() == true)
  end)
  local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  text:SetPoint("LEFT", box, "RIGHT", 4, 0)
  text:SetText(label)
  return y - 28
end

local function BuildOptions(_, parent)
  local y = -4
  local note = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  note:SetPoint("TOPLEFT", 0, y)
  note:SetWidth(420)
  note:SetJustifyH("LEFT")
  note:SetWordWrap(true)
  note:SetText("When you open a repair merchant, Repair All pays for every damaged equipped item. Non-repair vendors are skipped.")
  y = y - 40
  y = CheckLine(parent, "Use guild bank funds when available", y, function()
    return Config().useGuildFunds == true
  end, function(value)
    Config().useGuildFunds = value == true
  end)
  parent:SetHeight(80)
end

frame:SetScript("OnEvent", function(_, event)
  if event == "MERCHANT_CLOSED" then
    session = session + 1
    return
  end
  if event == "MERCHANT_SHOW" then
    HookMerchantFrame()
    StartRepair(0)
  end
end)

FTK:RegisterModule({
  id = MODULE_ID,
  name = "Repair All",
  description = "Repairs all gear at a repair merchant. Optional guild funds. Skips vendors that cannot repair.",
  defaultEnabled = true,
  BuildOptions = BuildOptions,
  onEnable = function()
    Config()
    frame:RegisterEvent("MERCHANT_SHOW")
    frame:RegisterEvent("MERCHANT_CLOSED")
    HookMerchantFrame()
    if MerchantOpen() then
      StartRepair(0)
    end
  end,
  onDisable = function()
    frame:UnregisterAllEvents()
    session = session + 1
  end,
})
