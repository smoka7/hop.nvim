local jump_targets = require('hop.jump_target')
local parsers = require('nvim-treesitter.parsers')

local T = {}

T.run = function()
  ---@param opts Options
  ---@return Locations
  return function(opts)
    local Locations = T.parse()
    jump_targets.sort_indirect_jump_targets(Locations.indirect_jump_targets, opts)
    return Locations
  end
end

---
---@param targets JumpTarget[]
---@param row integer
---@param col integer
---@return boolean
local function duplicate(targets, row, col)
  for _, j in pairs(targets) do
    if j.line == row and j.column == col + 1 then
      return true
    end
  end
  return false
end

---
---@return Locations
T.parse = function()
  ---@type Locations
  local locations = {
    jump_targets = {},
    indirect_jump_targets = {},
  }

  -- Check if buffer has a parser
  local parser = parsers.get_parser()
  if not parser then
    return locations
  end
  local root = parser:parse()[1]:root()

  -- Get the node at current cursor position
  local here = vim.api.nvim_win_get_cursor(0)
  ---@type TSNode
  local node = root:named_descendant_for_range(here[1] - 1, here[2], here[1] - 1, here[2] + 1)

  if not node then
    return locations
  end

  local append = function(row, col)
    if duplicate(locations.jump_targets, row, col) then
      return
    end

    local len = #locations.jump_targets + 1
    -- Increment column to convert it to 1-index
    locations.jump_targets[len] = { buffer = 0, line = row, column = col + 1, length = 0, window = 0 }
    locations.indirect_jump_targets[len] = { index = len, score = len }
  end

  -- Create jump targets for node surroundings
  local a, b, c, d = node:range()
  append(a, b)
  append(c, d)

  -- Create jump targets for parents
  local parent = node:parent()
  while parent ~= nil do
    -- Don't create a jump target for root
    if parent:equal(root) then
      return locations
    end

    a, b, c, d = parent:range()
    append(a, b)
    append(c, d)

    parent = parent:parent()
  end

  return locations
end

return T
