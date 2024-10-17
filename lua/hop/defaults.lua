---@class Options
---@field direction HintDirection
---@field loaded_mappings any
local M = {}

local hint = require('hop.hint')

M.keys = 'asdghklqwertyuiopzxcvbnmfj'
M.quit_key = '<Esc>'
M.perm_method = require('hop.perm').TrieBacktrackFilling
M.reverse_distribution = false
M.x_bias = 10
M.distance_method = hint.manh_distance
M.teasing = true
M.virtual_cursor = false
M.jump_on_sole_occurrence = true
M.case_insensitive = true
M.create_hl_autocmd = true
M.current_line_only = false
M.dim_unmatched = true
M.hl_mode = "combine"
M.uppercase_labels = false
M.multi_windows = false
M.windows_list = function ()
  return vim.api.nvim_tabpage_list_wins(0)
end
M.ignore_injections = false
M.hint_position = hint.HintPosition.BEGIN ---@type HintPosition
M.hint_offset = 0 ---@type WindowCell
M.hint_type = hint.HintType.OVERLAY ---@type HintType
M.excluded_filetypes = {}
M.match_mappings = {}
M.extensions = { 'hop-yank', 'hop-treesitter' }

return M
