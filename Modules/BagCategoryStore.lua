--[[
  Own bag categories and the section order: storage and lookup.

  The player puts an item type (item id) into a category they name
  themselves. That choice wins over every default section of Clean Bags
  and Clean Bank. A category exists while at least one item type is in
  it. Category names ignore case.

  The player also sets the order of all sections, own categories and
  default sections alike. A section the player never moved keeps its
  default place: right after the section before it in the default order.

  Data is account-wide, in the Clean Bags config of ForeverForgeDB:
    customCategories = {
      names = { "Favorites", ... },     -- creation order
      items = { [itemID] = "Favorites" },
    }
    sectionOrder = { "quest", "custom:favorites", "set:PvP", ... }  -- group ids
  Every item id that reaches this file is a plain number, read through
  CleanBagRules.ReadItem, never a secret value.
]]

local FTK = ForeverForge
if not FTK then
  error("ForeverForge: Core.lua must load before Modules/BagCategoryStore.lua")
end

local CONFIG_MODULE_ID = "BagSections"
local ID_PREFIX = "custom:"
local MAX_NAME_LENGTH = 30

local Store = {
  MAX_NAME_LENGTH = MAX_NAME_LENGTH,
}

local pruned = false

-- Compare key of a category name.
local function KeyOf(name)
  return string.lower(name)
end

-- Length in characters, UTF-8 aware where the client offers it.
local function CharacterCount(name)
  if type(strlenutf8) == "function" then
    return strlenutf8(name)
  end
  return #name
end

-- Saved section order: a list of layout group ids, top to bottom.
local function SectionOrder()
  local config = FTK:GetConfig(CONFIG_MODULE_ID)
  if type(config.sectionOrder) ~= "table" then
    config.sectionOrder = {}
  end
  return config.sectionOrder
end

-- Position of a value in a list, compared exactly.
local function PositionOf(list, value)
  for index = 1, #list do
    if list[index] == value then
      return index
    end
  end
  return nil
end

