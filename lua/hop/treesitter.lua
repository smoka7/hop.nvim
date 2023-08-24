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

  local score = 2
  -- Create jump targets for node surroundings
  local a, b, c, d = node:range()
  -- Increment column to convert it to 1-index
  locations.jump_targets[1] = { buffer = 0, line = a, column = b + 1, length = 0, window = 0 }
  locations.indirect_jump_targets[1] = { index = 1, score = score }

  locations.jump_targets[2] = { buffer = 0, line = c, column = d, length = 0, window = 0 }
  locations.indirect_jump_targets[2] = { index = 2, score = score }

  -- Create jump targets for parents
  local parent = node:parent()
  while parent ~= nil do
    a, b, c, d = parent:range()
    -- TODO do not append duplicate jump targets
    locations.jump_targets[score + 1] = { buffer = 0, line = a, column = b + 1, length = 0, window = 0 }
    locations.indirect_jump_targets[score + 1] = { index = score + 1, score = score }
    locations.jump_targets[score + 2] = { buffer = 0, line = c, column = d, length = 0, window = 0 }
    locations.indirect_jump_targets[score + 2] = { index = score + 2, score = score }

    score = score + 2
    parent = parent:parent()
  end

  return locations
end

return T
