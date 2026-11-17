--[[
  Section flow for Clean Bags and Clean Bank.

  Places sections in order, left to right and top to bottom. A section
  is as many columns wide as it has slots, up to the full width, and its
  label can make it wider. A section that fits next to the one before it
  shares that row; otherwise it starts a new row below the tallest
  section of the row above. Only sections of a single row of items are
  narrow enough to share a row, so large sections keep the full width.

  Pure arithmetic: no frames, no game API.
]]

local FTK = ForeverForge
if not FTK then
  error("ForeverForge: Core.lua must load before Modules/BagSectionFlow.lua")
end

local Flow = {}

-- Width of a grid of `columns` item buttons.
function Flow.GridWidth(columns, metrics)
  return (columns * metrics.buttonWidth) + ((columns - 1) * metrics.gapX)
end

-- Number of item columns that fit into `width`, after `margin` for the
-- window edges, kept between minColumns and maxColumns.
function Flow.ColumnsForWidth(width, margin, metrics, minColumns, maxColumns)
  local columns = math.floor((width - margin + metrics.gapX) / (metrics.buttonWidth + metrics.gapX))
  if columns < minColumns then
    return minColumns
  end
  if columns > maxColumns then
    return maxColumns
  end
  return columns
end

-- Arranges sections. Each section is { count, headerWidth }: count is the
-- number of item buttons, headerWidth the width its label needs.
-- metrics: columns, buttonWidth, buttonHeight, gapX, gapY, headerHeight,
-- headerGap (label to items), rowGap (between rows of sections) and
-- blockGap (between sections in one row).
-- Returns one block { x, y, width, columns } per section, with x and y
-- measured from the top left of the content, and the content height.
function Flow.Arrange(sections, metrics)
  local gridWidth = Flow.GridWidth(metrics.columns, metrics)
  local blocks = {}
  local x, y, rowHeight = 0, 0, 0
  for index = 1, #sections do
    local section = sections[index]
    local count = math.max(section.count or 0, 1)
    local columns = math.min(count, metrics.columns)
    local rows = math.ceil(count / columns)
    local width = math.min(math.max(Flow.GridWidth(columns, metrics), section.headerWidth or 0), gridWidth)
    local height = metrics.headerHeight + metrics.headerGap
      + (rows * metrics.buttonHeight) + ((rows - 1) * metrics.gapY)
    if x > 0 and x + width > gridWidth then
      y = y + rowHeight + metrics.rowGap
      x = 0
      rowHeight = 0
    end
    blocks[index] = { x = x, y = y, width = width, columns = columns }
    x = x + width + metrics.blockGap
    if height > rowHeight then
      rowHeight = height
    end
  end
  return blocks, y + rowHeight
end

-- Position of the item at `index` (1-based) of a block, measured from the
-- top left of the content.
function Flow.ItemOffset(block, index, metrics)
  local column = (index - 1) % block.columns
  local row = math.floor((index - 1) / block.columns)
  local x = block.x + (column * (metrics.buttonWidth + metrics.gapX))
  local y = block.y + metrics.headerHeight + metrics.headerGap + (row * (metrics.buttonHeight + metrics.gapY))
  return x, y
end

FTK.BagSectionFlow = Flow