-- Drops entries of the wrong type and own categories that no longer
-- exist from the section order.
local function PruneOrder(existing)
  local order = SectionOrder()
  local kept = {}
  for index = 1, #order do
    local id = order[index]
    if type(id) == "string" and id ~= "" and not PositionOf(kept, id) then
      if id:sub(1, #ID_PREFIX) ~= ID_PREFIX or existing[id:sub(#ID_PREFIX + 1)] then
        kept[#kept + 1] = id
      end
    end
  end
  for index = #order, 1, -1 do
    order[index] = nil
  end
  for index = 1, #kept do
    order[index] = kept[index]
  end
end

-- Keeps names and assignments in step: a name without items is dropped,
-- a name used by items but missing from the list goes to the end, and
-- entries of the wrong type are removed. The section order forgets the
-- dropped names.
local function Prune(data)
  local used = {}
  local invalid = {}
  for itemID, name in pairs(data.items) do
    if type(itemID) ~= "number" or type(name) ~= "string" or name == "" then
      invalid[#invalid + 1] = itemID
    else
      used[KeyOf(name)] = name
    end
  end
  for index = 1, #invalid do
    data.items[invalid[index]] = nil
  end

  local names = {}
  local seen = {}
  for index = 1, #data.names do
    local name = data.names[index]
    if type(name) == "string" then
      local key = KeyOf(name)
      if used[key] and not seen[key] then
        names[#names + 1] = name
        seen[key] = true
      end
    end
  end
  local missing = {}
  for key, name in pairs(used) do
    if not seen[key] then
      missing[#missing + 1] = name
    end
  end
  table.sort(missing)
  for index = 1, #missing do
    names[#names + 1] = missing[index]
  end
  data.names = names
  PruneOrder(used)
end

-- Saved category data. Missing tables are created, and the data is
-- pruned once per session.
local function Data()
  local config = FTK:GetConfig(CONFIG_MODULE_ID)
  local data = config.customCategories
  if type(data) ~= "table" then
    data = {}
    config.customCategories = data
  end
  if type(data.names) ~= "table" then
    data.names = {}
  end
  if type(data.items) ~= "table" then
    data.items = {}
  end
  if not pruned then
    Prune(data)
    pruned = true
  end
  return data
end

-- Trims a typed name and checks it.
-- Returns the clean name, or nil and the reason: "empty", "pipe" or "length".
local function CleanName(rawName)
  local name = (tostring(rawName or ""):gsub("^%s+", ""):gsub("%s+$", ""))
  if name == "" then
    return nil, "empty"
  end
  if name:find("|", 1, true) then
    return nil, "pipe"
  end
  if CharacterCount(name) > MAX_NAME_LENGTH then
    return nil, "length"
  end
  return name, nil
end

-- Position of a category name in a list, matched without case.
local function IndexOf(names, name)
  local key = KeyOf(name)
  for index = 1, #names do
    if KeyOf(names[index]) == key then
      return index
    end
  end
  return nil
end

-- Stored spelling of a category name, matched without case.
local function FindName(names, name)
  local index = IndexOf(names, name)
  return index and names[index] or nil
end

-- Own category of an item type.
-- Returns the layout group id ("custom:<name>") and the display name, or nil.
function Store:CategoryOf(itemID)
  if type(itemID) ~= "number" then
    return nil, nil
  end
  local name = Data().items[itemID]
  if type(name) ~= "string" then
    return nil, nil
  end
  return ID_PREFIX .. KeyOf(name), name
end

-- All own categories in creation order (a copy).
function Store:Names()
  local names = Data().names
  local copy = {}
  for index = 1, #names do
    copy[index] = names[index]
  end
  return copy
end

-- Puts an item type into a category and creates the category when needed.
-- Returns true, or false and the reason: "item", "empty", "pipe" or "length".
function Store:Assign(itemID, rawName)
  if type(itemID) ~= "number" then
    return false, "item"
  end
  local name, problem = CleanName(rawName)
  if not name then
    return false, problem
  end
  local data = Data()
  local existing = FindName(data.names, name)
  if existing then
    name = existing
  else
    data.names[#data.names + 1] = name
  end
  data.items[itemID] = name
  Prune(data)
  return true, nil
end

-- Returns an item type to the default sections. A category left empty
-- by this disappears.
function Store:Reset(itemID)
  if type(itemID) ~= "number" then
    return
  end
  local data = Data()
  data.items[itemID] = nil
  Prune(data)
end

-- Sorts the groups of a layout (each with an id), given in default
-- order, into the player's section order. A group missing from the saved
-- order follows the group before it in the default order; several such
-- groups in a row keep their default order.
function Store:SortGroups(groups)
  Data()
  local rank = {}
  local order = SectionOrder()
  for index = 1, #order do
    rank[order[index]] = index
  end
  local entries = {}
  local anchor = 0
  local step = 0
  for index = 1, #groups do
    local id = groups[index].id
    local key
    if rank[id] then
      anchor = rank[id]
      step = 0
      key = anchor
    else
      step = step + 1
      key = anchor + (step / (#groups + 1))
    end
    entries[index] = { group = groups[index], key = key, index = index }
  end
  table.sort(entries, function(a, b)
    if a.key ~= b.key then
      return a.key < b.key
    end
    return a.index < b.index
  end)
  for index = 1, #entries do
    groups[index] = entries[index].group
  end
end

-- Moves a section one step up (direction -1) or down (direction 1), past
-- its neighbour in visibleIDs, the group ids shown in the same window
-- from top to bottom. Sections not shown there keep their order among
-- themselves. Returns true when the order changed.
function Store:MoveSection(id, direction, visibleIDs)
  if type(id) ~= "string" or (direction ~= -1 and direction ~= 1) or type(visibleIDs) ~= "table" then
    return false
  end
  local position = PositionOf(visibleIDs, id)
  local neighbour = position and visibleIDs[position + direction]
  if not neighbour then
    return false
  end
  Data()
  local order = SectionOrder()
  -- A shown section missing from the saved order goes in right after the
  -- section shown above it, so the saved order matches the window.
  for index = 1, #visibleIDs do
    local shown = visibleIDs[index]
    if not PositionOf(order, shown) then
      local above = 0
      if index > 1 then
        above = PositionOf(order, visibleIDs[index - 1]) or 0
      end
      table.insert(order, above + 1, shown)
    end
  end
  local moved = table.remove(order, PositionOf(order, id))
  local to = PositionOf(order, neighbour)
  if direction == 1 then
    to = to + 1
  end
  table.insert(order, to, moved)
  return true
end

-- Group ids of the own categories in a layout that hold items, in
-- creation order (their default order).
function Store:OrderedGroupIDs(groupOrder, groups)
  local rank = {}
  local names = Data().names
  for index = 1, #names do
    rank[ID_PREFIX .. KeyOf(names[index])] = index
  end
  local ids = {}
  for index = 1, #groupOrder do
    local id = groupOrder[index]
    local group = groups[id]
    if rank[id] and group and #group.items > 0 then
      ids[#ids + 1] = id
    end
  end
  table.sort(ids, function(a, b)
    return rank[a] < rank[b]
  end)
  return ids
end

FTK.BagCategoryStore = Store
